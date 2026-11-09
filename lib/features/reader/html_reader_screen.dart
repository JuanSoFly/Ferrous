import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:reader_app/features/reader/widgets/html_table_viewer.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:uuid/uuid.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/annotations/annotation_detail_sheet.dart';
import 'package:reader_app/features/reader/annotation_highlight_helper.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/controllers/html_tts_controller.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/features/reader/widgets/book_background_texture.dart';
import 'package:reader_app/features/reader/widgets/book_cover_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reader_app/core/services/diagnostic_logger.dart';
import 'package:reader_app/features/reader/widgets/reader_error_view.dart';

/// Represents a Table of Contents entry extracted from an HTML document.
class HtmlTocEntry {
  final String title;
  final int level;
  final String? anchor;
  final double estimatedFraction;

  const HtmlTocEntry({
    required this.title,
    required this.level,
    this.anchor,
    required this.estimatedFraction,
  });
}

/// Shared base class for HTML-based text readers (DOCX, MOBI, TXT).
abstract class HtmlReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const HtmlReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });
}

/// Configuration for HTML reader styling.
class HtmlReaderConfig {
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double webtoonSpacing;
  final String errorPrefix;

  const HtmlReaderConfig({
    this.fontSize = 12.0,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 20.0,
    this.webtoonSpacing = 28.0,
    this.errorPrefix = 'Error',
  });

  static const docx = HtmlReaderConfig(
    fontSize: 12.0,
    lineHeight: 1.5,
    paragraphSpacing: 20.0,
    webtoonSpacing: 28.0,
    errorPrefix: 'Error loading DOCX',
  );

  static const mobi = HtmlReaderConfig(
    fontSize: 12.0,
    lineHeight: 1.8,
    paragraphSpacing: 20.0,
    webtoonSpacing: 28.0,
    errorPrefix: 'Error',
  );
}

