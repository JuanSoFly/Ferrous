import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:ferrous/core/models/annotation.dart';
import 'package:ferrous/core/utils/dom_text_utils.dart';
import 'package:ferrous/core/utils/reader_typography_metrics.dart';
import 'package:ferrous/features/reader/annotation_highlight_helper.dart';
import 'package:ferrous/features/reader/hyphenation_helper.dart';
import 'package:ferrous/core/utils/xml_html_normalizer.dart';

/// Represents a single screen-fitted slice of an EPUB/MOBI chapter.
class PageSlice {
  final String html;
  final int startCharOffset;
  final int endCharOffset;
  final int pageIndex;

  const PageSlice({
    required this.html,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.pageIndex,
  });

  @override
  String toString() =>
      'PageSlice(pageIndex: $pageIndex, range: [$startCharOffset..$endCharOffset], htmlLen: ${html.length})';
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
    final cacheKey =
        '$bookId:$chapterIndex:${availableWidth.toInt()}x${availableHeight.toInt()}:'
        '${fontSize.toStringAsFixed(1)}:${lineHeight.toStringAsFixed(2)}:'
        '${paragraphSpacing.toStringAsFixed(1)}:${fontFamily ?? "default"}:'
        '${textAlign.name}:${fontWeight.value}:${wordSpacing.toStringAsFixed(2)}:'
        '$paragraphIndent:$hyphenation:$primaryLang:${textScale.toStringAsFixed(2)}:$annotationSig';

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

    final headHtml =
        document.head?.outerHtml ?? '<head><meta charset="utf-8"></head>';
    final bodyAttrs = _serializeAttributes(body, stripId: false);

