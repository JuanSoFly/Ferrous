import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/utils/sentence_utils.dart';
import 'package:reader_app/utils/text_normalization.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';

/// Shared base class for HTML-based text readers (DOCX, MOBI).
/// 
/// This consolidates the identical reader logic from docx_reader.dart and mobi_reader.dart,
/// reducing ~740 lines of code to a single implementation.
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
      final plainText = _htmlToPlainText(html);

      // Preload the current font family before rendering
      final fontFamily = themeRepo.config.fontFamily;
      await _preloadFont(fontFamily);
      _lastLoadedFontFamily = fontFamily;

      setState(() {
        _htmlContent = html;
        _plainText = plainText;
        _sentenceSpans = splitIntoSentences(plainText);
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

  /// Called when theme settings change - preload font if it changed
  void _onThemeChanged() {
    final newFontFamily = _themeRepository?.config.fontFamily ?? '';
    if (newFontFamily.isNotEmpty && newFontFamily != _lastLoadedFontFamily) {
      _lastLoadedFontFamily = newFontFamily;
      _preloadFont(newFontFamily).then((_) {
        if (mounted) setState(() {});
      });
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
      File(resolved.path).deleteSync();
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
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final screenSize = MediaQuery.of(context).size;
    if (_chromeController.isCenterTap(details.globalPosition, screenSize)) {
      _chromeController.toggleChrome();
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

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parse(html);
    document.querySelectorAll('script,style,noscript').forEach((e) => e.remove());
    final rawText = document.body?.text ??
        document.documentElement?.text ??
        document.text ??
        '';
    return normalizePlainText(rawText);
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = _chromeController.showChrome && !_chromeController.isLocked;

    return Scaffold(
      body: Stack(
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
        ],
      ),
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
            // Apply user paragraph spacing multiplier/value on top of base? 
            // The user setting is 0-50 px. Let's use user setting if customized, or add it?
            // "Paragraph Spacing from 0% to 100%".
            // Let's assume the slider value is the pixel margin bottom.
            final spacing = themeConfig.paragraphSpacing; 
            
             // Margins
              final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0; // Reduced margin logic

             final displayContent = themeConfig.hyphenation
                 ? HyphenationHelper.processHtml(_htmlContent ?? '')
                 : (_htmlContent ?? '');

             return Padding( // Apply margins here or in Html p style?
                padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
                child: Html(
                 data: displayContent,
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
                  ),
                  "p": Style(
                    margin: Margins.only(
                      bottom: spacing,
                      top: 0,
                    ),
                    textAlign: _parseTextAlign(themeConfig.textAlign),
                  ),
                },
              ),
            );
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

  /// Get font data for flutter_html Style
  ({String? fontFamily, List<String>? fontFamilyFallback}) _getGoogleFontData(String family) {
    try {
      final textStyle = GoogleFonts.getFont(family);
      return (
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: textStyle.fontFamilyFallback,
      );
    } catch (_) {
      // Fallback to the raw family name
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
