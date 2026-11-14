import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/features/reader/annotation_highlight_helper.dart';

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

  static void clearCache() {
    _cache.clear();
  }

  static void invalidateBook(String bookId) {
    _cache.removeWhere((key, _) => key.startsWith('$bookId:'));
  }

  /// Paginates a chapter into screen-fitted
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

    final textScale = textScaler.scale(10.0) / 10.0;
    final cacheKey =
        '$bookId:$chapterIndex:${availableWidth.toInt()}x${availableHeight.toInt()}:'
        '${fontSize.toStringAsFixed(1)}:${lineHeight.toStringAsFixed(2)}:'
        '${fontFamily ?? "default"}:$paragraphIndent:$hyphenation:${textScale.toStringAsFixed(2)}:$annotationSig';

    final cached = _cache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // Step 1: Pre-process chapter HTML with annotation highlights BEFORE pagination
    final processedHtml = annotations.isNotEmpty
        ? AnnotationHighlightHelper.applyHighlights(chapterHtml, annotations)
        : chapterHtml;

    final document = html_parser.parse(processedHtml);
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

    // 0.5-line safety ceiling now that whitespace is normalized and margins are locked
    final safetyCeiling = fontSize * lineHeight * 0.5;
    final maxPageHeight =
        (availableHeight - safetyCeiling).clamp(100.0, availableHeight);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: textScaler,
      strutStyle: StrutStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        forceStrutHeight: false,
      ),
    );

    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeight,
      letterSpacing: wordSpacing,
      fontWeight: fontWeight,
    );

    double measureTextHeight(
      String text, {
      double fontScale = 1.0,
      bool isIndent = false,
      double extraBottomMargin = 0.0,
      bool isPre = false,
    }) {
      final normalized = isPre ? text : text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty) return fontSize * lineHeight + extraBottomMargin;

      final measurementText = isIndent ? '\u2003\u2003$normalized' : normalized;
      textPainter.text = TextSpan(
        text: measurementText,
        style: fontScale == 1.0
            ? baseStyle
            : baseStyle.copyWith(fontSize: fontSize * fontScale),
      );
      textPainter.layout(maxWidth: availableWidth);
      return textPainter.height + paragraphSpacing + extraBottomMargin;
    }

    final pages = <PageSlice>[];
    final pageHeights = <double>[];
    final currentBuffer = StringBuffer();
    double currentHeight = 0.0;
    int runningCharOffset = 0;
    int pageStartCharOffset = 0;

    void flushPage() {
      if (currentBuffer.isEmpty) return;
      final pageIndex = pages.length;
      pageHeights.add(currentHeight);
      pages.add(
        PageSlice(
          html:
              '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>${currentBuffer.toString()}</body></html>',
          startCharOffset: pageStartCharOffset,
          endCharOffset: runningCharOffset,
          pageIndex: pageIndex,
        ),
      );
      currentBuffer.clear();
      currentHeight = 0.0;
      pageStartCharOffset = runningCharOffset;
    }

    void processNodes(List<dom.Node> nodes, List<dom.Element> ancestors) {
      for (int i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        if (node is dom.Element) {
          final tag = node.localName?.toLowerCase() ?? '';

          // Unwrap container divs/sections/articles if they contain multiple block children
          if ((tag == 'div' || tag == 'section' || tag == 'article') &&
              node.children.length > 1) {
            final id = (node.attributes['id'] ?? '').trim();
            if (id.isNotEmpty) {
              final escapedId =
                  const HtmlEscape(HtmlEscapeMode.attribute).convert(id);
              currentBuffer.write('<span id="$escapedId"></span>');
            }
            processNodes(node.nodes, [...ancestors, node]);
            continue;
          }

          final nodePlainText = DomTextUtils.extractPlainText(node);
          final textLen = nodePlainText.length;
          final isHeading =
              {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag);
          final hasImage = tag == 'img' ||
              tag == 'svg' ||
              tag == 'image' ||
              node.querySelector('img, svg, image') != null;

          final double blockHeight = hasImage
              ? (maxPageHeight * 0.72)
              : measureTextHeight(
                  node.text,
                  fontScale: isHeading ? 1.35 : 1.0,
                  isIndent: paragraphIndent && tag == 'p',
                  extraBottomMargin: 0.0,
                  isPre: tag == 'pre',
                );

          // Keep headings attached to at least 2 lines of text
          if (isHeading &&
              currentHeight > 0 &&
              (currentHeight + blockHeight + (fontSize * lineHeight * 2.0)) >
                  maxPageHeight) {
            flushPage();
          }

          // Standalone image handling
          if (hasImage) {
            if (currentHeight > 0 && (currentHeight + blockHeight) > maxPageHeight) {
              flushPage();
            }
            currentBuffer.write(_wrapWithAncestors(node.outerHtml, ancestors));
            currentHeight += blockHeight;
            runningCharOffset += textLen;
            if (blockHeight >= maxPageHeight * 0.6) {
              flushPage();
            }
            continue;
          }

          // If block fits on current page, append directly
          if (currentHeight + blockHeight <= maxPageHeight) {
            currentBuffer.write(_wrapWithAncestors(node.outerHtml, ancestors));
            currentHeight += blockHeight;
            runningCharOffset += textLen;
            continue;
          }

          // Multi-page paragraph/block splitting without arbitrary length gates
          final canSplit = (tag == 'p' || tag == 'blockquote' || tag == 'div') &&
              !hasImage;

          if (canSplit) {
            final double minRemainingSpace = fontSize * lineHeight * 2.0;
            double remainingHeight = maxPageHeight - currentHeight;

            // If remaining space on current page is too small (< 2 lines), start fresh on next page
            if (currentHeight > 0 && remainingHeight < minRemainingSpace) {
              flushPage();
              remainingHeight = maxPageHeight;
            }

            // Perform non-destructive multi-page splitting
            var splitParts = _splitBlockAcrossPages(
              node: node,
              firstBudget: remainingHeight,
              maxPageHeight: maxPageHeight,
              measureText: (txt, isIndent) => measureTextHeight(
                txt,
                isIndent: isIndent && paragraphIndent,
                isPre: tag == 'pre',
              ),
            );

            if (splitParts.isEmpty && currentBuffer.isNotEmpty) {
              flushPage();
              splitParts = _splitBlockAcrossPages(
                node: node,
                firstBudget: maxPageHeight,
                maxPageHeight: maxPageHeight,
                measureText: (txt, isIndent) => measureTextHeight(
                  txt,
                  isIndent: isIndent && paragraphIndent,
                  isPre: tag == 'pre',
                ),
              );
            }

            for (int partIdx = 0; partIdx < splitParts.length; partIdx++) {
              final part = splitParts[partIdx];
              if (currentHeight + part.height > maxPageHeight &&
                  currentBuffer.isNotEmpty) {
                flushPage();
              }
              currentBuffer.write(_wrapWithAncestors(part.html, ancestors));
              currentHeight += part.height;
              runningCharOffset += part.charLength;
            }
            continue;
          }

          // Standard atomic block doesn't fit on current page -> flush and start new page
          if (currentBuffer.isNotEmpty) {
            flushPage();
          }
          currentBuffer.write(_wrapWithAncestors(node.outerHtml, ancestors));
          currentHeight += blockHeight;
          runningCharOffset += textLen;
        } else if (node is dom.Text && node.text.trim().isNotEmpty) {
          final escaped = const HtmlEscape().convert(node.text);
          currentBuffer.write(_wrapWithAncestors(escaped, ancestors));
          runningCharOffset += node.text.length;
        }
      }
    }

    processNodes(body.nodes, const []);
    flushPage();

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

  /// Splits an oversized element into multiple continuous pieces across 2, 3, or more pages
  static List<_BlockPart> _splitBlockAcrossPages({
    required dom.Element node,
    required double firstBudget,
    required double maxPageHeight,
    required double Function(String, bool) measureText,
  }) {
    final rawText = node.text;
    if (rawText.trim().isEmpty) {
      final len = DomTextUtils.extractPlainText(node).length;
      return [_BlockPart(html: node.outerHtml, height: measureText(rawText, true), charLength: len)];
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

      // Check if all remaining text fits in currentBudget
      final remainingHeight = measureText(remainingText, isFirstPart);
      if (remainingHeight <= currentBudget) {
        final partInnerHtml = _sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          rawText.length,
        );
        final String partHtml;
        if (isFirstPart) {
          partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
        } else {
          partHtml =
              '<$tag$attrsNoId style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
        }
        // Trailing '\n' only exists on the final closing block in DomTextUtils
        final int charLength = (rawText.length - currentOffset) + 1;
        parts.add(_BlockPart(
          html: partHtml,
          height: remainingHeight,
          charLength: charLength,
        ));
        break;
      }

      // Remaining text exceeds currentBudget. Find word boundaries in remainingText
      final wordBoundaries = <int>[];
      final wsRegex = RegExp(r'\s+');
      for (final m in wsRegex.allMatches(remainingText)) {
        if (m.end > 0 && m.end < remainingText.length) {
          wordBoundaries.add(m.end);
        }
      }

      if (wordBoundaries.isEmpty) {
        // No whitespace boundaries (e.g., giant single word or unspaced text)
        final partInnerHtml = _sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          rawText.length,
        );
        final String partHtml;
        if (isFirstPart) {
          partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
        } else {
          partHtml =
              '<$tag$attrsNoId style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
        }
        final int charLength = (rawText.length - currentOffset) + 1;
        parts.add(_BlockPart(
          html: partHtml,
          height: remainingHeight,
          charLength: charLength,
        ));
        break;
      }

      // Binary search for the maximum word boundary that fits within currentBudget
      int low = 0;
      int high = wordBoundaries.length - 1;
      int bestIndex = -1;

      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final splitPoint = wordBoundaries[mid];
        final candidateText = remainingText.substring(0, splitPoint);
        final candidateHeight = measureText(candidateText, isFirstPart);

        if (candidateHeight <= currentBudget) {
          bestIndex = mid;
          low = mid + 1; // Try fitting more
        } else {
          high = mid - 1; // Over budget, try less
        }
      }

      // Prefer clean sentence boundary if one exists within 2 words before bestIndex
      if (bestIndex > 0) {
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
        // Not even 1 word boundary fits in currentBudget
        if (isFirstPart && currentBudget < maxPageHeight) {
          return const []; // Signal to flush page and retry with full budget
        }
        bestIndex = 0; // At full page height, force taking first word to make progress
      }

      final splitLength = wordBoundaries[bestIndex];
      final chunkText = remainingText.substring(0, splitLength);
      final chunkHeight = measureText(chunkText, isFirstPart);
      final chunkEndOffset = currentOffset + splitLength;

      final partInnerHtml = _sliceNodeInnerHtmlForRange(
        node,
        currentOffset,
        chunkEndOffset,
      );

      final String partHtml;
      if (isFirstPart) {
        partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
      } else {
        partHtml =
            '<$tag$attrsNoId style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
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
              height: measureText(rawText, true),
              charLength: DomTextUtils.extractPlainText(node).length,
            ),
          ];
  }

  /// Slices child DOM tree matching the exact character range [startOffset, endOffset),
  /// preserving inline tags (`<i>`, `<b>`, `<a>`, `<annotation-highlight>`) intact.
  static String _sliceNodeInnerHtmlForRange(
    dom.Element element,
    int startOffset,
    int endOffset,
  ) {
    if (startOffset >= endOffset) return '';

    if (element.nodes.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    int nodeStart = 0;

    for (final child in element.nodes) {
      final int nodeLen = child is dom.Text
          ? child.data.length
          : (child is dom.Element ? child.text.length : 0);

      final int nodeEnd = nodeStart + nodeLen;

      if (nodeEnd <= startOffset) {
        nodeStart = nodeEnd;
        continue;
      }
      if (nodeStart >= endOffset) {
        break;
      }

      final localStart = (startOffset - nodeStart).clamp(0, nodeLen);
      final localEnd = (endOffset - nodeStart).clamp(localStart, nodeLen);

      if (child is dom.Text) {
        final textSlice = child.data.substring(localStart, localEnd);
        buffer.write(const HtmlEscape().convert(textSlice));
      } else if (child is dom.Element) {
        final childTag = child.localName ?? 'span';
        final childAttrs = _serializeAttributes(child, stripId: false);
        final innerSlice = _sliceNodeInnerHtmlForRange(child, localStart, localEnd);
        buffer.write('<$childTag$childAttrs>$innerSlice</$childTag>');
      }

      nodeStart = nodeEnd;
    }

    return buffer.toString();
  }

  static String _wrapWithAncestors(String innerHtml, List<dom.Element> ancestors) {
    if (ancestors.isEmpty) return innerHtml;
    final open = StringBuffer();
    final close = StringBuffer();
    for (final el in ancestors) {
      open.write('<${el.localName ?? 'div'}${_serializeAttributes(el, stripId: true)}>');
    }
    for (final el in ancestors.reversed) {
      close.write('</${el.localName ?? 'div'}>');
    }
    return '$open$innerHtml$close';
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