    // Dynamic canvas bounds: guarantee at least one full line block and guard clamp
    final singleLineHeight = fontSize * lineHeight;
    final minOneLineBlock = singleLineHeight + paragraphSpacing + 2.0;
    final rawMaxHeight = math.max(
      availableHeight - singleLineHeight,
      minOneLineBlock,
    );
    final lowerBound = math.min(100.0, availableHeight);
    final double maxPageHeight = rawMaxHeight
        .clamp(lowerBound, math.max(availableHeight, minOneLineBlock))
        .toDouble();

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

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: textScaler,
      locale: Locale(primaryLang),
      strutStyle: StrutStyle(
        fontFamily: baseStyle.fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        forceStrutHeight: false,
      ),
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
    }) {
      final sanitized = text.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').trim();
      final normalized = isPre
          ? text
          : (hyphenation ? sanitized : HyphenationHelper.stripSoftHyphens(sanitized));
      if (normalized.isEmpty) {
        return (fontSize * fontScale * lineHeight) + extraTopMargin + extraBottomMargin;
      }

      final effectiveStyle = isHeading
          ? baseStyle.copyWith(
              fontSize: fontSize * fontScale,
              fontWeight: FontWeight.bold,
            )
          : (fontScale == 1.0
              ? baseStyle
              : baseStyle.copyWith(fontSize: fontSize * fontScale));

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

      textPainter.layout(maxWidth: availableWidth);
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

      final sliceHtml =
          '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>$wellFormedFragmentHtml</body></html>';
      pageHeights.add(currentHeight);
      pages.add(
        PageSlice(
          html: sliceHtml,
          startCharOffset: pageStartCharOffset,
          endCharOffset: runningCharOffset,
          pageIndex: pages.length,
        ),
      );
      currentBuffer.clear();
      currentHeight = 0.0;
      pageStartCharOffset = runningCharOffset;

      // Re-open active ancestors for next page slice
      for (final el in openAncestors) {
        final tag = el.localName ?? 'div';
        final attrs = _serializeAttributes(el, stripId: true);
        currentBuffer.write('<$tag$attrs style="margin-top: 0px; padding-top: 0px;">');
      }
    }

    late final void Function(List<dom.Node>) processNodes;

    void processBlockElement(dom.Element node, {bool isAnonymous = false}) {
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

        final containerAttrs = _serializeAttributes(node, stripId: false);
        currentBuffer.write('<$tag$containerAttrs>');
        openAncestors.add(node);

        processNodes(node.nodes);

        if (openAncestors.isNotEmpty && openAncestors.last == node) {
          openAncestors.removeLast();
          currentBuffer.write('</$tag>');
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
        );
        targetElement = cloned;
      } else {
        targetElement = node;
      }

      final nodeText = _extractMeasurementText(targetElement, isPre: tag == 'pre');
      final textLen = DomTextUtils.extractPlainText(targetElement, preserveSoftHyphens: true).length;

      final double blockHeight;
      if (hasImage) {
        blockHeight = maxPageHeight * 0.72;
      } else if (isHeading) {
        final scale = ReaderTypographyMetrics.headingScale(tag);
        final topMargin = ReaderTypographyMetrics.headingTopMargin(tag, true, fontSize);
        final bottomMargin = ReaderTypographyMetrics.headingBottomMargin(tag, true, paragraphSpacing);
        blockHeight = measureTextHeight(
          nodeText,
          fontScale: scale,
          isIndent: false,
          extraTopMargin: topMargin,
          extraBottomMargin: bottomMargin,
          isHeading: true,
        );
      } else {
        blockHeight = measureTextHeight(
          nodeText,
          fontScale: 1.0,
          isIndent: !isAnonymous && paragraphIndent && tag == 'p',
          extraTopMargin: 0.0,
          extraBottomMargin: paragraphSpacing,
          isPre: tag == 'pre',
          isHeading: false,
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
      final canSplit = (tag == 'p' || tag == 'blockquote' || tag == 'div') && !hasImage;

      if (canSplit) {
        final double singleLineHeight = fontSize * lineHeight;
        final double minRemainingSpace = singleLineHeight * 2.0;
        double remainingHeight = maxPageHeight - currentHeight;

        // If remaining space on current page is too small (< 2 lines), start fresh on next page
        if (currentHeight > 0 && remainingHeight < minRemainingSpace) {
          flushPage();
          remainingHeight = maxPageHeight;
        }

        var splitParts = _splitBlockAcrossPages(
          node: targetElement,
          firstBudget: remainingHeight,
          maxPageHeight: maxPageHeight,
          singleLineHeight: singleLineHeight,
          measureText: (txt, isIndent, {required bool isLastPart}) => measureTextHeight(
            txt,
            isIndent: isIndent && paragraphIndent && !isAnonymous,
            extraBottomMargin: isLastPart ? paragraphSpacing : 0.0,
            isPre: tag == 'pre',
            isHeading: false,
          ),
          isPre: tag == 'pre',
        );

        if (splitParts.isEmpty && currentHeight > 0) {
          flushPage();
          splitParts = _splitBlockAcrossPages(
            node: targetElement,
            firstBudget: maxPageHeight,
            maxPageHeight: maxPageHeight,
            singleLineHeight: singleLineHeight,
            measureText: (txt, isIndent, {required bool isLastPart}) => measureTextHeight(
              txt,
              isIndent: isIndent && paragraphIndent && !isAnonymous,
              extraBottomMargin: isLastPart ? paragraphSpacing : 0.0,
              isPre: tag == 'pre',
              isHeading: false,
            ),
            isPre: tag == 'pre',
          );
        }

        for (int partIdx = 0; partIdx < splitParts.length; partIdx++) {
          final part = splitParts[partIdx];
          if (currentHeight + part.height > maxPageHeight && currentHeight > 0) {
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
                currentHeight += brCount * singleLineHeight;
              }
            } else if (plainText.isNotEmpty &&
                currentBuffer.isNotEmpty &&
                !currentBuffer.toString().endsWith(' ')) {
              currentBuffer.write(' ');
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

  /// Finds the largest word boundary index < [currentBestIndex] that leaves at least
  /// [minRemainderHeight] of text for the next page.
  static int _findSplitPointLeavingAtLeastTwoLines(
    List<int> wordBoundaries,
    int currentBestIndex,
    String remainingText,
    double minRemainderHeight,
    double Function(String, bool, {required bool isLastPart}) measureText,
  ) {
    int candidate = currentBestIndex;
    while (candidate > 0) {
      candidate--;
      final splitPos = wordBoundaries[candidate];
      final tail = remainingText.substring(splitPos).trim();
      if (tail.isEmpty) continue;
      final tailHeight = measureText(tail, false, isLastPart: false);
      if (tailHeight >= minRemainderHeight) {
        return candidate;
      }
    }
    return currentBestIndex;
  }

  /// Splits an oversized element into multiple continuous pieces across 2, 3, or more pages
  static List<_BlockPart> _splitBlockAcrossPages({
    required dom.Element node,
    required double firstBudget,
    required double maxPageHeight,
    required double singleLineHeight,
    required double Function(String, bool, {required bool isLastPart}) measureText,
    bool isPre = false,
  }) {
    // Normalize text nodes first so DOM offsets and _extractMeasurementText are 1:1
    _normalizeBlockTextNodes(node, isPre: isPre);

    final rawText = _extractMeasurementText(node, isPre: isPre);
    if (rawText.trim().isEmpty) {
      final len = DomTextUtils.extractPlainText(node).length;
      return [
        _BlockPart(
          html: node.outerHtml,
          height: measureText(rawText, true, isLastPart: true),
          charLength: len,
        )
      ];
    }

    final tag = node.localName ?? 'p';
    final attrs = _serializeAttributes(node, stripId: false);
    final attrsNoId = _serializeAttributes(node, stripId: true);

    final parts = <_BlockPart>[];
    int currentOffset = 0;
    double currentBudget = firstBudget;
    bool isFirstPart = true;

    while (currentOffset < rawText.length) {
      final remainingText = rawText.substring(currentOffset);
      if (remainingText.trim().isEmpty) {
        break;
      }

      // 1. Check if all remaining text fits in currentBudget WITH bottom paragraphSpacing
      final remainingHeight = measureText(remainingText, isFirstPart, isLastPart: true);
      if (remainingHeight <= currentBudget) {
        final partInnerHtml = (currentOffset == 0)
            ? node.innerHtml
            : _sliceNodeInnerHtmlForRange(
                node,
                currentOffset,
                rawText.length,
                isPre: isPre,
                rawTextLength: rawText.length,
              );
        final String partHtml = isFirstPart
            ? '<$tag$attrs>$partInnerHtml</$tag>'
            : '<$tag$attrsNoId class="page-continuation" style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
        final int charLength = (rawText.length - currentOffset) + 1;
        parts.add(_BlockPart(
          html: partHtml,
          height: remainingHeight,
          charLength: charLength,
        ));
        break;
      }

      // 2. Check if all remaining text fits WITHOUT bottom paragraphSpacing (Margin Collapse at Page Bottom)
      final heightTextOnly = measureText(remainingText, isFirstPart, isLastPart: false);
      if (heightTextOnly <= currentBudget) {
        final partInnerHtml = (currentOffset == 0)
            ? node.innerHtml
            : _sliceNodeInnerHtmlForRange(
                node,
                currentOffset,
                rawText.length,
                isPre: isPre,
                rawTextLength: rawText.length,
              );
        final String partHtml = isFirstPart
            ? '<$tag$attrs>$partInnerHtml</$tag>'
            : '<$tag$attrsNoId class="page-continuation" style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
        final int charLength = (rawText.length - currentOffset) + 1;
        parts.add(_BlockPart(
          html: partHtml,
          // Consume full currentBudget so the page flushes before the next block
          height: math.max(heightTextOnly, currentBudget),
          charLength: charLength,
        ));
        break;
      }

      // 3. Remaining text exceeds currentBudget. Find word boundaries in remainingText
      final wordBoundaries = <int>[];
      final splitRegex = RegExp(r'\s+|\u00AD');
      for (final m in splitRegex.allMatches(remainingText)) {
        if (m.end > 0 && m.end < remainingText.length) {
          wordBoundaries.add(m.end);
        }
      }
      wordBoundaries.add(remainingText.length);

      // Binary search for the maximum word boundary that fits within currentBudget
      int low = 0;
      int high = wordBoundaries.length - 1;
      int bestIndex = -1;

      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final splitPoint = wordBoundaries[mid];
        final candidateText = remainingText.substring(0, splitPoint);
        final candidateHeight = measureText(candidateText, isFirstPart, isLastPart: false);

        if (candidateHeight <= currentBudget) {
          bestIndex = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      // Prefer clean sentence boundary if one exists within 2 words before bestIndex
      if (bestIndex > 0 && bestIndex < wordBoundaries.length - 1) {
        final sentencePunct = RegExp(r'[.!?]["”’\)]*\s*$');
        for (int back = 1; back <= 2 && (bestIndex - back) >= 0; back++) {
          final candidateSub = remainingText.substring(0, wordBoundaries[bestIndex - back]);
          if (sentencePunct.hasMatch(candidateSub.trimRight())) {
            bestIndex = bestIndex - back;
            break;
          }
        }
      }

      if (bestIndex == -1) {
        if (isFirstPart && currentBudget < maxPageHeight) {
          return const []; // Signal to flush page and retry with full budget
        }
        bestIndex = 0; // At full page height, force taking first word to make progress
      }

      int splitLength = wordBoundaries[bestIndex];

      // 4. Widow & Orphan Protection
      final remainder = remainingText.substring(splitLength).trim();
      final remainderTextHeight = remainder.isEmpty
          ? 0.0
          : measureText(remainder, false, isLastPart: false);

      if (remainder.isNotEmpty && remainderTextHeight < (singleLineHeight * 1.5)) {
        if (bestIndex > 1) {
          final pulledBackIndex = _findSplitPointLeavingAtLeastTwoLines(
            wordBoundaries,
            bestIndex,
            remainingText,
            singleLineHeight * 1.6,
            measureText,
          );
          final pulledBackLength = wordBoundaries[pulledBackIndex];
          final pulledBackText = remainingText.substring(0, pulledBackLength).trim();
          final pulledBackHeight = measureText(pulledBackText, isFirstPart, isLastPart: false);

          // Ensure pulling back still leaves at least 2 lines on the current page
          if (pulledBackHeight >= singleLineHeight * 1.5) {
            bestIndex = pulledBackIndex;
            splitLength = pulledBackLength;
          } else if (isFirstPart && currentBudget < maxPageHeight) {
            // Pulling back would leave a 1-line orphan; flush and start fresh on next page
            return const [];
          }
        } else if (isFirstPart && currentBudget < maxPageHeight) {
          return const [];
        }
      }

      final chunkText = remainingText.substring(0, splitLength);
      final chunkHeight = measureText(chunkText, isFirstPart, isLastPart: false);
      final chunkEndOffset = currentOffset + splitLength;

      final partInnerHtml = _sliceNodeInnerHtmlForRange(
        node,
        currentOffset,
        chunkEndOffset,
        isPre: isPre,
        rawTextLength: rawText.length,
      );

      final String partHtml;
      if (isFirstPart) {
        partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
      } else {
        partHtml =
            '<$tag$attrsNoId class="page-continuation" style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
      }

      parts.add(_BlockPart(
        html: partHtml,
        // Consume currentBudget on non-final parts so next part always flushes to next page
        height: chunkEndOffset < rawText.length
            ? math.max(chunkHeight, currentBudget)
            : chunkHeight,
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
              height: measureText(rawText, true, isLastPart: true),
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
    if (startOffset == 0 && endOffset >= totalLen) {
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
        if (nodeStart >= endOffset) {
          break;
        }

        final localStart = (startOffset - nodeStart).clamp(0, nodeLen);
        final localEnd = (endOffset >= totalLen && nodeEnd >= endOffset)
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
        if (nodeStart >= endOffset) {
          break;
        }

        final localStart = (startOffset - nodeStart).clamp(0, nodeLen);
        final localEnd = (endOffset >= totalLen && nodeEnd >= endOffset)
            ? nodeLen
            : (endOffset - nodeStart).clamp(localStart, nodeLen);

        final childAttrs = _serializeAttributes(child, stripId: false);
        final innerSlice = _sliceNodeInnerHtmlForRange(
          child,
          localStart,
          localEnd,
          isPre: childIsPre,
          rawTextLength: nodeLen,
        );
        buffer.write('<$childTag$childAttrs>$innerSlice</$childTag>');

        nodeStart = nodeEnd;
      }
    }

    return buffer.toString();
  }

  static String _serializeAttributes(dom.Element el, {required bool stripId}) {
    if (el.attributes.isEmpty) return '';
    final parts = <String>[];
    el.attributes.forEach((key, value) {
      if (stripId && key.toString().toLowerCase() == 'id') return;
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
