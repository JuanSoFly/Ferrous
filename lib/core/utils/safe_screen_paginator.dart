import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:image/image.dart' as img;
import 'package:ferrous/core/models/annotation.dart';
import 'package:ferrous/core/utils/dom_text_utils.dart';
import 'package:ferrous/core/utils/reader_typography_metrics.dart';
import 'package:ferrous/features/reader/annotation_highlight_helper.dart';
import 'package:ferrous/features/reader/hyphenation_helper.dart';
import 'package:ferrous/core/utils/xml_html_normalizer.dart';
import 'package:ferrous/core/utils/css_rule_resolver.dart';

/// Represents a single screen-fitted slice of an EPUB/MOBI chapter.
class PageSlice {
  final String html;
  final int startCharOffset;
  final int endCharOffset;
  final int pageIndex;
  final double? estimatedHeight;

  const PageSlice({
    required this.html,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.pageIndex,
    this.estimatedHeight,
  });

  @override
  String toString() =>
      'PageSlice(pageIndex: $pageIndex, range: [$startCharOffset..$endCharOffset], htmlLen: ${html.length}, estH: $estimatedHeight)';
}

class SafeScreenPaginator {
  // Bounded LRU cache of paginated slices
  static final Map<String, List<PageSlice>> _cache = {};

  static const Set<String> _blockTags = {
    'p', 'div', 'section', 'article', 'main', 'aside', 'header', 'footer',
    'blockquote', 'figure', 'figcaption', 'pre', 'ul', 'ol', 'li', 'dl',
    'dt', 'dd', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr',
    // Treat standalone media/replaced elements as block-level for pagination measurement
    'img', 'svg', 'image', 'video', 'canvas',
  };

  static bool _isBlockNode(dom.Node node) {
    if (node is! dom.Element) return false;
    final tag = node.localName?.toLowerCase() ?? '';
    if (_blockTags.contains(tag)) return true;
    return node.querySelector(_blockTags.join(',')) != null;
  }

  static bool _hasMeaningfulNonTextContent(dom.Element el) {
    if (el.attributes.containsKey('id') || el.attributes.containsKey('name')) {
      return true;
    }
    return el.querySelector('img, svg, image, br, hr, [id], [name]') != null;
  }

  static void clearCache() {
    _cache.clear();
  }

  static void invalidateBook(String bookId) {
    _cache.removeWhere((key, _) => key.startsWith('$bookId:'));
  }

  /// Fast binary header probe to extract image dimensions in <1 microsecond without decoding full bitmap.
  static Size? _probeImageDimensions(Uint8List bytes) {
    if (bytes.length < 10) return null;

    // 1. PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
    }

    // 2. GIF: 'GIF87a' or 'GIF89a'
    if (bytes.length >= 10 &&
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      final width = bytes[6] | (bytes[7] << 8);
      final height = bytes[8] | (bytes[9] << 8);
      if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
    }

