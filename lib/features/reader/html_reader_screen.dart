import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
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
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';

/// Shared base class for HTML-based text readers (DOCX, MOBI).

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
    this.fontSize = 16.0,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 12.0,
    this.webtoonSpacing = 28.0,
    this.errorPrefix = 'Error',
  });

  static const docx = HtmlReaderConfig(
    fontSize: 16.0,
    lineHeight: 1.5,
    paragraphSpacing: 12.0,
    webtoonSpacing: 28.0,
    errorPrefix: 'Error loading DOCX',
  );

  static const mobi = HtmlReaderConfig(
    fontSize: 18.0,
    lineHeight: 1.8,
    paragraphSpacing: 16.0,
    webtoonSpacing: 28.0,
    errorPrefix: 'Error',
  );
}

abstract class HtmlReaderScreenState<T extends HtmlReaderScreen> extends State<T>
    with WidgetsBindingObserver {
  String? _htmlContent;
  String? _hyphenatedHtml;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  ResolvedBookFile? _resolvedFile;
  String _plainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  late ReadingMode _readingMode;
  late double _lastScrollPosition;

  // Shared chrome controller for UI visibility and lock mode
  final ReaderChromeController _chromeController = ReaderChromeController();
  Offset? _lastDoubleTapDown;

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
      final html = await loadContent(resolved.path);

      // Run expensive text processing in background isolates
      final plainTextFuture = compute(_htmlToPlainTextStatic, html);
      final sentenceSpansFuture = plainTextFuture.then(
        (plainText) => compute(splitIntoSentences, plainText),
      );

      // Precompute hyphenation in background if enabled.
      // Uses processHtmlIsolated which calls init() inside the isolate
      // so the hyphenator is available in the background isolate's static field.
      final shouldHyphenate = themeRepo.config.hyphenation;
      Future<String?> hyphenationFuture;
      if (shouldHyphenate) {
        hyphenationFuture = compute(HyphenationHelper.processHtmlIsolated, html);
      } else {
        hyphenationFuture = Future.value(null);
      }

      // Preload the current font family before rendering
      final fontFamily = themeRepo.config.fontFamily;
      await _preloadFont(fontFamily);
      _lastLoadedFontFamily = fontFamily;

      final plainText = await plainTextFuture;
      final sentenceSpans = await sentenceSpansFuture;
      final hyphenatedHtml = await hyphenationFuture;

      setState(() {
        _htmlContent = html;
        _plainText = plainText;
        _sentenceSpans = sentenceSpans;
        _hyphenatedHtml = hyphenatedHtml;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
      });
    } catch (e) {
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

    // Handle hyphenation toggle at runtime
    if (_htmlContent != null) {
      if (themeConfig.hyphenation && _hyphenatedHtml == null) {
        // Hyphenation was just enabled — compute in background
        compute(HyphenationHelper.processHtmlIsolated, _htmlContent!).then((result) {
          if (mounted) setState(() => _hyphenatedHtml = result);
        });
      } else if (!themeConfig.hyphenation && _hyphenatedHtml != null) {
        // Hyphenation was just disabled — clear cache
        setState(() => _hyphenatedHtml = null);
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
      _ttsController.setTtsControlsVisible(_chromeController.showChrome);
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

  static String _htmlToPlainTextStatic(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parse(html);
    document.querySelectorAll('script,style,noscript').forEach((e) => e.remove());
    return DomTextUtils.extractPlainText(document.body ?? document.documentElement);
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
                    child: _buildBody(),
                  ),
                ),
                if (showChrome) _buildTopBar(),
                if (_ttsController.showTtsControls)
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text("${config.errorPrefix}: $_error"),
            ],
          ),
        ),
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
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Consumer<ReaderThemeRepository>(
          builder: (context, themeRepo, _) {
            final themeConfig = themeRepo.config;
            final spacing = themeConfig.paragraphSpacing; 
            
            // Margins
            final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;

            final baseHtml = themeConfig.hyphenation
                ? (_hyphenatedHtml ?? _htmlContent ?? '')
                : (_htmlContent ?? '');

            final extensions = [
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
            ];

            Widget buildHtmlWidget(String displayContent) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Html(
                  data: displayContent,
                  extensions: extensions,
                  style: {
                    "body": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      fontWeight: FontWeight.values[(themeConfig.fontWeight ~/ 100).clamp(0, 8)],
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      textAlign: _parseTextAlign(themeConfig.textAlign),
                      letterSpacing: themeConfig.wordSpacing,
                      padding: HtmlPaddings.zero,
                      margin: Margins.zero,
                    ),
                    "tts-highlight": Style(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                    ),
                    "p": Style(
                      margin: Margins.only(
                        bottom: spacing,
                        top: 0,
                      ),
                      textAlign: _parseTextAlign(themeConfig.textAlign),
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
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(top: 24, bottom: 12),
                    ),
                    "h2": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.35),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(top: 20, bottom: 10),
                    ),
                    "h3": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.2),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(top: 18, bottom: 8),
                    ),
                    "h4": Style(
                      fontSize: FontSize(themeConfig.fontSize * 1.1),
                      fontWeight: FontWeight.bold,
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
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
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 6),
                    ),
                    "table": Style(
                      width: Width(100, Unit.percent),
                      margin: Margins.symmetric(vertical: 16.0),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.0),
                    ),
                    "th": Style(
                      padding: HtmlPaddings.all(10.0),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                      fontWeight: FontWeight.bold,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                    ),
                    "td": Style(
                      padding: HtmlPaddings.all(8.0),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                    ),
                    "blockquote": Style(
                      margin: Margins.symmetric(horizontal: 16, vertical: 8),
                      padding: HtmlPaddings.all(12),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                      border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
                    ),
                    "hr": Style(
                      margin: Margins.symmetric(vertical: 24),
                      height: Height(1),
                      backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    "pre": Style(
                      fontFamily: 'JetBrains Mono',
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                      padding: HtmlPaddings.all(8),
                    ),
                    "code": Style(
                      fontFamily: 'JetBrains Mono',
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                      padding: HtmlPaddings.all(4),
                    ),
                    ".list-item": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 8),
                    ),
                    ".choice-item": Style(
                      fontSize: FontSize(themeConfig.fontSize),
                      lineHeight: LineHeight(themeConfig.lineHeight),
                      fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                      fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      margin: Margins.only(bottom: 6),
                    ),
                  },
                ),
              );
            }

            if (isTtsActive) {
              return ListenableBuilder(
                listenable: _ttsController,
                builder: (context, _) {
                  _ttsController.highlightKeyAssigned = false;
                  final content = _ttsController.buildTtsHighlightedHtml(baseHtml);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _ttsController.maybeEnsureHighlightVisible();
                  });
                  return buildHtmlWidget(content);
                },
              );
            } else {
              return buildHtmlWidget(baseHtml);
            }
          },
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
                IconButton(
                  icon: Icon(_ttsController.showTtsControls ? Icons.volume_up : Icons.volume_mute),
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

    BoxDecoration decoration;
    TextStyle highlightedTextStyle;
    EdgeInsets padding;

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

