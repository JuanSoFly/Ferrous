import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:reader_app/core/utils/safe_screen_paginator.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class EpubContentViewer extends StatefulWidget {
  final int chapterIndex;
  final String htmlContent;
  final EpubChapterController chapterController;
  final EpubTtsController ttsController;
  final PageSlice? pageSlice;

  const EpubContentViewer({
    super.key,
    required this.chapterIndex,
    required this.htmlContent,
    required this.chapterController,
    required this.ttsController,
    this.pageSlice,
  });

  @override
  State<EpubContentViewer> createState() => _EpubContentViewerState();
}

class _EpubContentViewerState extends State<EpubContentViewer> {
  // Static chunk-level LRU cache keyed by bookId:chapterIndex:chunkIndex:hyphenation:paragraphIndent:annotationHash
  // Theme changes like font size, font family, margins, etc. do NOT invalidate this cache.
  static final Map<String, String> _chunkCache = {};

  String _formatChunk(
    String rawChunk,
    int chunkIndex, {
    required bool hyphenation,
    required bool paragraphIndent,
    required List<Annotation> annotations,
  }) {
    if (widget.pageSlice != null) {
      // Leaf hyphenation on single page slice (<0.2 ms)
      return HyphenationHelper.processHtmlAndIndent(
        rawChunk,
        applyHyphenation: hyphenation,
        applyIndent: paragraphIndent,
      );
    }

    final bookId = widget.chapterController.book.id;
    final annotationSig = annotations.isEmpty
        ? '0'
        : annotations.map((a) => '${a.id}:${a.color}').join(',');
    final key = '$bookId:${widget.chapterIndex}:$chunkIndex:$hyphenation:$paragraphIndent:$annotationSig';

    final cached = _chunkCache[key];
    if (cached != null) return cached;

    // Strict Pipeline Order:
    // 1. Base chunk HTML
    // 2. Inject annotation highlights into DOM FIRST (so clean text matches exactly before hyphenation)
    var processed = annotations.isNotEmpty
        ? AnnotationHighlightHelper.applyHighlights(rawChunk, annotations)
        : rawChunk;

    // 3. Process hyphenation and paragraph indentation
    if (hyphenation || paragraphIndent) {
      processed = HyphenationHelper.processHtmlAndIndent(
        processed,
        applyHyphenation: hyphenation,
        applyIndent: paragraphIndent,
      );
    } else {
      // Clean strip if hyphenation is false
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

    final effectiveTextColor = isEInk
        ? const Color(0xFF1A1A18)
        : (themeConfig.paperTexture != BookTextures.none
            ? textureInfo.textColor
            : null);

    return Padding(
      key: ValueKey('chapter-html-pad-${widget.chapterIndex}'),
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < chunks.length; i++)
            RepaintBoundary(
              key: ValueKey('chunk_rb_${widget.chapterIndex}_$i'),
              child: Html(
                key: ValueKey('chapter-html-chunk-${widget.chapterIndex}-$i'),
                data: chunks[i],
                extensions: extensions,
                onLinkTap: (url, attributes, element) {
                  if (url == null || url.trim().isEmpty) return;
                  final trimmed = url.trim();
                  if (trimmed.startsWith('http://') ||
                      trimmed.startsWith('https://') ||
                      trimmed.startsWith('mailto:')) {
                    try {
                      launchUrl(Uri.parse(trimmed), mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Error launching external URL $trimmed: $e');
                    }
                  } else {
                    widget.chapterController.navigateToHref(trimmed);
                  }
                },
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
            margin: Margins.only(bottom: themeConfig.paragraphSpacing),
            textAlign: parseTextAlign(themeConfig.textAlign),
            color: effectiveTextColor,
            backgroundColor: isEInk ? Colors.transparent : null,
          ),
          "div": Style(
            margin: Margins.only(bottom: themeConfig.paragraphSpacing),
            textAlign: parseTextAlign(themeConfig.textAlign),
            color: effectiveTextColor,
            backgroundColor: isEInk ? Colors.transparent : null,
          ),
          "span": Style(
            color: effectiveTextColor,
            backgroundColor: isEInk ? Colors.transparent : null,
          ),
          "h1": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "h2": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "h3": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "h4": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "h5": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "h6": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "blockquote": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "li": Style(color: effectiveTextColor, backgroundColor: isEInk ? Colors.transparent : null),
          "img": Style(
            width: Width(100, Unit.percent),
            height: Height.auto(),
            display: Display.block,
            margin: Margins.only(bottom: 24.0),
          ),
          "image": Style(
            width: Width(100, Unit.percent),
            height: Height.auto(),
            display: Display.block,
            margin: Margins.only(bottom: 24.0),
          ),
          "svg": Style(
            width: Width(100, Unit.percent),
            height: Height.auto(),
            display: Display.block,
            margin: Margins.only(bottom: 24.0),
          ),
          "figure": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            display: Display.block,
            textAlign: TextAlign.center,
          ),
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedImageWidget(ExtensionContext ctx, BuildContext context) {
    String src = '';
    String? alt = ctx.attributes['alt'];

    if (ctx.elementName == 'svg') {
      final imageChild = ctx.element?.querySelector('image, img');
      if (imageChild != null) {
        alt ??= imageChild.attributes['alt'];
        for (final entry in imageChild.attributes.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k.contains('href') || k == 'src') {
            final val = entry.value.trim();
            if (val.isNotEmpty) {
              src = val;
              break;
            }
          }
        }
      }
      if (src.isEmpty) {
        src = ctx.attributes['data-src']?.trim() ?? '';
      }
    } else if (ctx.elementName == 'image') {
      for (final entry in ctx.attributes.entries) {
        final k = entry.key.toString().toLowerCase();
        if (k.contains('href') || k == 'src') {
          final val = entry.value.trim();
          if (val.isNotEmpty) {
            src = val;
            break;
          }
        }
      }
    } else if (ctx.elementName == 'object') {
      src = ctx.attributes['data']?.trim() ?? '';
    } else {
      // img
      src = ctx.attributes['src']?.trim() ?? '';
    }

    if (src.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageProvider = _resolveImageProvider(src);
    if (imageProvider == null) {
      if (alt != null && alt.isNotEmpty) {
        return Text(alt, style: const TextStyle(fontStyle: FontStyle.italic));
      }
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final maxHeight = screenHeight * 0.92;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth,
            maxHeight: maxHeight,
          ),
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Failed to render embedded image ($src): $error');
              if (alt != null && alt.isNotEmpty) {
                return Text(alt, style: const TextStyle(fontStyle: FontStyle.italic));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  static ImageProvider? _resolveImageProvider(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('data:image/')) {
      final commaIdx = trimmed.indexOf(',');
      if (commaIdx != -1) {
        final b64 = trimmed.substring(commaIdx + 1).trim();
        try {
          final bytes = base64Decode(b64);
          return MemoryImage(bytes);
        } catch (e) {
          debugPrint('Error decoding base64 image: $e');
          return null;
        }
      }
    }

    if (trimmed.startsWith('file://')) {
      try {
        final uri = Uri.parse(trimmed);
        final file = File(uri.toFilePath());
        if (file.existsSync()) {
          return FileImage(file);
        }
        final fallback = File(trimmed.substring(7));
        if (fallback.existsSync()) {
          return FileImage(fallback);
        }
      } catch (_) {
        final fallback = File(trimmed.replaceFirst('file://', ''));
        if (fallback.existsSync()) {
          return FileImage(fallback);
        }
      }
    }

    final directFile = File(trimmed);
    if (directFile.isAbsolute && directFile.existsSync()) {
      return FileImage(directFile);
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return NetworkImage(trimmed);
    }

    if (trimmed.startsWith('asset:')) {
      return AssetImage(trimmed.substring(6));
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final annotationRepo = context.watch<AnnotationRepository>();
    final themeConfig = themeRepo.config;
    final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
    final chapterAnnotations = annotationRepo
        .getAnnotationsForBook(widget.chapterController.book.id)
        .where((a) => a.chapterIndex == widget.chapterIndex)
        .toList();

    final extensions = [
      TagExtension(
        tagsToExtend: {'img', 'image', 'svg', 'object'},
        builder: (extensionContext) =>
            _buildEmbeddedImageWidget(extensionContext, context),
      ),
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
        builder: (context) {
          final isCurrent = widget.chapterIndex == widget.chapterController.currentChapterIndex;
          final text = context.node.text ?? '';
          final style =
              context.style?.generateTextStyle() ?? const TextStyle();
          return _TtsHighlightSpan(
            key: isCurrent
                ? widget.ttsController.ttsHighlightKey
                : null,
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

    final staticChild = _buildHtmlContent(
      extensions: extensions,
      horizontalMargin: horizontalMargin,
      themeConfig: themeConfig,
      annotations: chapterAnnotations,
    );

    return ListenableBuilder(
      listenable: widget.ttsController,
      child: staticChild,
      builder: (context, child) {
        final isCurrentChapter =
            widget.chapterIndex == widget.chapterController.currentChapterIndex;
        final isTtsActive = widget.ttsController.showTtsControls ||
            widget.ttsController.ttsService.state != TtsState.stopped;
        final hasHighlight = widget.ttsController.lastHighlightStart != null;

        if (!isCurrentChapter || !isTtsActive || !hasHighlight) {
          return child!;
        }

        widget.ttsController.highlightKeyAssigned = false;
        final highlightStart = widget.ttsController.lastHighlightStart!;
        final highlightEnd = widget.ttsController.lastHighlightEnd ?? highlightStart;

        // Paged mode: single slice TTS highlight
        if (widget.pageSlice != null) {
          final slice = widget.pageSlice!;
          if (highlightStart >= slice.startCharOffset && highlightStart < slice.endCharOffset) {
            final localStart = (highlightStart - slice.startCharOffset).clamp(0, slice.html.length);
            final localEnd = (highlightEnd - slice.startCharOffset).clamp(localStart, slice.html.length);

            var sliceHtml = widget.ttsController.buildTtsHighlightedHtml(
              slice.html,
              overrideStart: localStart,
              overrideEnd: localEnd,
            );
            if (themeConfig.hyphenation || themeConfig.paragraphIndent) {
              sliceHtml = HyphenationHelper.processHtmlAndIndent(
                sliceHtml,
                applyHyphenation: themeConfig.hyphenation,
                applyIndent: themeConfig.paragraphIndent,
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.ttsController.maybeEnsureHighlightVisible();
            });
            return _buildHtmlWidget(
              [sliceHtml],
              extensions: extensions,
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

        // Guardrail 2: Translate chapter-level TTS offsets to chunk-local offsets
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
            );
            if (chapterAnnotations.isNotEmpty) {
              chunk = AnnotationHighlightHelper.applyHighlights(chunk, chapterAnnotations);
            }
            if (themeConfig.hyphenation || themeConfig.paragraphIndent) {
              chunk = HyphenationHelper.processHtmlAndIndent(
                chunk,
                applyHyphenation: themeConfig.hyphenation,
                applyIndent: themeConfig.paragraphIndent,
              );
            }
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
          extensions: extensions,
          horizontalMargin: horizontalMargin,
          themeConfig: themeConfig,
        );
      },
    );
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


