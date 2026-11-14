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

    final cacheKey =
        '$bookId:$chapterIndex:${availableWidth.toInt()}x${availableHeight.toInt()}:'
        '${fontSize.toStringAsFixed(1)}:${lineHeight.toStringAsFixed(2)}:'
        '${fontFamily ?? "default"}:$paragraphIndent:$hyphenation:$annotationSig';

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

    // 2-line safety ceiling ensures flutter_html never overflows into RenderFlex crashes
    final maxPageHeight =
        (availableHeight - (fontSize * lineHeight * 2.0)).clamp(100.0, availableHeight);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      strutStyle: StrutStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        forceStrutHeight: true,
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
    }) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return fontSize * lineHeight + extraBottomMargin;

      final measurementText = isIndent ? '\u2003\u2003$trimmed' : trimmed;
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
    final currentBuffer = StringBuffer();
    double currentHeight = 0.0;
    int runningCharOffset = 0;
    int pageStartCharOffset = 0;

    void flushPage() {
      if (currentBuffer.isEmpty) return;
      final pageIndex = pages.length;
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
                  extraBottomMargin: isHeading ? fontSize * 0.8 : 0.0,
                );

          // Keep headings attached to at least 2 lines of text
          if (isHeading &&
              currentHeight > 0 &&
              (currentHeight + blockHeight + (fontSize * lineHeight * 2.5)) >
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

          // Multi-page paragraph/block splitting
          final canSplit = (tag == 'p' || tag == 'blockquote' || tag == 'div') &&
              !hasImage &&
              node.text.length > 40;

          if (canSplit) {
            final double minRemainingSpace = fontSize * lineHeight * 2.5;
            final double remainingHeight = maxPageHeight - currentHeight;

            // If remaining space on current page is too small, start fresh on next page
            if (currentHeight > 0 && remainingHeight < minRemainingSpace) {
              flushPage();
            }

            // Perform non-destructive multi-page splitting
            final splitParts = _splitBlockAcrossPages(
              node: node,
              firstBudget: (maxPageHeight - currentHeight).clamp(
                minRemainingSpace,
                maxPageHeight,
              ),
              maxPageHeight: maxPageHeight,
              measureText: (txt, isIndent) => measureTextHeight(
                txt,
                isIndent: isIndent && paragraphIndent,
              ),
            );

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
    final text = node.text;
    final sentenceMatches =
        RegExp(r'[^.!?]+[.!?]+["”’\)]*\s*|[^.!?]+$').allMatches(text);
    final sentences = sentenceMatches.map((m) => m.group(0)!).toList();

    if (sentences.length <= 1) {
      final h = measureText(text, true);
      final len = DomTextUtils.extractPlainText(node).length;
      return [_BlockPart(html: node.outerHtml, height: h, charLength: len)];
    }

    final tag = node.localName ?? 'p';
    final attrs = _serializeAttributes(node, stripId: false);
    final attrsNoId = _serializeAttributes(node, stripId: true);

    final parts = <_BlockPart>[];
    int sentenceIndex = 0;
    int currentBlockOffset = 0;
    double currentBudget = firstBudget;
    bool isFirstPart = true;

    while (sentenceIndex < sentences.length) {
      final accumulated = StringBuffer();
      double accumulatedHeight = 0.0;
      int chunkSentenceCount = 0;

      while (sentenceIndex < sentences.length) {
        final sentence = sentences[sentenceIndex];
        final candidate = '${accumulated.toString()}$sentence';
        final candidateHeight = measureText(candidate, isFirstPart);

        if (candidateHeight > currentBudget && chunkSentenceCount > 0) {
          break;
        }

        accumulated.write(sentence);
        accumulatedHeight = candidateHeight;
        chunkSentenceCount++;
        sentenceIndex++;
      }

      if (chunkSentenceCount == 0 && sentenceIndex < sentences.length) {
        final sentence = sentences[sentenceIndex];
        accumulated.write(sentence);
        accumulatedHeight = measureText(sentence, isFirstPart);
        sentenceIndex++;
      }

      final chunkText = accumulated.toString();
      final isLastPart = sentenceIndex >= sentences.length;
      final chunkEndOffset = currentBlockOffset + chunkText.length;

      // Extract non-destructive DOM HTML for this exact text range
      final partInnerHtml = _sliceNodeInnerHtmlForRange(node, currentBlockOffset, chunkEndOffset);
      currentBlockOffset = chunkEndOffset;

      final String partHtml;
      if (isFirstPart) {
        partHtml = '<$tag$attrs>$partInnerHtml</$tag>';
      } else {
        partHtml =
            '<$tag$attrsNoId style="text-indent: 0px; margin-top: 0px;">$partInnerHtml</$tag>';
      }

      // Trailing '\n' only exists on the final closing block in DomTextUtils
      final int charLength = chunkText.length + (isLastPart ? 1 : 0);

      parts.add(
        _BlockPart(
          html: partHtml,
          height: accumulatedHeight,
          charLength: charLength,
        ),
      );

      isFirstPart = false;
      currentBudget = maxPageHeight;
    }

    return parts.isNotEmpty
        ? parts
        : [
            _BlockPart(
              html: node.outerHtml,
              height: measureText(text, true),
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
