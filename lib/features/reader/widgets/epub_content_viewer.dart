import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:reader_app/features/reader/widgets/html_table_viewer.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/annotations/annotation_detail_sheet.dart';
import 'package:reader_app/features/reader/annotation_highlight_helper.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';

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
  Future<String>? _processedFuture;
  String? _loadedKey;

  String _cacheKey(bool hyphenation, bool paragraphIndent) {
    final bookId = widget.chapterController.book.id;
    return '$bookId:${widget.chapterIndex}:$hyphenation:$paragraphIndent';
  }

  @override
  void didUpdateWidget(EpubContentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlContent != widget.htmlContent ||
        oldWidget.chapterIndex != widget.chapterIndex) {
      _loadedKey = null;
      _processedFuture = null;
    }
  }

  void _ensureFuture(String key, String content, bool hyphenation, bool paragraphIndent) {
    if (_loadedKey == key) return;
    _loadedKey = key;
    if (_processedHtmlCache.containsKey(key)) {
      _processedFuture = null;
    } else if (hyphenation || paragraphIndent) {
      _processedFuture = _getProcessedHtml(key, content, hyphenation, paragraphIndent);
    } else {
      _processedFuture = null;
    }
  }

  Widget _buildHtmlContent(
    String content, {
    required bool hyphenation,
    required bool paragraphIndent,
    required List<HtmlExtension> extensions,
    required double horizontalMargin,
    required ReaderThemeConfig themeConfig,
    List<Annotation> annotations = const [],
  }) {
    final key = _cacheKey(hyphenation, paragraphIndent);

    // Cache hit: render synchronously, no FutureBuilder
    if (_processedHtmlCache.containsKey(key)) {
      final base = _processedHtmlCache[key]!;
      final display = annotations.isNotEmpty
          ? AnnotationHighlightHelper.applyHighlights(base, annotations)
          : base;
      return _buildHtmlWidget(
        display,
        extensions: extensions,
        horizontalMargin: horizontalMargin,
        themeConfig: themeConfig,
      );
    }

    _ensureFuture(key, content, hyphenation, paragraphIndent);

    // Cache miss: process in background isolate, show raw content immediately
    return FutureBuilder<String>(
      future: _processedFuture,
      initialData: content,
      builder: (context, snapshot) {
        final base = snapshot.data ?? content;
        final display = annotations.isNotEmpty
            ? AnnotationHighlightHelper.applyHighlights(base, annotations)
            : base;
        return _buildHtmlWidget(
          display,
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
    if (_processedHtmlCache.length > 50) {
      _processedHtmlCache.remove(_processedHtmlCache.keys.first);
    }
    _processedHtmlCache[key] = processed;
    if (mounted) {
      setState(() {});
    }
    return processed;
  }

  Widget _buildHtmlWidget(
    String content, {
    required List<HtmlExtension> extensions,
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

    final textureInfo = BookTextures.getById(themeConfig.paperTexture);
    final effectiveTextColor = themeConfig.paperTexture != BookTextures.none
        ? textureInfo.textColor
        : null;

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
            color: effectiveTextColor,
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
            color: effectiveTextColor,
          ),
          "div": Style(
            margin: Margins.only(bottom: themeConfig.paragraphSpacing),
            textAlign: parseTextAlign(themeConfig.textAlign),
            color: effectiveTextColor,
          ),
          "img": Style(
            width: Width(100, Unit.percent),
            margin: Margins.only(bottom: 24.0),
          ),
          "table": Style(
            width: Width(100, Unit.percent),
            margin: Margins.symmetric(vertical: 14.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1.0,
            ),
          ),
          "th": Style(
            padding: HtmlPaddings.symmetric(horizontal: 8.0, vertical: 6.0),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            fontWeight: FontWeight.bold,
            fontSize: FontSize((themeConfig.fontSize * 0.85).clamp(11.0, 15.0)),
            lineHeight: LineHeight(1.25),
            color: effectiveTextColor,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
          "td": Style(
            padding: HtmlPaddings.symmetric(horizontal: 8.0, vertical: 5.0),
            fontSize: FontSize((themeConfig.fontSize * 0.85).clamp(11.0, 15.0)),
            lineHeight: LineHeight(1.25),
            color: effectiveTextColor,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final annotationRepo = context.watch<AnnotationRepository>();
    final themeConfig = themeRepo.config;
    final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
    final isTtsActive = widget.ttsController.showTtsControls ||
        widget.ttsController.ttsService.state != TtsState.stopped;
    final isCurrentChapter =
        widget.chapterIndex == widget.chapterController.currentChapterIndex;

    final chapterAnnotations = annotationRepo
        .getAnnotationsForBook(widget.chapterController.book.id)
        .where((a) => a.chapterIndex == widget.chapterIndex)
        .toList();

    final extensions = [
      TagWrapExtension(
        tagsToWrap: {'table'},
        builder: (child) => HtmlTableViewer(child: child),
      ),
      const TableHtmlExtension(),
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
            highlightStyle: themeRepo.highlightStyle,
          );
        },
      ),
      TagExtension(
        tagsToExtend: {AnnotationHighlightHelper.highlightTag},
        builder: (ctx) {
          final text = ctx.node.text ?? '';
          final id = ctx.attributes['data-id'] ?? '';
          final colorVal = int.tryParse(ctx.attributes['data-color'] ?? '') ?? 0xFFFFF176;
          final style = ctx.style?.generateTextStyle() ?? const TextStyle();
          return _AnnotationHighlightSpan(
            annotationId: id,
            text: text,
            color: Color(colorVal),
            textStyle: style,
            onTap: () {
              final all = annotationRepo.getAllAnnotations();
              final target = all.cast<Annotation?>().firstWhere(
                    (a) => a?.id == id,
                    orElse: () => null,
                  );
              if (target != null) {
                showAnnotationDetailSheet(context, target);
              }
            },
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
          if (!_processedHtmlCache.containsKey(key) &&
              (themeConfig.hyphenation || themeConfig.paragraphIndent)) {
            _getProcessedHtml(
              key,
              widget.htmlContent,
              themeConfig.hyphenation,
              themeConfig.paragraphIndent,
            ).then((_) {
              if (mounted) setState(() {});
            });
          }
          final processedHtml = _processedHtmlCache[key] ?? widget.htmlContent;
          String content = widget.ttsController
              .buildTtsHighlightedHtml(processedHtml);
          if (chapterAnnotations.isNotEmpty) {
            content = AnnotationHighlightHelper.applyHighlights(content, chapterAnnotations);
          }
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
        annotations: chapterAnnotations,
      );
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

class _AnnotationHighlightSpan extends StatelessWidget {
  final String annotationId;
  final String text;
  final Color color;
  final TextStyle textStyle;
  final VoidCallback onTap;

  const _AnnotationHighlightSpan({
    required this.annotationId,
    required this.text,
    required this.color,
    required this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
          border: Border(
            bottom: BorderSide(
              color: color,
              width: 2.0,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(
          text,
          style: textStyle.copyWith(
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

