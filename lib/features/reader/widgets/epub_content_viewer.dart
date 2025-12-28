import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/core/utils/performance.dart';

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
  final Map<String, String> _hyphenatedHtmlCache = {};

  Future<String> _getHyphenatedHtml(int index, String rawHtml, ReaderThemeConfig theme) async {
    if (!theme.hyphenation) return rawHtml;
    
    final key = '$index:${theme.hashCode}';
    if (_hyphenatedHtmlCache.containsKey(key)) {
      return _hyphenatedHtmlCache[key]!;
    }
    
    final processed = await measureAsync('epub_hyphenation', () => compute(HyphenationHelper.processHtmlIsolated, rawHtml));
    _hyphenatedHtmlCache[key] = processed;
    return processed;
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

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final themeConfig = themeRepo.config;
    final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
    // Show highlights when TTS is playing OR controls are visible (paused state)
    final isTtsActive = widget.ttsController.showTtsControls || 
                        widget.ttsController.ttsService.state == TtsState.playing;
    final isCurrentChapter = widget.chapterIndex == widget.chapterController.currentChapterIndex;

    const ttsHighlightTag = 'tts-highlight';
    final highlightColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);

    final extensions = [
      TagExtension(
        tagsToExtend: {ttsHighlightTag},
        builder: (context) {
          final text = context.node.text ?? '';
          final style = context.style?.generateTextStyle() ?? const TextStyle();
          return _TtsHighlightSpan(
            key: isCurrentChapter ? widget.ttsController.ttsHighlightKey : null,
            text: text,
            textStyle: style,
            highlightColor: highlightColor,
          );
        },
      ),
    ];

    Widget buildHtml(String content) {
      return FutureBuilder<String>(
        future: _getHyphenatedHtml(widget.chapterIndex, content, themeConfig),
        initialData: _hyphenatedHtmlCache['${widget.chapterIndex}:${themeConfig.hashCode}'],
        builder: (context, snapshot) {
          final displayContent = snapshot.data ?? content;
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
                  textAlign: _parseTextAlign(themeConfig.textAlign),
                  letterSpacing: themeConfig.wordSpacing,
                  padding: HtmlPaddings.zero,
                  margin: Margins.zero,
                ),
                ttsHighlightTag: Style(
                  backgroundColor: highlightColor,
                ),
                "p": Style(
                  margin: Margins.only(bottom: themeConfig.paragraphSpacing),
                  textAlign: _parseTextAlign(themeConfig.textAlign),
                ),
                "img": Style(
                  width: Width(100, Unit.percent),
                  margin: Margins.only(bottom: 24.0), // Fixed image spacing
                ),
              },
            ),
          );
        },
      );
    }

    if (isTtsActive && isCurrentChapter) {
      return ListenableBuilder(
        listenable: widget.ttsController,
        builder: (context, _) {
          widget.ttsController.highlightKeyAssigned = false;
          final content = widget.ttsController.buildTtsHighlightedHtml(widget.htmlContent);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.ttsController.maybeEnsureHighlightVisible();
          });
          return buildHtml(content);
        },
      );
    } else {
      return buildHtml(widget.htmlContent);
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
    final borderColor = isDark ? Colors.yellow.shade600 : Colors.orange.shade700;

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