    // 3. JPEG: FF D8
    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        if ((marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF)) {
          if (offset + 9 < bytes.length) {
            final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
            if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
          }
          break;
        }
        if (marker == 0xDA || marker == 0xD9) break; // SOS or EOI
        if (offset + 3 >= bytes.length) break;
        final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
        if (length <= 0) break;
        offset += 2 + length;
      }
    }

    // 4. WebP: 'RIFF' .... 'WEBP'
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
        if (bytes.length >= 30) {
          final width = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
          final height = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
          if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
        }
      }
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C) {
        if (bytes.length >= 25 && bytes[20] == 0x2F) {
          final b1 = bytes[21];
          final b2 = bytes[22];
          final b3 = bytes[23];
          final b4 = bytes[24];
          final width = 1 + (((b2 & 0x3F) << 8) | b1);
          final height = 1 + ((((b4 & 0xF) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6)));
          if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
        }
      }
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58) {
        if (bytes.length >= 30) {
          final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
          final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
          if (width > 0 && height > 0) return Size(width.toDouble(), height.toDouble());
        }
      }
    }

    return null;
  }

  /// Paginates a chapter into screen-fitted slices with accurate typography and DOM preservation
  static List<PageSlice> paginateChapter({
    required String bookId,
    required int chapterIndex,
    required String chapterHtml,
    required String chapterPlainText,
    required double availableWidth,
    required double availableHeight,
    required double fontSize,
    required double lineHeight,
    required double paragraphSpacing,
    required String? fontFamily,
    required bool paragraphIndent,
    required bool hyphenation,
    required List<Annotation> annotations,
    TextAlign textAlign = TextAlign.justify,
    FontWeight fontWeight = FontWeight.normal,
    double wordSpacing = 0.0,
    TextScaler textScaler = TextScaler.noScaling,
    String languageCode = 'en',
    Map<String, ResolvedCssRule> cssRules = const {},
  }) {
    if (availableWidth <= 0 || availableHeight <= 0) {
      return [
        PageSlice(
          html: chapterHtml,
          startCharOffset: 0,
          endCharOffset: chapterPlainText.length,
          pageIndex: 0,
        ),
      ];
    }

    final annotationSig = annotations.isEmpty
        ? '0'
        : annotations.map((a) => '${a.id}:${a.color}').join(',');

    final primaryLang = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    final textScale = textScaler.scale(10.0) / 10.0;
    final cssSig = cssRules.isNotEmpty ? cssRules.length : 0;
    final cacheKey =
        '$bookId:$chapterIndex:${availableWidth.toInt()}x${availableHeight.toInt()}:'
        '${fontSize.toStringAsFixed(1)}:${lineHeight.toStringAsFixed(2)}:'
        '${paragraphSpacing.toStringAsFixed(1)}:${fontFamily ?? "default"}:'
        '${textAlign.name}:${fontWeight.value}:${wordSpacing.toStringAsFixed(2)}:'
        '$paragraphIndent:$hyphenation:$primaryLang:${textScale.toStringAsFixed(2)}:$cssSig:$annotationSig';

    final cached = _cache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // Step 1: Pre-process chapter HTML with annotation highlights BEFORE pagination
    final processedHtml = annotations.isNotEmpty
        ? AnnotationHighlightHelper.applyHighlights(chapterHtml, annotations)
        : chapterHtml;

    final normalizedHtml = XmlHtmlNormalizer.normalizeXmlSelfClosingTags(processedHtml);
    final document = html_parser.parse(normalizedHtml);
    final body = document.body;
    if (body == null) {
      final fallback = [
        PageSlice(
          html: chapterHtml,
          startCharOffset: 0,
          endCharOffset: chapterPlainText.length,
          pageIndex: 0,
        ),
      ];
      _cache[cacheKey] = fallback;
      return fallback;
    }

    // Stamp narrative prose markers if missing to guarantee layout parity with EpubContentViewer
    if (body.querySelector('.ferrous-prose') == null) {
      stampProseMarkers(body, cssRules);
    }

    final headHtml =
        document.head?.outerHtml ?? '<head><meta charset="utf-8"></head>';
    final bodyAttrs = _serializeAttributes(body, stripId: false);

    // Resolve TextStyle matching EpubContentViewer exactly (letterSpacing = wordSpacing)
    TextStyle resolveTextStyle({
      required String? fontFamily,
      required double fontSize,
      required double lineHeight,
      required FontWeight fontWeight,
      required double wordSpacing,
    }) {
      TextStyle base;
      if (fontFamily == null || fontFamily.isEmpty || fontFamily == 'default') {
        base = TextStyle(fontSize: fontSize, height: lineHeight, fontWeight: fontWeight);
      } else {
        try {
          base = GoogleFonts.getFont(fontFamily, fontSize: fontSize, height: lineHeight, fontWeight: fontWeight);
        } catch (_) {
          base = TextStyle(fontFamily: fontFamily, fontSize: fontSize, height: lineHeight, fontWeight: fontWeight);
        }
      }
      return base.copyWith(
        fontFamilyFallback: [
          if (base.fontFamilyFallback != null) ...base.fontFamilyFallback!,
          if (fontFamily != null) fontFamily,
          'Roboto',
          'Noto Sans',
          'sans-serif',
        ],
        letterSpacing: wordSpacing,
        wordSpacing: null,
        locale: Locale(primaryLang),
      );
    }

    final baseStyle = resolveTextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      lineHeight: lineHeight,
      fontWeight: fontWeight,
      wordSpacing: wordSpacing,
    );

    // Intrinsic font line height: probe with TextPainter to match Skia/flutter_html actual line box height
    final textPainterProbe = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale(primaryLang),
      text: TextSpan(text: 'M', style: baseStyle),
    );
    textPainterProbe.layout();
    final intrinsicLineHeight = textPainterProbe.preferredLineHeight;
    final singleLineHeight = math.max(fontSize * lineHeight, intrinsicLineHeight);

    // Dynamic canvas bounds: snap to whole integer line multiples with 1.0 line headroom reserve
    // (expanded to 2.0 lines when publisher CSS rules are active to prevent margin accumulation overflow)
    final double reserveHeadroom = cssRules.isNotEmpty
        ? (singleLineHeight * 2.0) + 8.0
        : singleLineHeight + 4.0;
    final int wholeLineCount = math.max(
      1,
      ((availableHeight - reserveHeadroom) / singleLineHeight).floor(),
    );
    final double upperLimit = math.max(singleLineHeight, availableHeight - reserveHeadroom);
    final double lowerLimit = math.min(singleLineHeight, upperLimit);
    final double maxPageHeight = (wholeLineCount * singleLineHeight)
        .clamp(lowerLimit, upperLimit)
        .toDouble();

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: TextScaler.noScaling,
      locale: Locale(primaryLang),
    );

    final indentWidth = ReaderTypographyMetrics.computeIndentWidth(fontSize);
    final indentPlaceholder = PlaceholderDimensions(
      size: Size(indentWidth, 1.0),
      alignment: PlaceholderAlignment.middle,
    );

    double measureTextHeight(
      String text, {
      double fontScale = 1.0,
      bool isIndent = false,
      double extraTopMargin = 0.0,
      double extraBottomMargin = 0.0,
      bool isPre = false,
      bool isHeading = false,
      bool isBold = false,
      bool isItalic = false,
      double layoutWidth = double.infinity,
      int brCount = 0,
      bool hasNonBreakingSpace = false,
    }) {
      final sanitized = text.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').trim();
      final normalized = isPre
          ? text
          : (hyphenation ? sanitized : HyphenationHelper.stripSoftHyphens(sanitized));
      if (normalized.isEmpty) {
        final lines = math.max(1, brCount > 0 ? (brCount + 1) : 1);
        return (lines * fontSize * fontScale * lineHeight) + extraTopMargin + extraBottomMargin;
      }

      final effectiveStyle = isHeading
          ? baseStyle.copyWith(
              fontSize: fontSize * fontScale,
              fontWeight: FontWeight.bold,
            )
          : isPre
              ? baseStyle.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['monospace'],
                  fontSize: fontScale == 1.0 ? fontSize : fontSize * fontScale,
                  fontWeight: isBold ? FontWeight.bold : fontWeight,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                )
              : baseStyle.copyWith(
                  fontSize: fontScale == 1.0 ? fontSize : fontSize * fontScale,
                  fontWeight: isBold ? FontWeight.bold : fontWeight,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                );

      textPainter.text = TextSpan(
        style: effectiveStyle,
        children: [
          if (isIndent)
            WidgetSpan(child: SizedBox(width: indentWidth, height: 1.0)),
          TextSpan(text: normalized),
        ],
      );

      if (isIndent) {
        textPainter.setPlaceholderDimensions([indentPlaceholder]);
      } else {
        textPainter.setPlaceholderDimensions(const []);
      }

      final effectiveMaxWidth = (layoutWidth.isFinite && layoutWidth > 0)
          ? layoutWidth
          : availableWidth;
      textPainter.layout(maxWidth: effectiveMaxWidth);
      return textPainter.height + extraTopMargin + extraBottomMargin;
    }

    final pages = <PageSlice>[];
    final pageHeights = <double>[];
    final currentBuffer = StringBuffer();
    final openAncestors = <dom.Element>[];
    double currentHeight = 0.0;
    int runningCharOffset = 0;
    int pageStartCharOffset = 0;

    bool hasSubstantiveContent(dom.Element container) {
      if (container.text.trim().isNotEmpty) return true;
      return container.querySelector('img, svg, image, canvas, video, hr, table') != null;
    }

    void flushPage({bool isEndOfChapter = false}) {
      if (currentHeight == 0 && runningCharOffset == pageStartCharOffset && currentBuffer.isEmpty) {
        return;
      }

      final closeBuffer = StringBuffer();
      for (final el in openAncestors.reversed) {
        closeBuffer.write('</${el.localName ?? 'div'}>');
      }

      final wellFormedFragmentHtml = '${currentBuffer.toString()}$closeBuffer';
      final testContainer = dom.Element.html('<div>$wellFormedFragmentHtml</div>');

      if (!hasSubstantiveContent(testContainer)) {
        if (!isEndOfChapter) {
          // Mid-chapter: keep reopened ancestor wrappers and leading anchors in currentBuffer,
          // but zero out height so the incoming block gets the full page height budget.
          currentHeight = 0.0;
          return;
        }

        // End-of-chapter: only splice into pages.last if there is an anchor target to preserve
        if (pages.isNotEmpty && testContainer.querySelector('[id], [name]') != null) {
          final lastSlice = pages.last;
          final updatedHtml = lastSlice.html.replaceFirst(
            '</body>',
            '$wellFormedFragmentHtml</body>',
          );
          pages[pages.length - 1] = PageSlice(
            html: updatedHtml,
            startCharOffset: lastSlice.startCharOffset,
            endCharOffset: runningCharOffset,
            pageIndex: lastSlice.pageIndex,
          );
        }
        currentBuffer.clear();
        currentHeight = 0.0;
        pageStartCharOffset = runningCharOffset;
        return;
      }

      final cleanFragment = wellFormedFragmentHtml
          .trim()
          .replaceAllMapped(
            RegExp(
              r'(</(?:p|div|h[1-6]|blockquote|li|ul|ol|table|tr|td|th)>)\s+(<(?:p|div|h[1-6]|blockquote|li|ul|ol|table|tr|td|th))',
              caseSensitive: false,
            ),
            (m) => '${m[1]}${m[2]}',
          );

      final sliceHtml =
          '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>$cleanFragment</body></html>';
      pageHeights.add(currentHeight);
      pages.add(
        PageSlice(
          html: sliceHtml,
          startCharOffset: pageStartCharOffset,
          endCharOffset: runningCharOffset,
          pageIndex: pages.length,
          estimatedHeight: currentHeight,
        ),
      );
      currentBuffer.clear();
      currentHeight = 0.0;
      pageStartCharOffset = runningCharOffset;

      // Re-open active ancestors for next page slice
      for (final el in openAncestors) {
        final tag = el.localName ?? 'div';
        final attrs = _serializeAttributes(el, stripId: true);
        currentBuffer.write('<$tag$attrs style="margin-top: 0px !important; padding-top: 0px !important; margin-bottom: 0px !important; padding-bottom: 0px !important;">');
      }
    }

    late final void Function(List<dom.Node>) processNodes;

    void processBlockElement(dom.Element node, {bool isAnonymous = false}) {
      // Intercept explicit MOBI / EPUB pagebreaks
      if (node.classes.contains('ferrous-pagebreak') ||
          node.attributes['data-pagebreak'] == 'true') {
        flushPage();
        return;
      }

      final tag = node.localName?.toLowerCase() ?? '';

      // Structural container elements with block children
      final hasBlockChildren = !isAnonymous &&
          tag != 'table' &&
          tag != 'p' &&
          node.children.any((c) => _blockTags.contains(c.localName?.toLowerCase()));

      if (hasBlockChildren) {
        final id = (node.attributes['id'] ?? '').trim();
        if (id.isNotEmpty) {
          final escapedId = const HtmlEscape(HtmlEscapeMode.attribute).convert(id);
          currentBuffer.write('<span id="$escapedId"></span>');
        }

        final isPageContainer = tag == 'article' || tag == 'section' || tag == 'main';
        final containerMargins = (!isPageContainer && cssRules.isNotEmpty)
            ? CssRuleResolver.resolveVerticalMargins(node, cssRules, baseFontSize: fontSize)
            : (top: 0.0, bottom: 0.0, hasExplicitTop: false, hasExplicitBottom: false);

        if (containerMargins.top > 0) {
          currentHeight += containerMargins.top;
        }

        final containerAttrs = _serializeAttributes(node, stripId: false);
        if (isPageContainer) {
          currentBuffer.write('<$tag$containerAttrs style="margin: 0px !important; padding: 0px !important;">');
        } else {
          currentBuffer.write('<$tag$containerAttrs>');
        }
        openAncestors.add(node);

        processNodes(node.nodes);

        if (openAncestors.isNotEmpty && openAncestors.last == node) {
          openAncestors.removeLast();
          currentBuffer.write('</$tag>');
          if (containerMargins.bottom > 0) {
            currentHeight += containerMargins.bottom;
          }
        }
        return;
      }

      final isHeading = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag);
      final hasImage = tag == 'img' ||
          tag == 'svg' ||
          tag == 'image' ||
          node.querySelector('img, svg, image') != null;

      final dom.Element targetElement;
      if (!hasImage && !isHeading) {
        final cloned = node.clone(true);
        HyphenationHelper.processElement(
          cloned,
          applyHyphenation: hyphenation && tag != 'pre',
          applyIndent: !isAnonymous && paragraphIndent && tag != 'pre',
          languageCode: primaryLang,
          cssRules: cssRules,
        );
        targetElement = cloned;
      } else {
        targetElement = node;
      }

      final nodeText = _extractMeasurementText(targetElement, isPre: tag == 'pre');
      final textLen = DomTextUtils.extractPlainText(targetElement, preserveSoftHyphens: true).length;

      // Compute lateral insets (with ancestor summation) and vertical margins from CSS AST + inline styles
      final lateralInsets = cssRules.isNotEmpty
          ? CssRuleResolver.resolveLateralInsets(
              targetElement,
              cssRules,
              fontSize,
              availableWidth,
              ancestors: openAncestors,
            )
          : 0.0;
      final isInsideList = openAncestors.any((a) => a.localName == 'ul' || a.localName == 'ol') || tag == 'li';
      final listIndent = isInsideList ? 24.0 : 0.0;
      final effectiveBlockWidth = math.max(100.0, availableWidth - lateralInsets - listIndent);

      final verticalMargins = cssRules.isNotEmpty
          ? CssRuleResolver.resolveVerticalMargins(targetElement, cssRules, baseFontSize: fontSize)
          : (top: 0.0, bottom: 0.0, hasExplicitTop: false, hasExplicitBottom: false);

      // Implementation Detail 1: Synchronize margins with .ferrous-prose
      final isProse = targetElement.classes.contains('ferrous-prose');
      final effectiveTopMargin = isAnonymous
          ? 0.0
          : (isProse ? 0.0 : verticalMargins.top);
      final effectiveBottomMargin = isAnonymous
          ? 0.0
          : (isProse
              ? paragraphSpacing
              : (tag == 'li'
                  ? 4.0
                  : (verticalMargins.hasExplicitBottom
                      ? verticalMargins.bottom
                      : ((tag == 'p' || tag == 'pre' || tag == 'ul' || tag == 'ol') ? paragraphSpacing : 0.0))));

      double effectiveFontScale = 1.0;
      FontStyle? inheritedFontStyle;
      FontWeight? inheritedFontWeight;
      String? inheritedTextAlign;

      for (final ancestor in openAncestors) {
        final ancRule = cssRules.isNotEmpty ? CssRuleResolver.resolveRule(ancestor, cssRules) : null;
        if (ancRule != null) {
          if (ancRule.fontSizeScale != null) {
            effectiveFontScale *= ancRule.fontSizeScale!;
          }
          if (ancRule.fontStyle != null) {
            inheritedFontStyle = ancRule.fontStyle;
          }
          if (ancRule.fontWeight != null) {
            inheritedFontWeight = ancRule.fontWeight;
          }
          if (ancRule.textAlign != null && ancRule.textAlign!.isNotEmpty) {
            inheritedTextAlign = ancRule.textAlign;
          }
        }
      }

      final resolvedRule = cssRules.isNotEmpty ? CssRuleResolver.resolveRule(targetElement, cssRules) : null;
      if (resolvedRule?.fontSizeScale != null) {
        effectiveFontScale *= resolvedRule!.fontSizeScale!;
      }
      final cssFontScale = effectiveFontScale;
      final bool isBold = (resolvedRule?.fontWeight ?? inheritedFontWeight) == FontWeight.bold ||
          tag == 'b' ||
          tag == 'strong' ||
          targetElement.querySelector('b, strong') != null;
      final bool isItalic = (resolvedRule?.fontStyle ?? inheritedFontStyle) == FontStyle.italic ||
          tag == 'i' ||
          tag == 'em' ||
          (targetElement.children.isNotEmpty &&
              targetElement.children.every((c) => c.localName == 'i' || c.localName == 'em'));

      double resolveImageHeight(dom.Element el) {
        final imgEl = el.localName?.toLowerCase() == 'img' ? el : el.querySelector('img');
        if (imgEl == null) return (maxPageHeight * 0.72) + effectiveTopMargin + effectiveBottomMargin;

        final hAttr = double.tryParse(imgEl.attributes['height'] ?? '');
        final wAttr = double.tryParse(imgEl.attributes['width'] ?? '');
        if (hAttr != null && hAttr > 0) {
          final scaledH = (wAttr != null && wAttr > 0 && wAttr > availableWidth)
              ? (hAttr * (availableWidth / wAttr))
              : hAttr;
          final effectiveH = math.max(singleLineHeight, scaledH);
          return effectiveH + effectiveTopMargin + effectiveBottomMargin;
        }

        final src = imgEl.attributes['src'] ?? '';
        if (src.startsWith('data:image')) {
          final comma = src.indexOf(',');
          if (comma != -1) {
            try {
              final bytes = base64Decode(src.substring(comma + 1).trim());
              final probed = _probeImageDimensions(bytes);
              final imgWidth = probed?.width ?? (img.decodeImage(bytes)?.width.toDouble() ?? 0.0);
              final imgHeight = probed?.height ?? (img.decodeImage(bytes)?.height.toDouble() ?? 0.0);
              if (imgWidth > 0 && imgHeight > 0) {
                final scale = math.min(1.0, availableWidth / imgWidth);
                final scaledH = imgHeight * scale;
                final effectiveH = math.max(singleLineHeight, scaledH);
                return effectiveH + effectiveTopMargin + effectiveBottomMargin;
              }
            } catch (_) {}
          }
        }
        return (maxPageHeight * 0.72) + effectiveTopMargin + effectiveBottomMargin;
      }

      final double blockHeight;
      if (hasImage) {
        blockHeight = resolveImageHeight(targetElement);
      } else if (isHeading) {
        final scale = (cssRules.isNotEmpty && resolvedRule?.fontSizeScale != null)
            ? resolvedRule!.fontSizeScale!
            : ReaderTypographyMetrics.headingScale(tag);
        final topMargin = 0.0;
        final bottomMargin = paragraphSpacing;
        blockHeight = measureTextHeight(
          nodeText,
          fontScale: scale,
          isIndent: false,
          extraTopMargin: topMargin,
          extraBottomMargin: bottomMargin,
          isHeading: true,
          layoutWidth: effectiveBlockWidth,
        );
      } else {
        final bool hasIndent = !isAnonymous && paragraphIndent && targetElement.querySelector('p-indent') != null;
        final brCount = targetElement.querySelectorAll('br').length;
        final hasNbsp = targetElement.text.contains('\u00A0') || targetElement.innerHtml.contains('&nbsp;');
        blockHeight = measureTextHeight(
          nodeText,
          fontScale: cssFontScale,
          isIndent: hasIndent,
          extraTopMargin: effectiveTopMargin,
          extraBottomMargin: effectiveBottomMargin,
          isPre: tag == 'pre',
          isHeading: false,
          isBold: isBold,
          isItalic: isItalic,
          layoutWidth: effectiveBlockWidth,
          brCount: brCount,
          hasNonBreakingSpace: hasNbsp,
        );
      }

      // Keep headings attached to at least 2 lines of text
      if (isHeading &&
          currentHeight > 0 &&
          (currentHeight + blockHeight + (fontSize * lineHeight * 2.0)) > maxPageHeight) {
        flushPage();
      }

      // Standalone image handling
      if (hasImage) {
        if (currentHeight > 0 && (currentHeight + blockHeight) > maxPageHeight) {
          flushPage();
        }
        currentBuffer.write(node.outerHtml);
        currentHeight += blockHeight;
        runningCharOffset += textLen;
        if (blockHeight >= maxPageHeight * 0.6) {
          flushPage();
        }
        return;
      }

      // If block fits on current page, append directly
      if (currentHeight + blockHeight <= maxPageHeight) {
        currentBuffer.write(isAnonymous ? targetElement.innerHtml : targetElement.outerHtml);
        currentHeight += blockHeight;
        runningCharOffset += textLen;
        return;
      }

      // Multi-page paragraph/block splitting
      final canSplit = (tag == 'p' || tag == 'blockquote' || tag == 'div' || tag == 'pre' || tag == 'li') && !hasImage;

      if (canSplit) {
        final double blockLineHeight = (fontSize * cssFontScale) * lineHeight;
        final double minRemainingSpace = blockLineHeight * 2.0;
        double remainingHeight = maxPageHeight - currentHeight;

        // If remaining space on current page is too small (< 2 lines), start fresh on next page
        if (currentHeight > 0 && remainingHeight < minRemainingSpace) {
          flushPage();
          remainingHeight = maxPageHeight;
          if (blockHeight <= maxPageHeight) {
            currentBuffer.write(isAnonymous ? targetElement.innerHtml : targetElement.outerHtml);
            currentHeight += blockHeight;
            runningCharOffset += textLen;
            return;
          }
        }

        final rawTextAlign = resolvedRule?.textAlign ?? inheritedTextAlign;
        final blockTextAlign = (rawTextAlign != null && rawTextAlign.isNotEmpty)
            ? _parseTextAlign(rawTextAlign)
            : textAlign;

        final bool hasIndent = !isAnonymous && paragraphIndent && targetElement.querySelector('p-indent') != null;
        final blockStyle = tag == 'pre'
            ? baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: cssFontScale == 1.0 ? fontSize : fontSize * cssFontScale,
                fontWeight: isBold ? FontWeight.bold : fontWeight,
                fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              )
            : baseStyle.copyWith(
                fontSize: cssFontScale == 1.0 ? fontSize : fontSize * cssFontScale,
                fontWeight: isBold ? FontWeight.bold : fontWeight,
                fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              );
        final brCount = targetElement.querySelectorAll('br').length;
        final hasNbsp = targetElement.text.contains('\u00A0') || targetElement.innerHtml.contains('&nbsp;');

        var splitParts = _splitBlockAcrossPages(
          node: targetElement,
          firstBudget: remainingHeight,
          maxPageHeight: maxPageHeight,
          singleLineHeight: blockLineHeight,
          textStyle: blockStyle,
          textAlign: blockTextAlign,
          effectiveBlockWidth: effectiveBlockWidth,
          hasIndent: hasIndent,
          indentWidth: indentWidth,
          indentPlaceholder: indentPlaceholder,
          primaryLang: primaryLang,
          effectiveTopMargin: effectiveTopMargin,
          effectiveBottomMargin: effectiveBottomMargin,
          measureText: (txt, isIndent, {required bool isFirstPart, required bool isLastPart}) => measureTextHeight(
            txt,
            fontScale: cssFontScale,
            isIndent: isIndent && hasIndent,
            extraTopMargin: isFirstPart ? effectiveTopMargin : 0.0,
            extraBottomMargin: isLastPart ? effectiveBottomMargin : 0.0,
            isPre: tag == 'pre',
            isHeading: false,
            isBold: isBold,
            isItalic: isItalic,
            layoutWidth: effectiveBlockWidth,
            brCount: brCount,
            hasNonBreakingSpace: hasNbsp,
          ),
          isPre: tag == 'pre',
        );

        if (splitParts.isEmpty && currentHeight > 0) {
          flushPage();
          if (blockHeight <= maxPageHeight) {
            currentBuffer.write(isAnonymous ? targetElement.innerHtml : targetElement.outerHtml);
            currentHeight += blockHeight;
            runningCharOffset += textLen;
            return;
          }
          splitParts = _splitBlockAcrossPages(
            node: targetElement,
            firstBudget: maxPageHeight,
            maxPageHeight: maxPageHeight,
            singleLineHeight: blockLineHeight,
            textStyle: blockStyle,
            textAlign: blockTextAlign,
            effectiveBlockWidth: effectiveBlockWidth,
            hasIndent: paragraphIndent && !isAnonymous,
            indentWidth: indentWidth,
            indentPlaceholder: indentPlaceholder,
            primaryLang: primaryLang,
            effectiveTopMargin: effectiveTopMargin,
            effectiveBottomMargin: effectiveBottomMargin,
            measureText: (txt, isIndent, {required bool isFirstPart, required bool isLastPart}) => measureTextHeight(
              txt,
              fontScale: cssFontScale,
              isIndent: isIndent && paragraphIndent && !isAnonymous,
              extraTopMargin: isFirstPart ? effectiveTopMargin : 0.0,
              extraBottomMargin: isLastPart ? effectiveBottomMargin : 0.0,
              isPre: tag == 'pre',
              isHeading: false,
              isBold: isBold,
              isItalic: isItalic,
              layoutWidth: effectiveBlockWidth,
              brCount: brCount,
              hasNonBreakingSpace: hasNbsp,
            ),
            isPre: tag == 'pre',
          );
        }

        for (int partIdx = 0; partIdx < splitParts.length; partIdx++) {
          final part = splitParts[partIdx];
          if (partIdx > 0 || (currentHeight + part.height > maxPageHeight && currentHeight > 0)) {
            flushPage();
          }
          currentBuffer.write(part.html);
          currentHeight += part.height;
          runningCharOffset += part.charLength;
        }
        return;
      }

      // Standard atomic block doesn't fit on current page -> flush and start new page
      if (currentHeight > 0) {
        flushPage();
      }
      currentBuffer.write(isAnonymous ? targetElement.innerHtml : targetElement.outerHtml);
      currentHeight += blockHeight;
      runningCharOffset += textLen;
    }

    void doProcessNodes(List<dom.Node> nodes) {
      int i = 0;
      while (i < nodes.length) {
        final node = nodes[i];

        // Group contiguous inline nodes (Text nodes and non-block Elements)
        if (node is dom.Text || (node is dom.Element && !_isBlockNode(node))) {
          final inlineRun = <dom.Node>[];
          while (i < nodes.length &&
              (nodes[i] is dom.Text ||
                  (nodes[i] is dom.Element && !_isBlockNode(nodes[i])))) {
            inlineRun.add(nodes[i]);
            i++;
          }

          // Use a neutral <div> wrapper so CSS <p> text-indent/margins aren't injected
          final anonBlock = dom.Element.tag('div');
          for (final n in inlineRun) {
            anonBlock.nodes.add(n.clone(true));
          }

          final plainText =
              DomTextUtils.extractPlainText(anonBlock, preserveSoftHyphens: true);
          final hasVisibleText = plainText.replaceAll('\u00A0', ' ').trim().isNotEmpty;

          if (!hasVisibleText) {
            // Preserve empty anchors (<a id="chap01"></a>) or <br/> tags without losing them
            if (_hasMeaningfulNonTextContent(anonBlock)) {
              currentBuffer.write(anonBlock.innerHtml);
              // Count <br> vertical height so spacer lines aren't ignored
              final brCount = anonBlock.querySelectorAll('br').length;
              if (brCount > 0) {
                final hasNbsp = plainText.contains('\u00A0') || anonBlock.innerHtml.contains('&nbsp;');
                final lines = math.max(1, brCount + (hasNbsp ? 1 : 0));
                double scale = 1.0;
                for (final anc in openAncestors) {
                  final ancRule = cssRules.isNotEmpty ? CssRuleResolver.resolveRule(anc, cssRules) : null;
                  if (ancRule?.fontSizeScale != null) {
                    scale *= ancRule!.fontSizeScale!;
                  }
                }
                final addedH = lines * (fontSize * scale * lineHeight);
                currentHeight += addedH;
              }
            } else if (plainText.isNotEmpty &&
                currentBuffer.isNotEmpty &&
                !currentBuffer.toString().endsWith(' ')) {
              final isAdjoiningBlock = i < nodes.length &&
                  nodes[i] is dom.Element &&
                  _isBlockNode(nodes[i] as dom.Element);
              if (!isAdjoiningBlock) {
                currentBuffer.write(' ');
              }
            }
            runningCharOffset += plainText.length;
            continue;
          }

          // Measure and paginate the aggregated inline run as an anonymous block
          processBlockElement(anonBlock, isAnonymous: true);
          continue;
        }

        // Block element or replaced media element
        i++;
        if (node is dom.Element) {
          processBlockElement(node);
        }
      }
    }
    processNodes = doProcessNodes;

    processNodes(body.nodes);
    flushPage(isEndOfChapter: true);

    // Prevent 1-page short chapters from splitting into a tiny page-2 tail
    if (pages.length == 2 && pageHeights.length == 2) {
      final combinedHeight = pageHeights[0] + pageHeights[1];
      if (combinedHeight <= availableHeight * 0.98) {
        pages.clear();
        pages.add(
          PageSlice(
            html:
                '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>${body.innerHtml}</body></html>',
            startCharOffset: 0,
            endCharOffset: chapterPlainText.length,
            pageIndex: 0,
          ),
        );
      }
    }

    // Drop 90% blank footer pages with < 25 chars and no media, merging their content into the previous page
    if (pages.length > 1) {
      final lastSlice = pages.last;
      final lastDoc = html_parser.parse(lastSlice.html);
      final lastText = DomTextUtils.extractPlainText(lastDoc.body).trim();
      final hasMedia = lastDoc.body?.querySelector('img, svg, table, canvas, image') != null;
      if (!hasMedia && lastText.length < 25) {
        final prevSlice = pages[pages.length - 2];
        pages.removeLast();
        final lastBodyInner = lastDoc.body?.innerHtml ?? '';
        final mergedHtml = prevSlice.html.replaceFirst(
          '</body>',
          '$lastBodyInner</body>',
        );
        pages[pages.length - 1] = PageSlice(
          html: mergedHtml,
          startCharOffset: prevSlice.startCharOffset,
          endCharOffset: lastSlice.endCharOffset,
          pageIndex: prevSlice.pageIndex,
        );
      }
    }

    final result = pages.isNotEmpty
        ? pages
        : [
            PageSlice(
              html: chapterHtml,
              startCharOffset: 0,
              endCharOffset: chapterPlainText.length,
              pageIndex: 0,
            ),
          ];

    if (_cache.length >= 12) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = result;
    return result;
  }

  /// Distinguishes standard body paragraphs from non-narrative elements (headings, epigraphs, blockquotes, media).
  static void stampProseMarkers(dom.Element? body, Map<String, ResolvedCssRule> rules) {
    if (body == null) return;

    bool isNarrativeProse(dom.Element el) {
      final tag = el.localName?.toLowerCase() ?? '';
      if ({'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'table', 'blockquote', 'hr', 'img', 'svg'}.contains(tag)) {
        return false;
      }
      if (el.classes.contains('ceps') || el.classes.contains('ferrous-attribution')) return false;
      if (el.classes.contains('atx1') || el.classes.contains('ctag1') || el.classes.contains('ferrous-epigraph')) return false;
      if (el.classes.contains('cepiv') || el.classes.contains('ferrous-blockquote')) return false;

      final rule = CssRuleResolver.resolveRule(el, rules);
      if (rule != null) {
        if (rule.textAlign == 'right' || rule.textAlign == 'center') return false;
        if ((rule.marginLeft != null && rule.marginLeft! > 24) ||
            rule.isMarginLeftPercentage ||
            (rule.marginRight != null && rule.marginRight! > 24) ||
            rule.isMarginRightPercentage) {
          return false;
        }
      }

      if (tag == 'p') {
        final hasOnlyMedia = el.nodes.every((n) =>
            (n is dom.Element && {'img', 'svg', 'image', 'picture'}.contains(n.localName?.toLowerCase())) ||
            (n is dom.Text && n.text.trim().isEmpty));
        return !hasOnlyMedia;
      }

      if (tag == 'div' || tag == 'section') {
        final hasBlockChildren = el.children.any((c) {
          final cTag = c.localName?.toLowerCase() ?? '';
          return {'p', 'div', 'blockquote', 'table', 'ul', 'ol', 'section', 'article'}.contains(cTag);
        });
        if (hasBlockChildren) return false;

        final text = el.text.trim();
        if (text.isEmpty) return false;

        final hasOnlyMedia = el.nodes.every((n) =>
            (n is dom.Element && {'img', 'svg', 'image', 'picture'}.contains(n.localName?.toLowerCase())) ||
            (n is dom.Text && n.text.trim().isEmpty));
        return !hasOnlyMedia;
      }

      return false;
    }

    for (final el in body.querySelectorAll('p, div, section')) {
      if (isNarrativeProse(el)) {
        el.classes.add('ferrous-prose');
      }
    }
  }

  /// Public access for testing and DOM text extraction
  static String extractMeasurementText(dom.Node node, {bool isPre = false}) => _extractMeasurementText(node, isPre: isPre);
  static void normalizeBlockTextNodes(dom.Element element, {bool isPre = false}) => _normalizeBlockTextNodes(element, isPre: isPre);
  static String sliceNodeInnerHtmlForRange(
    dom.Element element,
    int startOffset,
    int endOffset, {
    bool isPre = false,
    int? rawTextLength,
  }) =>
      _sliceNodeInnerHtmlForRange(
        element,
        startOffset,
        endOffset,
        isPre: isPre,
        rawTextLength: rawTextLength,
      );

  /// Extracts measurement text: collapses \s+ to ' ' in dom.Text, preserves forced '\n' from <br>
  static String _extractMeasurementText(dom.Node node, {bool isPre = false}) {
    if (isPre) return node.text ?? '';
    final buffer = StringBuffer();
    void walk(dom.Node current) {
      if (current is dom.Text) {
        final collapsed = current.data.replaceAll(RegExp(r'\s+'), ' ');
        buffer.write(collapsed);
      } else if (current is dom.Element) {
        final tag = current.localName?.toLowerCase();
        if (tag == 'br') {
          buffer.write('\n');
        } else {
          for (final child in current.nodes) {
            walk(child);
          }
        }
      }
    }
    walk(node);
    return buffer.toString().replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n').trim();
  }

  /// Normalizes DOM text nodes in-place so DOM character offsets match
  /// `_extractMeasurementText` 1:1 without stripping inline element boundary spaces.
  static void _normalizeBlockTextNodes(dom.Element element, {bool isPre = false}) {
    if (isPre) return;
    final nodes = <dom.Node>[];

    void collect(dom.Node node) {
      if (node is dom.Text) {
        nodes.add(node);
      } else if (node is dom.Element) {
        final tag = node.localName?.toLowerCase();
        if (tag == 'br') {
          nodes.add(node);
        } else if (tag != 'pre' && tag != 'p-indent' && tag != 'indent') {
          for (final c in node.nodes) {
            collect(c);
          }
        }
      }
    }

    collect(element);
    final textNodes = nodes.whereType<dom.Text>().toList();
    if (textNodes.isEmpty) return;

    // 1. Collapse internal whitespace runs in each text node
    for (final t in textNodes) {
      t.data = t.data.replaceAll(RegExp(r'\s+'), ' ');
    }

    // 2. Strip leading whitespace across initial text nodes until first non-space char
    for (int i = 0; i < textNodes.length; i++) {
      final trimmed = textNodes[i].data.replaceFirst(RegExp(r'^\s+'), '');
      textNodes[i].data = trimmed;
      if (trimmed.isNotEmpty) break;
    }

    // 3. Strip trailing whitespace across final text nodes until last non-space char
    for (int i = textNodes.length - 1; i >= 0; i--) {
      final trimmed = textNodes[i].data.replaceFirst(RegExp(r'\s+$'), '');
      textNodes[i].data = trimmed;
      if (trimmed.isNotEmpty) break;
    }

    // 4. Deduplicate adjacent spaces across inline boundaries and strip spaces around <br>
    bool stripLeadingSpace = false;
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n is dom.Element) {
        // Current node is <br>: strip trailing space from nearest preceding non-empty text node
        for (int j = i - 1; j >= 0; j--) {
          final prev = nodes[j];
          if (prev is dom.Element) break;
          if (prev is dom.Text && prev.data.isNotEmpty) {
            prev.data = prev.data.replaceFirst(RegExp(r' +$'), '');
            break;
          }
        }
        stripLeadingSpace = true;
      } else if (n is dom.Text) {
        var data = n.data;
        if (data.isEmpty) continue;
        if (stripLeadingSpace && data.startsWith(' ')) {
          data = data.substring(1);
          n.data = data;
        }
        if (data.isNotEmpty) {
          stripLeadingSpace = data.endsWith(' ');
        }
      }
    }
  }

  /// Measures the exact character length of an inline or block node after
  /// `_normalizeBlockTextNodes` WITHOUT calling `.trim()`, preserving internal
  /// boundary spaces on inline elements like `<i>I </i>`.
  static int _measureNormalizedNodeLength(dom.Node node, {bool isPre = false}) {
    if (node is dom.Text) {
      return isPre ? node.data.length : node.data.replaceAll(RegExp(r'\s+'), ' ').length;
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'p-indent' || tag == 'indent' || tag == 'img' || tag == 'image' || tag == 'hr') {
        return 0;
      }
      if (tag == 'br') {
        return 1;
      }
      final childPre = isPre || tag == 'pre';
      int total = 0;
      for (final c in node.nodes) {
        total += _measureNormalizedNodeLength(c, isPre: childPre);
      }
      return total;
    }
    return 0;
  }

  /// Splits an oversized element into multiple continuous pieces across 2, 3, or more pages
  static List<_BlockPart> _splitBlockAcrossPages({
    required dom.Element node,
    required double firstBudget,
    required double maxPageHeight,
    required double singleLineHeight,
    required TextStyle textStyle,
    required TextAlign textAlign,
    required double effectiveBlockWidth,
    required bool hasIndent,
    required double indentWidth,
    required PlaceholderDimensions indentPlaceholder,
    required String primaryLang,
    required double effectiveTopMargin,
    required double effectiveBottomMargin,
    required double Function(String, bool, {required bool isFirstPart, required bool isLastPart}) measureText,
    bool isPre = false,
  }) {
    // Normalize text nodes first so DOM offsets and extractMeasurementText are 1:1
    normalizeBlockTextNodes(node, isPre: isPre);

    final rawText = extractMeasurementText(node, isPre: isPre);
    if (rawText.trim().isEmpty) {
      final len = DomTextUtils.extractPlainText(node).length;
      return [
        _BlockPart(
          html: node.outerHtml,
          height: measureText(rawText, true, isFirstPart: true, isLastPart: true),
          charLength: len,
        )
      ];
    }

    final tag = node.localName ?? 'p';
    final attrs = _serializeAttributes(node, stripId: false);
    final attrsNoIdOrClass = _serializeAttributes(node, stripId: true, stripClass: true);
    final existingClass = node.attributes['class'];
    final continuationClass = (existingClass != null && existingClass.trim().isNotEmpty)
        ? '${existingClass.trim()} page-continuation'
        : 'page-continuation';

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: TextScaler.noScaling,
      locale: Locale(primaryLang),
    );

    final parts = <_BlockPart>[];
    int currentOffset = 0;
    double currentBudget = firstBudget;
    bool isFirstPart = true;

    while (currentOffset < rawText.length) {
      final remainingText = rawText.substring(currentOffset);
      if (remainingText.trim().isEmpty) {
        break;
      }

      // 1. Check if all remaining text fits in currentBudget WITH bottom margin
      final remainingHeight = measureText(remainingText, isFirstPart, isFirstPart: isFirstPart, isLastPart: true);
      if (remainingHeight <= currentBudget) {
        final partInnerHtml = (currentOffset == 0)
            ? node.innerHtml
            : sliceNodeInnerHtmlForRange(
                node,
                currentOffset,
                rawText.length,
                isPre: isPre,
                rawTextLength: rawText.length,
              );
        final String partHtml = isFirstPart
            ? '<$tag$attrs>$partInnerHtml</$tag>'
            : '<$tag$attrsNoIdOrClass class="$continuationClass" style="text-indent: 0px !important; margin-top: 0px !important;">$partInnerHtml</$tag>';
        parts.add(_BlockPart(
          html: partHtml,
          height: remainingHeight,
          charLength: rawText.length - currentOffset,
        ));
        break;
      }

      // 2. Check if all remaining text fits WITHOUT bottom margin (Margin Collapse at Page Bottom)
      final heightTextOnly = measureText(remainingText, isFirstPart, isFirstPart: isFirstPart, isLastPart: false);
      if (heightTextOnly <= currentBudget) {
        final partInnerHtml = (currentOffset == 0)
            ? node.innerHtml
            : sliceNodeInnerHtmlForRange(
                node,
                currentOffset,
                rawText.length,
                isPre: isPre,
                rawTextLength: rawText.length,
              );
        final String partHtml = isFirstPart
            ? '<$tag$attrs style="margin-bottom: 0px !important;">$partInnerHtml</$tag>'
            : '<$tag$attrsNoIdOrClass class="$continuationClass" style="text-indent: 0px !important; margin-top: 0px !important; margin-bottom: 0px !important;">$partInnerHtml</$tag>';
        parts.add(_BlockPart(
          html: partHtml,
          height: heightTextOnly,
          charLength: rawText.length - currentOffset,
        ));
        break;
      }

      // 3. Layout remaining text with TextPainter to find how many full lines fit
      final bool applyIndentThisPart = isFirstPart && hasIndent && !isPre;
      textPainter.text = TextSpan(
        style: textStyle,
        children: [
          if (applyIndentThisPart)
            WidgetSpan(child: SizedBox(width: indentWidth, height: 1.0)),
          TextSpan(text: remainingText),
        ],
      );
      if (applyIndentThisPart) {
        textPainter.setPlaceholderDimensions([indentPlaceholder]);
      } else {
        textPainter.setPlaceholderDimensions(const []);
      }
      textPainter.layout(maxWidth: effectiveBlockWidth);
      final lineMetrics = textPainter.computeLineMetrics();

      if (lineMetrics.isEmpty) break;

      final topMarginDeduction = isFirstPart ? effectiveTopMargin : 0.0;
      final usableLineBudget = currentBudget - topMarginDeduction;

      int fittingLines = 0;
      double accumHeight = 0.0;
      for (int i = 0; i < lineMetrics.length; i++) {
        final lh = lineMetrics[i].height;
        if (accumHeight + lh <= usableLineBudget + 0.5) {
          accumHeight += lh;
          fittingLines++;
        } else {
          break;
        }
      }

      if (fittingLines == 0) {
        if (isFirstPart && currentBudget < maxPageHeight) {
          return const []; // Signal to flush page and retry with full budget
        }
        fittingLines = 1; // Force at least 1 line to make progress at top of page
      }

      // 4. Orphan & Widow Protection: pull back WHOLE LINES, never words!
      final remainingLines = lineMetrics.length - fittingLines;
      if (remainingLines == 1 && lineMetrics.length > 2) {
        if (fittingLines >= 2) {
          fittingLines--;
        } else if (isFirstPart && currentBudget < maxPageHeight) {
          return const []; // Signal to flush page
        }
      }

      final lastLineIdx = fittingLines - 1;
      final lm = lineMetrics[lastLineIdx];
      double lineY = 0.0;
      for (int i = 0; i < lastLineIdx; i++) {
        lineY += lineMetrics[i].height;
      }
      lineY += lm.height / 2.0;

      final posStart = textPainter.getPositionForOffset(Offset(0.0, lineY));
      final posEnd = textPainter.getPositionForOffset(Offset(effectiveBlockWidth - 1.0, lineY));
      final startRange = textPainter.getLineBoundary(posStart);
      final endRange = textPainter.getLineBoundary(posEnd);

      int splitLength = endRange.end;
      if (splitLength <= 0) splitLength = remainingText.length;
      if (splitLength > remainingText.length) splitLength = remainingText.length;

      final lineStartInRemaining = startRange.start.clamp(0, splitLength);

      // Verify that candidate slice does not split an unhyphenated word
      if (splitLength < remainingText.length && splitLength > lineStartInRemaining) {
        final prevChar = remainingText[splitLength - 1];
        final nextChar = remainingText[splitLength];
        final isWordChar = RegExp(r'[\w\u00C0-\u024F]');
        if (isWordChar.hasMatch(prevChar) && isWordChar.hasMatch(nextChar)) {
          // Mid-word cut! Retreat to start of word unless the word exceeds the entire line
          final wb = textPainter.getWordBoundary(TextPosition(offset: splitLength - 1));
          if (wb.start > lineStartInRemaining) {
            splitLength = wb.start;
          }
        }
      }

      // Defensively verify with a layout probe of candidateSlice that it does NOT wrap an extra line
      while (splitLength > lineStartInRemaining) {
        final candidateSlice = remainingText.substring(0, splitLength);
        final tpVerify = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: TextScaler.noScaling,
          locale: Locale(primaryLang),
        );
        tpVerify.text = TextSpan(
          style: textStyle,
          children: [
            if (applyIndentThisPart)
              WidgetSpan(child: SizedBox(width: indentWidth, height: 1.0)),
            TextSpan(text: candidateSlice),
          ],
        );
        if (applyIndentThisPart) {
          tpVerify.setPlaceholderDimensions([indentPlaceholder]);
        }
        tpVerify.layout(maxWidth: effectiveBlockWidth);
        if (tpVerify.computeLineMetrics().length <= fittingLines) {
          break; // Confirmed: fits within allocated line count
        }
        // Exceeded fittingLines: retreat to previous word boundary
        final wb = textPainter.getWordBoundary(TextPosition(offset: splitLength - 1));
        if (wb.start < splitLength && wb.start > lineStartInRemaining) {
          splitLength = wb.start;
        } else {
          splitLength--;
        }
      }

      // 5. Expand final split line to 100% width when justified
      double? neededWs;
      if (textAlign == TextAlign.justify && splitLength < remainingText.length) {
        final lineStr = remainingText.substring(lineStartInRemaining, splitLength).trim();
        final tpSingle = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        tpSingle.text = TextSpan(text: lineStr, style: textStyle);
        tpSingle.layout(maxWidth: effectiveBlockWidth);
        final unexpandedWidth = tpSingle.width;
        final delta = effectiveBlockWidth - unexpandedWidth;
        final spaceCount = ' '.allMatches(lineStr).length;
        if (spaceCount > 0 && delta > 2.0) {
          final safeDelta = delta - 2.0;
          neededWs = (safeDelta / spaceCount).clamp(0.0, 30.0);
        }
      }

      final chunkEndOffset = currentOffset + splitLength;
      final String partInnerHtml;
      if (neededWs != null && neededWs > 0 && lineStartInRemaining > 0) {
        final headSlice = sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          currentOffset + lineStartInRemaining,
          isPre: isPre,
          rawTextLength: rawText.length,
        );
        final tailSlice = sliceNodeInnerHtmlForRange(
          node,
          currentOffset + lineStartInRemaining,
          chunkEndOffset,
          isPre: isPre,
          rawTextLength: rawText.length,
        );
        partInnerHtml = '$headSlice<page-split-tail data-word-spacing="${neededWs.toStringAsFixed(2)}">$tailSlice</page-split-tail>';
      } else if (neededWs != null && neededWs > 0) {
        final tailSlice = sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          chunkEndOffset,
          isPre: isPre,
          rawTextLength: rawText.length,
        );
        partInnerHtml = '<page-split-tail data-word-spacing="${neededWs.toStringAsFixed(2)}">$tailSlice</page-split-tail>';
      } else {
        partInnerHtml = sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          chunkEndOffset,
          isPre: isPre,
          rawTextLength: rawText.length,
        );
      }

      final String partHtml;
      final attrsNoClass = _serializeAttributes(node, stripId: false, stripClass: true);
      final combinedClass = (existingClass != null && existingClass.trim().isNotEmpty)
          ? '${existingClass.trim()} ferrous-prose-split-tail'
          : 'ferrous-prose-split-tail';

      if (isFirstPart) {
        partHtml = '<$tag$attrsNoClass class="$combinedClass" style="margin-bottom: 0px !important;">$partInnerHtml</$tag>';
      } else {
        partHtml =
            '<$tag$attrsNoIdOrClass class="$continuationClass ferrous-prose-split-tail" style="text-indent: 0px !important; margin-top: 0px !important; margin-bottom: 0px !important;">$partInnerHtml</$tag>';
      }

      double chunkHeight = topMarginDeduction;
      for (int i = 0; i < fittingLines; i++) {
        chunkHeight += lineMetrics[i].height;
      }

      parts.add(_BlockPart(
        html: partHtml,
        height: chunkHeight,
        charLength: splitLength,
      ));

      currentOffset = chunkEndOffset;
      isFirstPart = false;
      currentBudget = maxPageHeight;
    }

    return parts.isNotEmpty
        ? parts
        : [
            _BlockPart(
              html: node.outerHtml,
              height: measureText(rawText, true, isFirstPart: true, isLastPart: true),
              charLength: DomTextUtils.extractPlainText(node).length,
            ),
          ];
  }

  /// Slices child DOM tree matching the exact character range [startOffset, endOffset),
  /// preserving inline tags (`<i>`, `<b>`, `<a>`, `<annotation-highlight>`), `<p-indent>`, and void elements.
  static String _sliceNodeInnerHtmlForRange(
    dom.Element element,
    int startOffset,
    int endOffset, {
    bool isPre = false,
    int? rawTextLength,
  }) {
    if (startOffset >= endOffset) return '';
    if (element.nodes.isEmpty) return '';

    final totalLen = rawTextLength ?? _measureNormalizedNodeLength(element, isPre: isPre);
    final bool isTerminalSlice = endOffset >= totalLen || endOffset >= (1 << 29);
    if (startOffset == 0 && isTerminalSlice) {
      return element.innerHtml;
    }

    final buffer = StringBuffer();
    int nodeStart = 0;

    for (final child in element.nodes) {
      if (child is dom.Text) {
        final text = isPre ? child.data : child.data.replaceAll(RegExp(r'\s+'), ' ');
        final int nodeLen = text.length;
        final int nodeEnd = nodeStart + nodeLen;

        if (nodeEnd <= startOffset) {
          nodeStart = nodeEnd;
          continue;
        }
        if (!isTerminalSlice && nodeStart >= endOffset) {
          break;
        }

        final localStart = (startOffset - nodeStart).clamp(0, nodeLen);
        final localEnd = isTerminalSlice
            ? nodeLen
            : (endOffset - nodeStart).clamp(localStart, nodeLen);

        var textSlice = text.substring(localStart, localEnd);

        // Bi-directional affinity check at soft-hyphen slice points:
        final brokeAtSoftHyphen = textSlice.endsWith('\u00AD') ||
            (localEnd < nodeLen && text.startsWith('\u00AD', localEnd));
        if (brokeAtSoftHyphen) {
          if (textSlice.endsWith('\u00AD')) {
            textSlice = '${textSlice.substring(0, textSlice.length - 1)}\u2010';
          } else {
            textSlice = '$textSlice\u2010';
          }
        }
        if (localStart > 0 && text.startsWith('\u00AD', localStart - 1) && textSlice.startsWith('\u00AD')) {
          textSlice = textSlice.substring(1);
        } else if (localStart == 0 && textSlice.startsWith('\u00AD')) {
          textSlice = textSlice.substring(1);
        }

        buffer.write(const HtmlEscape().convert(textSlice));
        nodeStart = nodeEnd;
      } else if (child is dom.Element) {
        final childTag = child.localName?.toLowerCase() ?? 'span';

        // Custom first-line indent element: emit on Part 1 (startOffset == 0), omit on continuations
        if (childTag == 'p-indent' || childTag == 'indent') {
          if (startOffset == 0) {
            buffer.write(child.outerHtml);
          }
          continue;
        }

        // Void elements: <br> emits only within slice boundary
        if (childTag == 'br') {
          if (nodeStart >= startOffset && nodeStart < endOffset) {
            buffer.write('<br/>');
          }
          nodeStart += 1;
          continue;
        }

        // Void elements: <img>, <hr>
        if (childTag == 'img' || childTag == 'image' || childTag == 'hr') {
          if (nodeStart >= startOffset && nodeStart < endOffset) {
            buffer.write(child.outerHtml);
          }
          continue;
        }

        final childIsPre = isPre || childTag == 'pre';
        final int nodeLen = _measureNormalizedNodeLength(child, isPre: childIsPre);
        final int nodeEnd = nodeStart + nodeLen;

        if (nodeEnd <= startOffset) {
          nodeStart = nodeEnd;
          continue;
        }
        if (!isTerminalSlice && nodeStart >= endOffset) {
          break;
        }

        final localStart = (startOffset - nodeStart).clamp(0, nodeLen);
        final localEnd = isTerminalSlice
            ? nodeLen
            : (endOffset - nodeStart).clamp(localStart, nodeLen);

        final childAttrs = _serializeAttributes(child, stripId: false);
        final innerSlice = _sliceNodeInnerHtmlForRange(
          child,
          localStart,
          isTerminalSlice ? (1 << 30) : localEnd,
          isPre: childIsPre,
          rawTextLength: nodeLen,
        );
        buffer.write('<$childTag$childAttrs>$innerSlice</$childTag>');

        nodeStart = nodeEnd;
      }
    }

    return buffer.toString();
  }

  static TextAlign _parseTextAlign(String align) {
    switch (align.toLowerCase().trim()) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.left;
    }
  }

  static String _serializeAttributes(
    dom.Element el, {
    required bool stripId,
    bool stripClass = false,
  }) {
    if (el.attributes.isEmpty) return '';
    final parts = <String>[];
    el.attributes.forEach((key, value) {
      final k = key.toString().toLowerCase();
      if (stripId && k == 'id') return;
      if (stripClass && k == 'class') return;
      final escapedVal = const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
      parts.add('$key="$escapedVal"');
    });
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }
}

class _BlockPart {
  final String html;
  final double height;
  final int charLength;

  const _BlockPart({
    required this.html,
    required this.height,
    required this.charLength,
  });
}
