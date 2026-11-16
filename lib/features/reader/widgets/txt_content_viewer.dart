import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:ferrous/features/reader/widgets/html_table_viewer.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ferrous/core/constants/book_textures.dart';
import 'package:ferrous/core/models/annotation.dart';
import 'package:ferrous/data/repositories/annotation_repository.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/features/annotations/annotation_detail_sheet.dart';
import 'package:ferrous/features/reader/annotation_highlight_helper.dart';
import 'package:ferrous/features/reader/controllers/txt_chapter_controller.dart';
import 'package:ferrous/features/reader/controllers/txt_tts_controller.dart';
import 'package:ferrous/core/utils/safe_screen_paginator.dart';
import 'package:ferrous/features/reader/hyphenation_helper.dart';
import 'package:ferrous/data/models/tts_highlight_style.dart';
import 'package:ferrous/features/settings/app_themes.dart';

class TxtContentViewer extends StatefulWidget {
  final int chapterIndex;
  final String htmlContent;
  final TxtChapterController chapterController;
  final TxtTtsController ttsController;
  final PageSlice? pageSlice;

  const TxtContentViewer({
    super.key,
    required this.chapterIndex,
    required this.htmlContent,
    required this.chapterController,
    required this.ttsController,
    this.pageSlice,
  });

  @override
  State<TxtContentViewer> createState() => _TxtContentViewerState();
}

class _TxtContentViewerState extends State<TxtContentViewer> {
  static final Map<String, String> _chunkCache = {};

  String _formatChunk(
    String rawChunk,
    int chunkIndex, {
    required bool hyphenation,
    required bool paragraphIndent,
    required List<Annotation> annotations,
  }) {
    if (widget.pageSlice != null) {
      return widget.pageSlice!.html;
    }

    final bookId = widget.chapterController.book.id;
    final annotationSig = annotations.isEmpty
        ? '0'
        : annotations.map((a) => '${a.id}:${a.color}').join(',');
    final key = '$bookId:${widget.chapterIndex}:$chunkIndex:$hyphenation:$paragraphIndent:$annotationSig';

    final cached = _chunkCache[key];
    if (cached != null) return cached;

    var processed = annotations.isNotEmpty
        ? AnnotationHighlightHelper.applyHighlights(rawChunk, annotations)
        : rawChunk;

    if (hyphenation || paragraphIndent) {
      processed = HyphenationHelper.processHtmlAndIndent(
        processed,
        applyHyphenation: hyphenation,
        applyIndent: paragraphIndent,
      );
    } else {
      processed = HyphenationHelper.processHtmlAndIndent(
        processed,
        applyHyphenation: false,
        applyIndent: false,
      );
    }

    if (_chunkCache.length > 500) {
      _chunkCache.remove(_chunkCache.keys.first);
    }
    _chunkCache[key] = processed;
    return processed;
  }

  List<String> _getChapterChunks() {
    if (widget.pageSlice != null) {
      return [widget.pageSlice!.html];
    }
    final allChunks = widget.chapterController.allChapterChunks;
    if (widget.chapterIndex >= 0 && widget.chapterIndex < allChunks.length) {
      final chunks = allChunks[widget.chapterIndex];
      if (chunks.isNotEmpty) return chunks;
    }
    return [widget.htmlContent];
  }

  Widget _buildHtmlContent({
    required List<HtmlExtension> extensions,
    required double horizontalMargin,
    required ReaderThemeConfig themeConfig,
    List<Annotation> annotations = const [],
  }) {
    final baseChunks = _getChapterChunks();
    final displayChunks = <String>[];
    for (int i = 0; i < baseChunks.length; i++) {
      final formatted = _formatChunk(
        baseChunks[i],
        i,
        hyphenation: themeConfig.hyphenation,
        paragraphIndent: themeConfig.paragraphIndent,
        annotations: annotations,
      );
      displayChunks.add(formatted);
    }
    return _buildHtmlWidget(
      displayChunks,
      extensions: extensions,
      horizontalMargin: horizontalMargin,
      themeConfig: themeConfig,
    );
  }

  Widget _buildHtmlWidget(
    List<String> chunks, {
    required List<HtmlExtension> extensions,
    required double horizontalMargin,
    required ReaderThemeConfig themeConfig,
  }) {
    late final ({String? fontFamily, List<String>? fontFamilyFallback}) fontData;
    try {
      final textStyle = GoogleFonts.getFont(themeConfig.fontFamily);
      fontData = (
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: [
          if (textStyle.fontFamilyFallback != null) ...textStyle.fontFamilyFallback!,
          'Roboto',
          'Noto Sans',
          'sans-serif',
        ],
      );
    } catch (_) {
      fontData = (
        fontFamily: themeConfig.fontFamily,
        fontFamilyFallback: const ['Roboto', 'Noto Sans', 'sans-serif'],
      );
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
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    final isPaged = widget.pageSlice != null;
    final blockMargin = isPaged
        ? Margins.only(top: 0.0, bottom: themeConfig.paragraphSpacing)
        : Margins.only(bottom: themeConfig.paragraphSpacing);

    final effectiveTextColor = isEInk
        ? const Color(0xFF1A1A18)
        : (themeConfig.paperTexture != BookTextures.none
            ? textureInfo.textColor
            : null);

    return Padding(
      key: ValueKey('txt-html-pad-${widget.chapterIndex}'),
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < chunks.length; i++)
            RepaintBoundary(
              key: ValueKey('txt_chunk_rb_${widget.chapterIndex}_$i'),
              child: Html(
                key: ValueKey('txt-html-chunk-${widget.chapterIndex}-$i'),
                data: chunks[i],
                extensions: extensions,
                style: {
                  "html": Style(
                    padding: HtmlPaddings.zero,
                    margin: Margins.zero,
                  ),
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
                    margin: blockMargin,
                    textAlign: parseTextAlign(themeConfig.textAlign),
                    color: effectiveTextColor,
                    backgroundColor: isEInk ? Colors.transparent : null,
                  ),
                  "div": Style(
                    margin: isPaged ? Margins.zero : blockMargin,
                    padding: HtmlPaddings.zero,
                    textAlign: parseTextAlign(themeConfig.textAlign),
                    color: effectiveTextColor,
                    backgroundColor: isEInk ? Colors.transparent : null,
                  ),
                  "section": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                  "article": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                  "main": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                  "span": Style(
                    color: effectiveTextColor,
                  ),
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final themeConfig = themeRepo.config;
    final annotationRepo = context.watch<AnnotationRepository>();

    final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;

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
      TagExtension.inline(
        tagsToExtend: {'p-indent', 'indent'},
        builder: (extensionContext) {
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
          final isCurrent = widget.chapterIndex == widget.chapterController.currentChapterIndex;
          final text = ctx.node.text ?? '';
          final style = ctx.style?.generateTextStyle() ?? const TextStyle();

          return _TxtTtsHighlightSpan(
            key: isCurrent ? widget.ttsController.ttsHighlightKey : null,
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

    return _buildHtmlContent(
      extensions: extensions,
      horizontalMargin: horizontalMargin,
      themeConfig: themeConfig,
      annotations: chapterAnnotations,
    );
  }
}

class _TxtTtsHighlightSpan extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  final TtsHighlightStyle highlightStyle;

  const _TxtTtsHighlightSpan({
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
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          );
          highlightedTextStyle = textStyle.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.w600,
          );
          padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
          break;
      }
    }

    return Container(
      decoration: decoration,
      padding: padding,
      child: Text(text, style: highlightedTextStyle),
    );
  }
}
