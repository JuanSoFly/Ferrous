import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';

class EpubContentViewer extends StatefulWidget {
  final int chapterIndex;
  final String htmlContent;
  final EpubChapterController chapterController;
  final EpubTtsController ttsController;

  const EpubContentViewer({
    super.key,
    required this.chapterIndex,
    required this.htmlContent,
    required this.chapterController,
    required this.ttsController,
  });

  @override
  State<EpubContentViewer> createState() => _EpubContentViewerState();
}

class _EpubContentViewerState extends State<EpubContentViewer> {
  // Static cache keyed by bookId:chapterIndex:hyphenation:paragraphIndent
  // Theme changes like font size, font family, etc. do NOT invalidate this cache.
  static final Map<String, String> _processedHtmlCache = {};

  String _cacheKey(bool hyphenation, bool paragraphIndent) {
    final bookId = widget.chapterController.book.id;
    return '$bookId:${widget.chapterIndex}:$hyphenation:$paragraphIndent';
  }

  Widget _buildHtmlContent(
    String content, {
    required bool hyphenation,
    required bool paragraphIndent,
    required List<TagExtension> extensions,
    required double horizontalMargin,
    required ReaderThemeConfig themeConfig,
  }) {
    final key = _cacheKey(hyphenation, paragraphIndent);

    // Cache hit: render synchronously, no FutureBuilder
    if (_processedHtmlCache.containsKey(key)) {
      return _buildHtmlWidget(
        _processedHtmlCache[key]!,
        extensions: extensions,
        horizontalMargin: horizontalMargin,
        themeConfig: themeConfig,
      );
    }

    // Cache miss: process in background isolate, show raw content immediately
    return FutureBuilder<String>(
      future: _getProcessedHtml(key, content, hyphenation, paragraphIndent),
      initialData: content,
      builder: (context, snapshot) {
        return _buildHtmlWidget(
          snapshot.data ?? content,
          extensions: extensions,
          horizontalMargin: horizontalMargin,
          themeConfig: themeConfig,
        );
      },
    );
  }

  Future<String> _getProcessedHtml(
    String key,
    String rawHtml,
    bool hyphenation,
    bool paragraphIndent,
  ) async {
    if (!hyphenation && !paragraphIndent) return rawHtml;

    await HyphenationHelper.init();
    final processed = await compute(
      HyphenationHelper.processHtmlAndIndentIsolated,
      {
        'html': rawHtml,
        'hyphenation': hyphenation,
        'paragraphIndent': paragraphIndent,
      },
    );
    _processedHtmlCache[key] = processed;
    return processed;
  }

  Widget _buildHtmlWidget(
    String content, {
    required List<TagExtension> extensions,
    required double horizontalMargin,
    required ReaderThemeConfig themeConfig,
  }) {
    late final ({String? fontFamily, List<String>? fontFamilyFallback}) fontData;
    try {
      final textStyle = GoogleFonts.getFont(themeConfig.fontFamily);
      fontData = (
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: textStyle.fontFamilyFallback,
      );
    } catch (_) {
      fontData = (fontFamily: themeConfig.fontFamily, fontFamilyFallback: null);
    }

    TextAlign parseTextAlign(String align) {
      switch (align) {
        case 'left':
          return TextAlign.left;
        case 'right':
          return TextAlign.right;
        case 'center':
          return TextAlign.center;
        case 'justify':
          return TextAlign.justify;
        default:
          return TextAlign.justify;
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Html(
        data: content,
        extensions: extensions,
        style: {
          "body": Style(
            fontSize: FontSize(themeConfig.fontSize),
            lineHeight: LineHeight(themeConfig.lineHeight),
            fontFamily: fontData.fontFamily,
            fontFamilyFallback: fontData.fontFamilyFallback,
            fontWeight: FontWeight.values[
                (themeConfig.fontWeight ~/ 100).clamp(0, 8)],
            textAlign: parseTextAlign(themeConfig.textAlign),
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
            margin: Margins.only(bottom: themeConfig.paragraphSpacing),
            textAlign: parseTextAlign(themeConfig.textAlign),
          ),
          "img": Style(
            width: Width(100, Unit.percent),
            margin: Margins.only(bottom: 24.0),
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final themeConfig = themeRepo.config;
    final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
    final isTtsActive = widget.ttsController.showTtsControls ||
        widget.ttsController.ttsService.state != TtsState.stopped;
    final isCurrentChapter =
        widget.chapterIndex == widget.chapterController.currentChapterIndex;

    final highlightColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);

    final extensions = [
      TagExtension(
        tagsToExtend: {'tts-highlight'},
        builder: (context) {
          final text = context.node.text ?? '';
          final style =
              context.style?.generateTextStyle() ?? const TextStyle();
          return _TtsHighlightSpan(
            key: isCurrentChapter
                ? widget.ttsController.ttsHighlightKey
                : null,
            text: text,
            textStyle: style,
            highlightColor: highlightColor,
          );
        },
      ),
    ];

    if (isTtsActive && isCurrentChapter) {
      return ListenableBuilder(
        listenable: widget.ttsController,
        builder: (context, _) {
          widget.ttsController.highlightKeyAssigned = false;
          final key = _cacheKey(themeConfig.hyphenation, themeConfig.paragraphIndent);
          final processedHtml = _processedHtmlCache[key] ?? widget.htmlContent;
          final content = widget.ttsController
              .buildTtsHighlightedHtml(processedHtml);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.ttsController.maybeEnsureHighlightVisible();
          });
          return _buildHtmlWidget(
            content,
            extensions: extensions,
            horizontalMargin: horizontalMargin,
            themeConfig: themeConfig,
          );
        },
      );
    } else {
      return _buildHtmlContent(
        widget.htmlContent,
        hyphenation: themeConfig.hyphenation,
        paragraphIndent: themeConfig.paragraphIndent,
        extensions: extensions,
        horizontalMargin: horizontalMargin,
        themeConfig: themeConfig,
      );
    }
  }
}

class _TtsHighlightSpan extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  final Color highlightColor;

  const _TtsHighlightSpan({
    super.key,
    required this.text,
    required this.textStyle,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.yellow.shade600 : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        text,
        style: textStyle.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.black : null,
        ),
      ),
    );
  }
}
