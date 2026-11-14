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
        '${paragraphSpacing.toStringAsFixed(1)}:${fontFamily ?? "default"}:'
        '${textAlign.name}:${fontWeight.value}:${wordSpacing.toStringAsFixed(2)}:'
        '$paragraphIndent:$hyphenation:${textScale.toStringAsFixed(2)}:$annotationSig';

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
      return base.copyWith(letterSpacing: wordSpacing, wordSpacing: null);
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
      final normalized = isPre ? text : text.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').trim();
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

    void flushPage() {
      if (currentHeight == 0 && runningCharOffset == pageStartCharOffset && currentBuffer.isEmpty) {
        return;
      }

      final closeBuffer = StringBuffer();
      for (final el in openAncestors.reversed) {
        closeBuffer.write('</${el.localName ?? 'div'}>');
      }

      final sliceHtml =
          '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>${currentBuffer.toString()}$closeBuffer</body></html>';
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

    void processNodes(List<dom.Node> nodes) {
      for (int i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        if (node is dom.Element) {
          final tag = node.localName?.toLowerCase() ?? '';

          // Structural container elements with multiple children
          if ((tag == 'div' || tag == 'section' || tag == 'article' || tag == 'main') &&
              node.children.length > 1) {
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
            continue;
          }

          final isHeading = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag);
          final hasImage = tag == 'img' ||
              tag == 'svg' ||
              tag == 'image' ||
              node.querySelector('img, svg, image') != null;

          final nodeText = _extractMeasurementText(node, isPre: tag == 'pre');
          final textLen = DomTextUtils.extractPlainText(node).length;

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
              isIndent: paragraphIndent && tag == 'p',
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
            continue;
          }

          // If block fits on current page, append directly
          if (currentHeight + blockHeight <= maxPageHeight) {
            currentBuffer.write(node.outerHtml);
            currentHeight += blockHeight;
            runningCharOffset += textLen;
            continue;
          }

          // Multi-page paragraph/block splitting
          final canSplit = (tag == 'p' || tag == 'blockquote' || tag == 'div') && !hasImage;

          if (canSplit) {
            final double minRemainingSpace = fontSize * lineHeight * 2.0;
            double remainingHeight = maxPageHeight - currentHeight;

            // If remaining space on current page is too small (< 2 lines), start fresh on next page
            if (currentHeight > 0 && remainingHeight < minRemainingSpace) {
              flushPage();
              remainingHeight = maxPageHeight;
            }

            var splitParts = _splitBlockAcrossPages(
              node: node,
              firstBudget: remainingHeight,
              maxPageHeight: maxPageHeight,
              measureText: (txt, isIndent, {required bool isLastPart}) => measureTextHeight(
                txt,
                isIndent: isIndent && paragraphIndent,
                extraBottomMargin: isLastPart ? paragraphSpacing : 0.0,
                isPre: tag == 'pre',
                isHeading: false,
              ),
              isPre: tag == 'pre',
            );

            if (splitParts.isEmpty && currentHeight > 0) {
              flushPage();
              splitParts = _splitBlockAcrossPages(
                node: node,
                firstBudget: maxPageHeight,
                maxPageHeight: maxPageHeight,
                measureText: (txt, isIndent, {required bool isLastPart}) => measureTextHeight(
                  txt,
                  isIndent: isIndent && paragraphIndent,
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
            continue;
          }

          // Standard atomic block doesn't fit on current page -> flush and start new page
          if (currentHeight > 0) {
            flushPage();
          }
          currentBuffer.write(node.outerHtml);
          currentHeight += blockHeight;
          runningCharOffset += textLen;
        } else if (node is dom.Text && node.text.trim().isNotEmpty) {
          final escaped = const HtmlEscape().convert(node.text);
          currentBuffer.write(escaped);
          runningCharOffset += node.text.length;
        }
      }
    }

    processNodes(body.nodes);
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

  /// Splits an oversized element into multiple continuous pieces across 2, 3, or more pages
  static List<_BlockPart> _splitBlockAcrossPages({
    required dom.Element node,
    required double firstBudget,
    required double maxPageHeight,
    required double Function(String, bool, {required bool isLastPart}) measureText,
    bool isPre = false,
  }) {
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

      // Check if all remaining text fits in currentBudget
      final remainingHeight = measureText(remainingText, isFirstPart, isLastPart: true);
      if (remainingHeight <= currentBudget) {
        final partInnerHtml = _sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          rawText.length,
          isPre: isPre,
        );
        final String partHtml;
        if (isFirstPart) {
          partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
        } else {
          partHtml =
              '<$tag$attrsNoId class="page-continuation" style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
        }
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
        final partInnerHtml = _sliceNodeInnerHtmlForRange(
          node,
          currentOffset,
          rawText.length,
          isPre: isPre,
        );
        final String partHtml;
        if (isFirstPart) {
          partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
        } else {
          partHtml =
              '<$tag$attrsNoId class="page-continuation" style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
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
        final candidateHeight = measureText(candidateText, isFirstPart, isLastPart: false);

        if (candidateHeight <= currentBudget) {
          bestIndex = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
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
        if (isFirstPart && currentBudget < maxPageHeight) {
          return const []; // Signal to flush page and retry with full budget
        }
        bestIndex = 0; // At full page height, force taking first word to make progress
      }

      final splitLength = wordBoundaries[bestIndex];
      final chunkText = remainingText.substring(0, splitLength);
      final chunkHeight = measureText(chunkText, isFirstPart, isLastPart: false);
      final chunkEndOffset = currentOffset + splitLength;

      final partInnerHtml = _sliceNodeInnerHtmlForRange(
        node,
        currentOffset,
        chunkEndOffset,
        isPre: isPre,
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
              height: measureText(rawText, true, isLastPart: true),
              charLength: DomTextUtils.extractPlainText(node).length,
            ),
          ];
  }

  /// Slices child DOM tree matching the exact character range [startOffset, endOffset),
  /// preserving inline tags (`<i>`, `<b>`, `<a>`, `<annotation-highlight>`) and void elements.
  static String _sliceNodeInnerHtmlForRange(
    dom.Element element,
    int startOffset,
    int endOffset, {
    bool isPre = false,
  }) {
    if (startOffset >= endOffset) return '';
    if (element.nodes.isEmpty) return '';

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
        final localEnd = (endOffset - nodeStart).clamp(localStart, nodeLen);

        final textSlice = text.substring(localStart, localEnd);
        buffer.write(const HtmlEscape().convert(textSlice));
        nodeStart = nodeEnd;
      } else if (child is dom.Element) {
        final childTag = child.localName?.toLowerCase() ?? 'span';

        // Void elements: <br> emits only within slice boundary
        if (childTag == 'br') {
          if (nodeStart > startOffset && nodeStart < endOffset) {
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

        final childText = _extractMeasurementText(child, isPre: isPre);
        final int nodeLen = childText.length;
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

        final childAttrs = _serializeAttributes(child, stripId: false);
        final innerSlice = _sliceNodeInnerHtmlForRange(
          child,
          localStart,
          localEnd,
          isPre: isPre,
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
