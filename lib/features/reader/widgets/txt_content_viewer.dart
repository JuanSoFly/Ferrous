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
import 'package:ferrous/features/reader/tts_highlight_extension.dart';
import 'package:ferrous/data/models/tts_highlight_style.dart';
import 'package:ferrous/data/services/tts_service.dart';
import 'package:ferrous/features/settings/app_themes.dart';
import 'package:html/dom.dart' as dom;

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

  String _formatContinuousChunkHtml(
    String rawChunk, {
    required bool hyphenation,
    required bool paragraphIndent,
    required List<Annotation> annotations,
  }) {
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

    return processed;
  }

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

    final processed = _formatContinuousChunkHtml(
      rawChunk,
      hyphenation: hyphenation,
      paragraphIndent: paragraphIndent,
      annotations: annotations,
    );

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
            : Theme.of(context).colorScheme.onSurface);

    final resolvedTextStyle = TextStyle(
      fontSize: themeConfig.fontSize,
      height: themeConfig.lineHeight,
      fontFamily: fontData.fontFamily,
      fontFamilyFallback: fontData.fontFamilyFallback,
      fontWeight: FontWeight.values[
          (themeConfig.fontWeight ~/ 100).clamp(0, 8)],
      letterSpacing: themeConfig.wordSpacing,
      color: effectiveTextColor,
    );

    return Padding(
      key: ValueKey('txt-html-pad-${widget.chapterIndex}'),
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < chunks.length; i++)
            RepaintBoundary(
              key: ValueKey('txt_chunk_rb_${widget.chapterIndex}_$i'),
              child: Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.copyWith(
                    bodyMedium: resolvedTextStyle,
                  ),
                ),
                child: DefaultTextStyle(
                  style: resolvedTextStyle,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
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
                          backgroundColor: Colors.transparent,
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
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
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<HtmlExtension> _buildExtensions({
    required BuildContext context,
    required ReaderThemeConfig themeConfig,
    required AnnotationRepository annotationRepo,
    required TtsHighlightStyle highlightStyle,
  }) {
    return [
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
      TagExtension.inline(
        tagsToExtend: {'page-split-tail'},
        builder: (ctx) {
          final style = ctx.style?.generateTextStyle() ?? const TextStyle();
          final wsStr = ctx.attributes['data-word-spacing'] ?? '';
          final extraWs = double.tryParse(wsStr) ?? 0.0;
          final effectiveStyle = style.copyWith(
            wordSpacing: extraWs > 0 ? extraWs : null,
          );
          if (ctx.node.nodes.isEmpty ||
              (ctx.node.nodes.length == 1 && ctx.node.nodes.first is dom.Text)) {
            return TextSpan(
              text: ctx.node.text ?? '',
              style: effectiveStyle,
            );
          }
          final children = <InlineSpan>[];
          for (final n in ctx.node.nodes) {
            if (n is dom.Text) {
              children.add(TextSpan(text: n.data, style: effectiveStyle));
            } else if (n is dom.Element) {
              final isItalic = n.localName == 'i' || n.localName == 'em';
              final isBold = n.localName == 'b' || n.localName == 'strong';
              children.add(TextSpan(
                text: n.text,
                style: effectiveStyle.copyWith(
                  fontStyle: isItalic ? FontStyle.italic : null,
                  fontWeight: isBold ? FontWeight.bold : null,
                ),
              ));
            }
          }
          return TextSpan(children: children, style: effectiveStyle);
        },
      ),
      TtsHighlightExtension.build(
        isSpeaking: () => widget.chapterIndex == widget.ttsController.speakingChapterIndex,
        isPaged: widget.pageSlice != null,
        ttsHighlightKey: widget.ttsController.ttsHighlightKey,
        highlightStyle: highlightStyle,
        primaryColor: Theme.of(context).colorScheme.primary,
        isEInk: () {
          AppTheme? currentTheme;
          try {
            currentTheme = context.watch<AppTheme?>();
          } catch (_) {}
          return currentTheme == AppTheme.eInk;
        }(),
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
          final hStyle = style.copyWith(
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
              style: hStyle,
              recognizer: TapGestureRecognizer()..onTap = handleTap,
            );
          }
          return TextSpan(
            text: text,
            style: hStyle,
            recognizer: TapGestureRecognizer()..onTap = handleTap,
          );
        },
      ),
    ];
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

    final staticChild = _buildHtmlContent(
      extensions: _buildExtensions(
        context: context,
        themeConfig: themeConfig,
        annotationRepo: annotationRepo,
        highlightStyle: themeRepo.highlightStyle,
      ),
      horizontalMargin: horizontalMargin,
      themeConfig: themeConfig,
      annotations: chapterAnnotations,
    );

    return ListenableBuilder(
      listenable: Listenable.merge([widget.ttsController, themeRepo]),
      child: staticChild,
      builder: (context, child) {
        final isSpeakingChapter =
            widget.ttsController.speakingChapterIndex == widget.chapterIndex;
        final isTtsActive = widget.ttsController.showTtsControls ||
            widget.ttsController.ttsService.state != TtsState.stopped;
        final hasHighlight = widget.ttsController.lastHighlightStart != null;

        if (!isSpeakingChapter || !isTtsActive || !hasHighlight) {
          return child!;
        }

        final liveExtensions = _buildExtensions(
          context: context,
          themeConfig: themeConfig,
          annotationRepo: annotationRepo,
          highlightStyle: themeRepo.highlightStyle,
        );

        widget.ttsController.highlightKeyAssigned = false;
        final highlightStart = widget.ttsController.lastHighlightStart!;
        final highlightEnd = widget.ttsController.lastHighlightEnd ?? highlightStart;

        // Paged mode: single slice TTS highlight
        if (widget.pageSlice != null) {
          final slice = widget.pageSlice!;
          if (highlightStart >= slice.startCharOffset && highlightStart < slice.endCharOffset) {
            final sliceCharLen = (slice.endCharOffset - slice.startCharOffset).clamp(0, double.maxFinite.toInt());
            final localStart = (highlightStart - slice.startCharOffset).clamp(0, sliceCharLen);
            final localEnd = (highlightEnd - slice.startCharOffset).clamp(localStart, sliceCharLen);

            var sliceHtml = widget.ttsController.buildTtsHighlightedHtml(
              slice.html,
              overrideStart: localStart,
              overrideEnd: localEnd,
              chapterRawStart: highlightStart,
              chapterRawEnd: highlightEnd,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.ttsController.maybeEnsureHighlightVisible();
            });
            return _buildHtmlWidget(
              [sliceHtml],
              extensions: liveExtensions,
              horizontalMargin: horizontalMargin,
              themeConfig: themeConfig,
            );
          } else {
            return child!;
          }
        }

        final baseChunks = _getChapterChunks();
        final chunkOffsets = widget.chapterController.allChapterChunkOffsets.length > widget.chapterIndex
            ? widget.chapterController.allChapterChunkOffsets[widget.chapterIndex]
            : const <int>[0];

        int activeChunkIndex = 0;
        for (var i = 0; i < chunkOffsets.length; i++) {
          final start = chunkOffsets[i];
          final nextStart = (i + 1 < chunkOffsets.length) ? chunkOffsets[i + 1] : double.maxFinite.toInt();
          if (highlightStart >= start && highlightStart < nextStart) {
            activeChunkIndex = i;
            break;
          }
        }

        final chunkStartOffset = chunkOffsets.length > activeChunkIndex ? chunkOffsets[activeChunkIndex] : 0;
        final localStart = highlightStart - chunkStartOffset;
        final localEnd = highlightEnd - chunkStartOffset;

        final ttsChunks = <String>[];
        for (var i = 0; i < baseChunks.length; i++) {
          if (i == activeChunkIndex) {
            var chunk = widget.ttsController.buildTtsHighlightedHtml(
              baseChunks[i],
              overrideStart: localStart,
              overrideEnd: localEnd,
              chapterRawStart: highlightStart,
              chapterRawEnd: highlightEnd,
            );
            chunk = _formatContinuousChunkHtml(
              chunk,
              hyphenation: themeConfig.hyphenation,
              paragraphIndent: themeConfig.paragraphIndent,
              annotations: chapterAnnotations,
            );
            ttsChunks.add(chunk);
          } else {
            ttsChunks.add(_formatChunk(
              baseChunks[i],
              i,
              hyphenation: themeConfig.hyphenation,
              paragraphIndent: themeConfig.paragraphIndent,
              annotations: chapterAnnotations,
            ));
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.ttsController.maybeEnsureHighlightVisible();
        });

        return _buildHtmlWidget(
          ttsChunks,
          extensions: liveExtensions,
          horizontalMargin: horizontalMargin,
          themeConfig: themeConfig,
        );
      },
    );
  }
}