abstract class HtmlReaderScreenState<T extends HtmlReaderScreen> extends State<T>
    with WidgetsBindingObserver {
  String? _htmlContent;
  String? _processedHtml;
  bool _processedWithHyphenation = false;
  bool _processedWithIndent = false;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  ResolvedBookFile? _resolvedFile;
  String _plainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  List<HtmlTocEntry> _tocEntries = const [];
  late ReadingMode _readingMode;
  late double _lastScrollPosition;

  // Shared chrome controller for UI visibility and lock mode
  final ReaderChromeController _chromeController = ReaderChromeController();
  Offset? _lastDoubleTapDown;
  SelectedContent? _selectedContent;

  // Font preloading
  String _lastLoadedFontFamily = '';
  ReaderThemeRepository? _themeRepository;

  // TTS implementation
  late final TtsService _ttsService;
  late final HtmlTtsController _ttsController;

  /// Override to provide reader-specific configuration.
  HtmlReaderConfig get config;

  /// Override to load content from the format-specific API.
  Future<String> loadContent(String path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HyphenationHelper.init();
    _readingMode = widget.book.readingMode;
    _lastScrollPosition = widget.book.scrollPosition;
    _chromeController.addListener(_onChromeChanged);

    _ttsService = TtsService();
    _ttsController = HtmlTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: _ttsService,
      scrollController: _scrollController,
      getPlainText: () => _plainText,
    );

    _loadDocument();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeController.enterImmersiveMode();
      // Listen for font changes
      _themeRepository = context.read<ReaderThemeRepository>();
      _themeRepository?.addListener(_onThemeChanged);
    });
  }

  @override
  void dispose() {
    _themeRepository?.removeListener(_onThemeChanged);
    _cleanupTempFile();
    _scrollController.dispose();
    _chromeController.removeListener(_onChromeChanged);
    _chromeController.exitToNormalMode();
    _ttsController.dispose();
    _ttsService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onChromeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDocument() async {
    // Capture theme repository before async operations
    final themeRepo = context.read<ReaderThemeRepository>();

    try {
      final resolver = BookFileResolver();
      final resolved = await resolver.resolve(widget.book);
      _resolvedFile = resolved;
      final rawHtml = await loadContent(resolved.path);
      final html = HyphenationHelper.injectIndentTags(rawHtml);

      // Run expensive text processing in background isolates
      final plainTextFuture = compute(_htmlToPlainTextStatic, rawHtml);
      final sentenceSpansFuture = plainTextFuture.then(
        (plainText) => compute(splitIntoSentences, plainText),
      );
      final tocEntriesFuture = compute(_htmlToTocStatic, html);

      // Precompute hyphenation in background if enabled.
      final shouldHyphenate = themeRepo.config.hyphenation;
      final shouldIndent = themeRepo.config.paragraphIndent;
      Future<String?> processedHtmlFuture;
      if (shouldHyphenate || shouldIndent) {
        processedHtmlFuture = compute(
          HyphenationHelper.processHtmlAndIndentIsolated,
          {
            'html': html,
            'hyphenation': shouldHyphenate,
            'paragraphIndent': shouldIndent,
          },
        );
      } else {
        processedHtmlFuture = Future.value(null);
      }

      // Preload the current font family before rendering
      final fontFamily = themeRepo.config.fontFamily;
      await _preloadFont(fontFamily);
      _lastLoadedFontFamily = fontFamily;

      final plainText = await plainTextFuture;
      final sentenceSpans = await sentenceSpansFuture;
      final processedHtml = await processedHtmlFuture;
      final tocEntries = await tocEntriesFuture;

      setState(() {
        _htmlContent = html;
        _plainText = plainText;
        _sentenceSpans = sentenceSpans;
        _processedHtml = processedHtml;
        _processedWithHyphenation = shouldHyphenate;
        _processedWithIndent = shouldIndent;
        _tocEntries = tocEntries;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
      });
    } catch (e, stack) {
      DiagnosticLogger.instance.logError(widget.book.format.toUpperCase(), e, stack);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Called when theme settings change - preload font if it changed,
  /// recompute hyphenation if the setting was toggled.
  void _onThemeChanged() {
    final themeConfig = _themeRepository?.config;
    if (themeConfig == null) return;

    // Handle font family changes
    final newFontFamily = themeConfig.fontFamily;
    if (newFontFamily.isNotEmpty && newFontFamily != _lastLoadedFontFamily) {
      _lastLoadedFontFamily = newFontFamily;
      _preloadFont(newFontFamily).then((_) {
        if (mounted) setState(() {});
      });
    }

    // Handle hyphenation and paragraph indent toggles at runtime
    if (_htmlContent != null) {
      final shouldHyphenate = themeConfig.hyphenation;
      final shouldIndent = themeConfig.paragraphIndent;

      if (shouldHyphenate != _processedWithHyphenation ||
          shouldIndent != _processedWithIndent) {
        if (!shouldHyphenate && !shouldIndent) {
          setState(() {
            _processedHtml = null;
            _processedWithHyphenation = false;
            _processedWithIndent = false;
          });
        } else {
          compute(
            HyphenationHelper.processHtmlAndIndentIsolated,
            {
              'html': _htmlContent!,
              'hyphenation': shouldHyphenate,
              'paragraphIndent': shouldIndent,
            },
          ).then((result) {
            if (mounted) {
              setState(() {
                _processedHtml = result;
                _processedWithHyphenation = shouldHyphenate;
                _processedWithIndent = shouldIndent;
              });
            }
          });
        }
      }
    }
  }

  /// Preload the specified font family to ensure it's available before rendering.
  Future<void> _preloadFont(String fontFamily) async {
    try {
      GoogleFonts.getFont(fontFamily);
      await GoogleFonts.pendingFonts();
    } catch (e) {
      debugPrint('Failed to preload font $fontFamily: $e');
    }
  }

  void _cleanupTempFile() {
    final resolved = _resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      unawaited(File(resolved.path).delete());
    } catch (_) {
      // Ignore cleanup failures
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveScrollProgress();
      _ttsController.saveCurrentTtsSentence();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final screenSize = MediaQuery.of(context).size;
    if (_chromeController.isCenterTap(details.globalPosition, screenSize)) {
      _chromeController.toggleChrome();
      if (!_chromeController.showChrome) {
        _ttsController.setTtsControlsVisible(false);
      }
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!_chromeController.isLocked) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    final screenSize = MediaQuery.of(context).size;
    if (_chromeController.isCenterTap(position, screenSize)) {
      _toggleLockModeWithFeedback();
    }
  }

  void _toggleLockModeWithFeedback() {
    final isLocked = _chromeController.toggleLockMode();
    if (isLocked) {
      _ttsController.setTtsControlsVisible(false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLocked
                ? 'Lock mode on. Double-tap center to unlock.'
                : 'Lock mode off.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.text,
    );
    if (selected == null || selected == _readingMode) return;
    setState(() => _readingMode = selected);
    widget.repository.updateReadingProgress(
      widget.book.id,
      readingMode: selected,
    );
  }

  void _showSettingsSheet() {
    AppTheme? currentTheme;
    try {
      currentTheme = context.read<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: isEInk ? Colors.transparent : null,
      builder: (context) => const ReaderSettingsSheet(),
    );
  }

  void _restoreScrollPosition() {
    if (!_scrollController.hasClients) return;
    if (_lastScrollPosition <= 0) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final clamped = _lastScrollPosition.clamp(0.0, maxExtent);
    _scrollController.jumpTo(clamped);
  }

  void _saveScrollProgress() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.offset;
    _lastScrollPosition = currentScroll;
    final text = _plainText;
    if (text.trim().isNotEmpty) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final fraction = maxExtent <= 0 ? 0.0 : (currentScroll / maxExtent);
      final maxIndex = text.length - 1;
      final approxIndex =
          maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);
      final span =
          sentenceForOffset(_sentenceSpans, approxIndex) ?? SentenceSpan(0, text.length);
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: 1,
        totalPages: 1,
        scrollPosition: currentScroll,
        lastReadingSentenceStart: span.start,
        lastReadingSentenceEnd: span.end,
      );
      return;
    }
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: 1,
      totalPages: 1,
      scrollPosition: currentScroll,
    );
  }

  void _scrollToFraction(double fraction) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final target = (fraction * maxExtent).clamp(0.0, maxExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToAnchor(String anchor) {
    final cleanAnchor = anchor.replaceAll('#', '').toLowerCase();
    if (cleanAnchor.isEmpty) return;

    for (final entry in _tocEntries) {
      if (entry.anchor?.toLowerCase() == cleanAnchor) {
        _scrollToFraction(entry.estimatedFraction);
        return;
      }
    }

    final html = _htmlContent;
    if (html != null && _scrollController.hasClients) {
      final matchPatterns = [
        'id="$cleanAnchor"',
        "id='$cleanAnchor'",
        'name="$cleanAnchor"',
        "name='$cleanAnchor'",
      ];
      int targetIdx = -1;
      final lowerHtml = html.toLowerCase();
      for (final pat in matchPatterns) {
        final pos = lowerHtml.indexOf(pat);
        if (pos != -1) {
          targetIdx = pos;
          break;
        }
      }
      if (targetIdx != -1) {
        final fraction = (targetIdx / html.length).clamp(0.0, 1.0);
        _scrollToFraction(fraction);
      }
    }
  }

  void _showTocSheet() {
    if (_tocEntries.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, sheetScrollController) {
            final theme = Theme.of(context);
            AppTheme? currentTheme;
            try {
              currentTheme = context.watch<AppTheme?>();
            } catch (_) {}
            final isEInk = currentTheme == AppTheme.eInk;

            return Container(
              decoration: BoxDecoration(
                color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(isEInk ? 2 : 16)),
                border: isEInk ? const Border(top: BorderSide(color: Color(0xFF1A1A18), width: 1.5)) : null,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        Icon(Icons.list, size: 24, color: isEInk ? const Color(0xFF1A1A18) : null),
                        const SizedBox(width: 8),
                        Text(
                          'Table of Contents',
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: const Color(0xFF1A1A18),
                                )
                              : theme.textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: isEInk ? const Color(0xFF1A1A18) : null),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: isEInk ? const Color(0xFFC2BEB4) : null),
                  Expanded(
                    child: ListView.separated(
                      controller: sheetScrollController,
                      itemCount: _tocEntries.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: isEInk ? const Color(0xFFC2BEB4) : theme.dividerColor.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, index) {
                        final entry = _tocEntries[index];
                        final indent = ((entry.level - 1).clamp(0, 4)) * 16.0;
                        final isH1 = entry.level == 1;

                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: 16.0 + indent,
                            right: 16.0,
                          ),
                          title: Text(
                            entry.title,
                            style: isEInk
                                ? GoogleFonts.robotoSlab(
                                    fontWeight: isH1 ? FontWeight.bold : FontWeight.normal,
                                    fontSize: isH1 ? 15.0 : 14.0,
                                    color: const Color(0xFF1A1A18),
                                  )
                                : TextStyle(
                                    fontWeight: isH1 ? FontWeight.bold : FontWeight.normal,
                                    fontSize: isH1 ? 15.0 : 14.0,
                                  ),
                          ),
                          trailing: entry.estimatedFraction > 0.0
                              ? Text(
                                  '${(entry.estimatedFraction * 100).toStringAsFixed(0)}%',
                                  style: isEInk
                                      ? const TextStyle(
                                          color: Color(0xFF3D3C38),
                                          fontSize: 12,
                                        )
                                      : theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _scrollToFraction(entry.estimatedFraction);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAnnotationDialog(String selectedText) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AnnotationDialog(selectedText: selectedText),
    );

    if (result != null && mounted) {
      final note = (result['note'] as String?)?.trim();
      final color = result['color'] as int? ?? 0xFFFFF176;

      final cleanSelected = selectedText.replaceAll('\u00AD', '');
      int start = _plainText.indexOf(cleanSelected);
      if (start == -1) start = _plainText.indexOf(selectedText);
      int end = start != -1 ? start + cleanSelected.length : cleanSelected.length;
      if (start == -1) start = 0;

      final annotation = Annotation(
        id: const Uuid().v4(),
        bookId: widget.book.id,
        selectedText: selectedText,
        note: note != null && note.isNotEmpty ? note : null,
        chapterIndex: widget.book.sectionIndex,
        startOffset: start,
        endOffset: end,
        color: color,
        createdAt: DateTime.now(),
      );

      await context.read<AnnotationRepository>().addAnnotation(annotation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Annotation saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  static String _htmlToPlainTextStatic(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parse(html);
    document.querySelectorAll('script,style,noscript').forEach((e) => e.remove());
    return DomTextUtils.extractPlainText(document.body ?? document.documentElement);
  }

  static List<HtmlTocEntry> _htmlToTocStatic(String html) {
    if (html.trim().isEmpty) return const [];
    final document = html_parser.parse(html);
    final totalLength = html.length;
    if (totalLength == 0) return const [];

    final entries = <HtmlTocEntry>[];
    final seenTitles = <String>{};

    // 1. Look for explicit TOC elements / links (from DOCX <a class="toc-link">, <p class="toc-entry">)
    final tocElements = document.querySelectorAll('.toc-entry, .toc-link');
    if (tocElements.isNotEmpty) {
      for (final elem in tocElements) {
        final text = elem.text.trim();
        if (text.isEmpty || seenTitles.contains(text)) continue;

        var level = 1;
        final className = elem.className.toLowerCase();
        if (className.contains('level-2') || className.contains('toc2') || className.contains('toc-2')) {
          level = 2;
        } else if (className.contains('level-3') || className.contains('toc3') || className.contains('toc-3')) {
          level = 3;
        } else if (className.contains('level-4') || className.contains('toc4') || className.contains('toc-4')) {
          level = 4;
        }

        final anchor = elem.attributes['href']?.replaceAll('#', '') ??
            elem.querySelector('a')?.attributes['href']?.replaceAll('#', '');

        double fraction = 0.0;
        if (anchor != null && anchor.isNotEmpty) {
          final targetIndex = html.indexOf(anchor);
          if (targetIndex != -1) {
            fraction = (targetIndex / totalLength).clamp(0.0, 1.0);
          }
        }
        if (fraction == 0.0) {
          final textIndex = html.indexOf(text);
          if (textIndex != -1) {
            fraction = (textIndex / totalLength).clamp(0.0, 1.0);
          }
        }

        seenTitles.add(text);
        entries.add(HtmlTocEntry(
          title: text,
          level: level,
          anchor: anchor,
          estimatedFraction: fraction,
        ));
      }
    }

    // 2. Document Headings (h1, h2, h3, h4, h5, h6)
    final headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
    for (final h in headings) {
      final text = h.text.trim();
      if (text.isEmpty || seenTitles.contains(text)) continue;
      if (h.className.contains('toc-heading')) continue; // Skip TOC title block

      final tagName = h.localName?.toLowerCase() ?? 'h1';
      final level = int.tryParse(tagName.replaceAll('h', '')) ?? 1;

      final anchor = h.id.isNotEmpty
          ? h.id
          : (h.querySelector('a[id]')?.attributes['id'] ??
              h.previousElementSibling?.attributes['id']);

      double fraction = 0.0;
      final indexInHtml = html.indexOf(h.outerHtml);
      if (indexInHtml != -1) {
        fraction = (indexInHtml / totalLength).clamp(0.0, 1.0);
      } else {
        final textIndex = html.indexOf(text);
        if (textIndex != -1) {
          fraction = (textIndex / totalLength).clamp(0.0, 1.0);
        }
      }

      seenTitles.add(text);
      entries.add(HtmlTocEntry(
        title: text,
        level: level,
        anchor: anchor,
        estimatedFraction: fraction,
      ));
    }

    // Keep chronological document order
    entries.sort((a, b) => a.estimatedFraction.compareTo(b.estimatedFraction));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        _chromeController,
        _ttsController,
      ]),
      builder: (context, _) {
        final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
        final showTtsControls = showChrome && _ttsController.showTtsControls;

        return Scaffold(
          body: PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) {
                _saveScrollProgress();
                _ttsController.saveCurrentTtsSentence();
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: _handleTapUp,
                    onDoubleTapDown: _handleDoubleTapDown,
                    onDoubleTap: _handleDoubleTap,
                    child: RealBookBackground(
                      textureId: themeRepo.config.paperTexture,
                      showSpine: themeRepo.config.showBookSpine,
                      child: _buildBody(),
                    ),
                  ),
                ),
                if (showChrome) _buildTopBar(),
                if (showTtsControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: TtsControlsSheet(
                      ttsService: _ttsController.ttsService,
                      textToSpeak: '',
                      resolveTextToSpeak: () => _ttsController.resolveTtsText(),
                      onStart: () async {
                        final text = _ttsController.resolveTtsText();
                        if (text.trim().isNotEmpty) {
                          await _ttsController.ttsService.speak(text);
                        }
                      },
                      isContinuous: _ttsController.ttsContinuous,
                      isFollowMode: _ttsController.ttsFollowMode,
                      isTapToStart: _ttsController.tapToStartEnabled,
                      onContinuousChanged: _ttsController.setTtsContinuous,
                      onFollowModeChanged: _ttsController.setTtsFollowMode,
                      onTapToStartChanged: _ttsController.setTapToStartEnabled,
                      onClose: _ttsController.closeTtsControls,
                      highlightStyle: themeRepo.highlightStyle,
                      onHighlightStyleChanged: themeRepo.setTtsHighlightStyle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final currentTheme = context.watch<AppTheme?>();
      final isEInk = currentTheme == AppTheme.eInk;
      return ReaderErrorView(
        formatTitle: widget.book.format.toUpperCase(),
        error: _error!,
        isEInk: isEInk,
      );
    }

    final isTtsActive = _ttsController.showTtsControls ||
        _ttsController.ttsService.state != TtsState.stopped;

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        if (scrollNotification is ScrollEndNotification) {
          _saveScrollProgress();
        }
        return true;
      },
      child: SelectionArea(
        onSelectionChanged: (content) {
          _selectedContent = content;
        },
        contextMenuBuilder: (context, selectableRegionState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: [
              ContextMenuButtonItem(
                label: 'Annotate',
                onPressed: () {
                  final text = _selectedContent?.plainText.trim() ?? '';
                  selectableRegionState.hideToolbar();
                  if (text.isNotEmpty) {
                    _showAnnotationDialog(text);
                  }
                },
              ),
              ...selectableRegionState.contextMenuButtonItems,
            ],
          );
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16.0),
          child: Consumer<ReaderThemeRepository>(
            builder: (context, themeRepo, _) {
              final themeConfig = themeRepo.config;
              final annotationRepo = context.watch<AnnotationRepository>();
              final bookAnnotations = annotationRepo.getAnnotationsForBook(widget.book.id);
              final spacing = themeConfig.paragraphSpacing;

              // Margins
              final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;

              final baseHtml = (themeConfig.hyphenation || themeConfig.paragraphIndent)
                  ? (_processedHtml ?? _htmlContent ?? '')
                  : (_htmlContent ?? '');

              final extensions = [
                TagWrapExtension(
                  tagsToWrap: {'table'},
                  builder: (child) => HtmlTableViewer(child: child),
                ),
                const TableHtmlExtension(),
                TagExtension.inline(
                  tagsToExtend: {'p-indent', 'indent'},
                  builder: (ctx) {
                    if (!themeConfig.paragraphIndent) {
                      return const TextSpan(text: '');
                    }
                    final indentWidth = (themeConfig.fontSize * 1.6).clamp(18.0, 42.0);
                    return WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: SizedBox(
                        width: indentWidth,
                        height: 1.0,
                      ),
                    );
                  },
                ),
                TagExtension(
                  tagsToExtend: {'tts-highlight'},
                  builder: (ctx) {
                    final text = ctx.node.text ?? '';
                    final style =
                        ctx.style?.generateTextStyle() ?? const TextStyle();
                    return _TtsHighlightSpan(
                      key: _ttsController.ttsHighlightKey,
                      text: text,
                      textStyle: style,
                      highlightStyle: themeRepo.highlightStyle,
                    );
                  },
                ),
                TagExtension.inline(
                  tagsToExtend: {AnnotationHighlightHelper.highlightTag},
                  builder: (ctx) {
                    final text = ctx.node.text ?? '';
                    final id = ctx.attributes['data-id'] ?? '';
                    AppTheme? currentTheme;
                    try {
                      currentTheme = context.watch<AppTheme?>();
                    } catch (_) {}
                    final isEInk = currentTheme == AppTheme.eInk;
                    final colorVal = int.tryParse(ctx.attributes['data-color'] ?? '') ?? 0xFFFFF176;
                    final color = isEInk ? const Color(0xFFD5D0C5) : Color(colorVal);
                    final style = ctx.style?.generateTextStyle() ?? const TextStyle();
                    final highlightStyle = style.copyWith(
                      backgroundColor: isEInk ? const Color(0xFFD5D0C5) : color.withValues(alpha: 0.35),
                      color: isEInk ? const Color(0xFF1A1A18) : null,
                    );

                    void handleTap() {
                      final all = annotationRepo.getAllAnnotations();
                      final target = all.cast<Annotation?>().firstWhere(
                            (a) => a?.id == id,
                            orElse: () => null,
                          );
                      if (target != null) {
                        showAnnotationDetailSheet(context, target);
                      }
                    }

                    final children = ctx.inlineSpanChildren;
                    if (children != null && children.isNotEmpty) {
                      return TextSpan(
                        children: children,
                        style: highlightStyle,
                        recognizer: TapGestureRecognizer()..onTap = handleTap,
                      );
                    }
                    return TextSpan(
                      text: text,
                      style: highlightStyle,
                      recognizer: TapGestureRecognizer()..onTap = handleTap,
                    );
                  },
                ),
              ];

            AppTheme? currentTheme;
            try {
              currentTheme = context.watch<AppTheme?>();
            } catch (_) {}
            final isEInk = currentTheme == AppTheme.eInk;

            final textureInfo = BookTextures.getById(themeConfig.paperTexture);
            final effectiveTextColor = isEInk
                ? const Color(0xFF1A1A18)
                : (themeConfig.paperTexture != BookTextures.none
                    ? textureInfo.textColor
                    : Theme.of(context).textTheme.bodyLarge?.color);

            Widget buildHtmlWidget(String displayContent) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Html(
                  data: displayContent,
                  extensions: extensions,
                  onLinkTap: (url, attributes, element) async {
                    if (url == null || url.isEmpty) return;
                    if (url.startsWith('#')) {
                      _scrollToAnchor(url);
                    } else {
                      final uri = Uri.tryParse(url);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  style: {
                    "body": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      fontWeight: FontWeight.values[(themeConfig.fontWeight ~/ 100).clamp(0, 8)],
                      color: effectiveTextColor,
                      textAlign: _parseTextAlign(themeConfig.textAlign),
                      letterSpacing: themeConfig.wordSpacing,
                      padding: HtmlPaddings.zero,
                      margin: Margins.zero,
                    ),
                    "a": Style(
                      color: isEInk ? const Color(0xFF1A1A18) : Theme.of(context).colorScheme.primary,
                    ),
                    "tts-highlight": Style(
                      backgroundColor: isEInk
                          ? const Color(0xFFD5D0C5)
                          : Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.3),
                      color: isEInk ? const Color(0xFF1A1A18) : null,
                    ),
                    "p": Style(
                      margin: Margins.only(
                        bottom: spacing,
                        top: 0,
                      ),
                      textAlign: _parseTextAlign(themeConfig.textAlign),
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                    ),
                    "div": Style(
                      margin: Margins.only(
                        bottom: spacing,
                        top: 0,
                      ),
                      textAlign: _parseTextAlign(themeConfig.textAlign),
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                    ),
                    "span": Style(
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                    ),
                    "img": Style(
                      width: Width(100, Unit.percent),
                      margin: Margins.only(bottom: 24.0),
                    ),
                    "h1": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.5),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                      margin: Margins.only(top: 24, bottom: 12),
                    ),
                    "h2": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.35),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                      margin: Margins.only(top: 20, bottom: 10),
                    ),
                    "h3": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.2),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                      margin: Margins.only(top: 18, bottom: 8),
                    ),
                    "h4": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.1),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? Colors.transparent : null,
                      margin: Margins.only(top: 16, bottom: 8),
                    ),
                    "ul": Style(
                      padding: HtmlPaddings.only(left: 20),
                      margin: Margins.only(bottom: spacing, top: 0),
                    ),
                    "ol": Style(
                      padding: HtmlPaddings.only(left: 20),
                      margin: Margins.only(bottom: spacing, top: 0),
                    ),
                    "li": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: isEInk ? effectiveTextColor : Theme.of(context).textTheme.bodyLarge?.color,
                      backgroundColor: isEInk ? Colors.transparent : null,
                      margin: Margins.only(bottom: 6),
                    ),
                    "table": Style(
                      width: Width(100, Unit.percent),
                      margin: Margins.symmetric(vertical: 14.0),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.0),
                    ),
                    "th": Style(
                      padding: HtmlPaddings.symmetric(horizontal: 8.0, vertical: 6.0),
                      backgroundColor: isEInk ? const Color(0xFFE0DCD3) : Theme.of(context).colorScheme.surfaceContainerHigh,
                      fontWeight: FontWeight.bold,
                      fontSize: FontSize((themeConfig.fontSize * 0.85).clamp(11.0, 15.0)),
                      lineHeight: LineHeight(1.25),
                      color: effectiveTextColor,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                    ),
                    "td": Style(
                      padding: HtmlPaddings.symmetric(horizontal: 8.0, vertical: 5.0),
                      fontSize: FontSize((themeConfig.fontSize * 0.85).clamp(11.0, 15.0)),
                      lineHeight: LineHeight(1.25),
                      color: effectiveTextColor,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                    ),
                    "blockquote": Style(
                      margin: Margins.symmetric(horizontal: 16, vertical: 8),
                      padding: HtmlPaddings.all(12),
                      color: effectiveTextColor,
                      backgroundColor: isEInk ? const Color(0xFFE0DCD3) : Theme.of(context).colorScheme.surfaceContainer,
                      border: Border(left: BorderSide(color: isEInk ? const Color(0xFF1A1A18) : Theme.of(context).colorScheme.primary, width: isEInk ? 3 : 4)),
                    ),
                    "hr": Style(
                      margin: Margins.symmetric(vertical: 24),
                      height: Height(1),
                      backgroundColor: isEInk ? const Color(0xFF9E9A90) : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    "pre": Style(
                      fontFamily: 'JetBrains Mono',
                      backgroundColor: isEInk ? const Color(0xFFE0DCD3) : Theme.of(context).colorScheme.surfaceContainer,
                      color: effectiveTextColor,
                      padding: HtmlPaddings.all(8),
                    ),
                    "code": Style(
                      fontFamily: 'JetBrains Mono',
                      backgroundColor: isEInk ? const Color(0xFFE0DCD3) : Theme.of(context).colorScheme.surfaceContainer,
                      color: effectiveTextColor,
                      padding: HtmlPaddings.all(4),
                    ),
                    ".list-item": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: isEInk ? effectiveTextColor : Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 8),
                    ),
                    ".choice-item": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: isEInk ? effectiveTextColor : Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 6),
                    ),
                    ".toc-entry": Style(
                      fontSize: FontSize(themeConfig.fontSize * 0.95),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: isEInk ? effectiveTextColor : Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 6),
                    ),
                    ".toc-heading": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.3),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: isEInk ? effectiveTextColor : Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(top: 20, bottom: 12),
                    ),
                  },
                ),
              );
            }

            Widget wrapWithCover(Widget contentWidget) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BookCoverPage(book: widget.book, isContinuous: true),
                  contentWidget,
                ],
              );
            }

            if (isTtsActive) {
              return ListenableBuilder(
                listenable: _ttsController,
                builder: (context, _) {
                  _ttsController.highlightKeyAssigned = false;
                  final content = _ttsController.buildTtsHighlightedHtml(baseHtml);
                  final displayContent = bookAnnotations.isNotEmpty
                      ? AnnotationHighlightHelper.applyHighlights(content, bookAnnotations)
                      : content;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _ttsController.maybeEnsureHighlightVisible();
                  });
                  return wrapWithCover(buildHtmlWidget(displayContent));
                },
              );
            } else {
              final displayContent = bookAnnotations.isNotEmpty
                  ? AnnotationHighlightHelper.applyHighlights(baseHtml, bookAnnotations)
                  : baseHtml;
              return wrapWithCover(buildHtmlWidget(displayContent));
            }
          },
        ),
      ),
    ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(_chromeController.isLocked ? Icons.lock : Icons.lock_open),
                  tooltip: _chromeController.isLocked ? 'Unlock' : 'Lock',
                  onPressed: _toggleLockModeWithFeedback,
                ),
                if (_tocEntries.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.list),
                    tooltip: 'Table of Contents',
                    onPressed: _showTocSheet,
                  ),
                IconButton(
                  icon: Icon(_ttsController.showTtsControls ? Icons.volume_off : Icons.volume_up),
                  tooltip: 'Read Aloud',
                  onPressed: () => _ttsController.toggleTts(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: _showSettingsSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: _showReadingModePicker,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({String? fontFamily, List<String>? fontFamilyFallback}) _getGoogleFontData(String family) {
    try {
      final textStyle = GoogleFonts.getFont(family);
      return (
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: textStyle.fontFamilyFallback,
      );
    } catch (_) {
      return (fontFamily: family, fontFamilyFallback: null);
    }
  }

  TextAlign _parseTextAlign(String align) {
    switch (align) {
      case 'left': return TextAlign.left;
      case 'right': return TextAlign.right;
      case 'center': return TextAlign.center;
      case 'justify': return TextAlign.justify;
      default: return TextAlign.justify;
    }
  }
}

class _TtsHighlightSpan extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  final TtsHighlightStyle highlightStyle;

  const _TtsHighlightSpan({
    super.key,
    required this.text,
    required this.textStyle,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    BoxDecoration decoration;
    TextStyle highlightedTextStyle;
    EdgeInsets padding;

    if (isEInk) {
      decoration = BoxDecoration(
        color: const Color(0xFFD5D0C5),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
      );
      highlightedTextStyle = textStyle.copyWith(
        color: const Color(0xFF1A1A18),
        fontWeight: FontWeight.w600,
      );
      padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5);
    } else {
      switch (highlightStyle) {
        case TtsHighlightStyle.softPill:
          decoration = BoxDecoration(
            color: primaryColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(4),
          );
          highlightedTextStyle = textStyle.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.w600,
          );
          padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
          break;

        case TtsHighlightStyle.underline:
          decoration = BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: primaryColor,
                width: 2.5,
              ),
            ),
          );
          highlightedTextStyle = textStyle.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.w600,
          );
          padding = const EdgeInsets.only(bottom: 1, left: 1, right: 1);
          break;

        case TtsHighlightStyle.classicClean:
          decoration = BoxDecoration(
            color: primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.4),
              width: 1.0,
            ),
          );
          highlightedTextStyle = textStyle.copyWith(
            fontWeight: FontWeight.w600,
          );
          padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
          break;
      }
    }

    return Container(
      padding: padding,
      decoration: decoration,
      child: Text(
        text,
        style: highlightedTextStyle,
      ),
    );
  }
}


