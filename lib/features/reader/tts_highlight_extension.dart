import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:ferrous/data/models/tts_highlight_style.dart';

/// Centralized inline TagExtension builder for TTS word highlighting across
/// EPUB, MOBI, TXT, and DOCX (HtmlReaderScreen).
///
/// Guarantees strict layout-metrics invariance:
/// - Never introduces WidgetSpan, Container, Padding, Margin, or border geometry into the text.
/// - Never alters font-size, font-weight, line-height, or letter-spacing (preventing glyph advance dilation).
/// - Styles exclusively via TextStyle.backgroundColor, TextStyle.color, and TextStyle.decoration.
/// - Preserves continuous-mode auto-scrolling via a zero-geometry anchor WidgetSpan.
class TtsHighlightExtension {
  static TagExtension build({
    required bool Function() isSpeaking,
    required bool isPaged,
    required GlobalKey? ttsHighlightKey,
    required TtsHighlightStyle highlightStyle,
    required Color primaryColor,
    required bool isEInk,
  }) {
    bool keyAttached = false;

    return TagExtension.inline(
      tagsToExtend: {'tts-highlight'},
      builder: (ctx) {
        final text = ctx.node.text ?? '';
        final baseStyle = ctx.style?.generateTextStyle() ?? const TextStyle();

        TextStyle highlightTextStyle;
        if (isEInk) {
          highlightTextStyle = baseStyle.copyWith(
            backgroundColor: const Color(0xFFD5D0C5),
            color: const Color(0xFF1A1A18),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF1A1A18),
            decorationThickness: 2.0,
          );
        } else {
          switch (highlightStyle) {
            case TtsHighlightStyle.softPill:
              highlightTextStyle = baseStyle.copyWith(
                backgroundColor: primaryColor.withValues(alpha: 0.24),
                color: primaryColor,
              );
              break;
            case TtsHighlightStyle.underline:
              highlightTextStyle = baseStyle.copyWith(
                color: primaryColor,
                decoration: TextDecoration.underline,
                decorationColor: primaryColor,
                decorationThickness: 2.5,
              );
              break;
            case TtsHighlightStyle.classicClean:
              highlightTextStyle = baseStyle.copyWith(
                backgroundColor: primaryColor.withValues(alpha: 0.16),
                color: primaryColor,
                decoration: TextDecoration.underline,
                decorationColor: primaryColor.withValues(alpha: 0.6),
                decorationThickness: 1.5,
              );
              break;
          }
        }

        InlineSpan applyHighlightStyles(InlineSpan span) {
          if (span is TextSpan) {
            final mergedStyle = span.style != null
                ? span.style!.copyWith(
                    backgroundColor: highlightTextStyle.backgroundColor,
                    color: highlightTextStyle.color,
                    decoration: highlightTextStyle.decoration,
                    decorationColor: highlightTextStyle.decorationColor,
                    decorationThickness: highlightTextStyle.decorationThickness,
                    decorationStyle: highlightTextStyle.decorationStyle,
                  )
                : highlightTextStyle;

            return TextSpan(
              text: span.text,
              children: span.children?.map(applyHighlightStyles).toList(),
              style: mergedStyle,
              recognizer: span.recognizer,
              semanticsLabel: span.semanticsLabel,
            );
          }
          return span;
        }

        final contentSpan = (ctx.inlineSpanChildren != null && ctx.inlineSpanChildren!.isNotEmpty)
            ? TextSpan(
                children: ctx.inlineSpanChildren!.map(applyHighlightStyles).toList(),
                style: highlightTextStyle,
              )
            : TextSpan(
                text: text,
                style: highlightTextStyle,
              );

        // In continuous mode when speaking, prepend a zero-geometry anchor WidgetSpan so
        // Scrollable.ensureVisible(ttsHighlightKey.currentContext) continues to work without
        // adding any vertical line-height inflation or horizontal word dilation.
        // In paged mode, return pure TextSpan with zero WidgetSpans.
        // Only attach key to the first occurrence in a render pass to prevent duplicate GlobalKey assertions.
        final shouldAttachKey = !isPaged && isSpeaking() && ttsHighlightKey != null && !keyAttached;
        if (shouldAttachKey) {
          keyAttached = true;
          try {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              keyAttached = false;
            });
          } catch (_) {}

          return TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(
                  key: ttsHighlightKey,
                  width: 0,
                  height: 1,
                ),
              ),
              contentSpan,
            ],
          );
        }

        return contentSpan;
      },
    );
  }
}
