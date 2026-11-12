import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/core/utils/dom_text_utils.dart';

class DomChunkResult {
  final List<String> chunks;
  final List<int> chunkStartOffsets;

  const DomChunkResult({
    required this.chunks,
    required this.chunkStartOffsets,
  });
}

/// Slices large HTML documents into valid, standalone HTML chunks of ~18 paragraphs,
/// unwrapping oversized wrapper divs while preserving ancestor CSS classes,
/// anchor IDs, and keeping headings attached to subsequent paragraphs.
class DomChunker {
  static const int targetBlocksPerChunk = 18;
  static const int maxSingleNodeHtmlLength = 8000;

  static DomChunkResult split(String fullHtml) {
    if (fullHtml.length < 15000) {
      return DomChunkResult(
        chunks: [fullHtml],
        chunkStartOffsets: [0],
      );
    }

    final document = html_parser.parse(fullHtml);
    final body = document.body;
    if (body == null) {
      return DomChunkResult(
        chunks: [fullHtml],
        chunkStartOffsets: [0],
      );
    }

    final headHtml = document.head?.outerHtml ?? '<head><meta charset="utf-8"></head>';
    final bodyAttrs = _serializeAttributes(body, stripId: false);

    final chunks = <String>[];
    final chunkOffsets = <int>[];
    final currentBuffer = StringBuffer();
    int currentBlockCount = 0;
    int currentChunkTextLen = 0;
    int runningTextOffset = 0;

    void flushChunk() {
      if (currentBuffer.isEmpty) return;
      chunks.add(
        '<!DOCTYPE html><html>$headHtml<body$bodyAttrs>${currentBuffer.toString()}</body></html>',
      );
      chunkOffsets.add(runningTextOffset);
      runningTextOffset += currentChunkTextLen;
      currentBuffer.clear();
      currentBlockCount = 0;
      currentChunkTextLen = 0;
    }

    void processNodes(List<dom.Node> nodes, List<dom.Element> ancestorWrappers) {
      for (final node in nodes) {
        if (node is dom.Element) {
          final tag = node.localName?.toLowerCase() ?? '';
          final isWrapper = (tag == 'div' || tag == 'section' || tag == 'article') &&
              node.children.length > 1 &&
              node.outerHtml.length > maxSingleNodeHtmlLength;

          if (isWrapper) {
            // Guardrail 1: Preserve anchor ID before unwrapping so target jumps do not break
            final id = (node.attributes['id'] ?? '').trim();
            if (id.isNotEmpty) {
              final escapedId = const HtmlEscape(HtmlEscapeMode.attribute).convert(id);
              currentBuffer.write('<span id="$escapedId"></span>');
            }
            processNodes(node.nodes, [...ancestorWrappers, node]);
            continue;
          }

          currentBuffer.write(_wrapWithAncestors(node.outerHtml, ancestorWrappers));

          // Track plain text length for TTS offset translation
          final nodeTextNodes = DomTextUtils.collectTextNodes(node);
          for (final t in nodeTextNodes) {
            currentChunkTextLen += t.data.length;
          }

          final isHeading = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag);
          final isBlock = {'p', 'div', 'blockquote', 'ul', 'ol', 'pre', 'table'}.contains(tag);

          // Never flush immediately after a heading so headings stay attached to their next paragraph
          if (isBlock && !isHeading) {
            currentBlockCount++;
            if (currentBlockCount >= targetBlocksPerChunk) {
              flushChunk();
            }
          }
        } else if (node is dom.Text && node.text.trim().isNotEmpty) {
          final escaped = const HtmlEscape().convert(node.text);
          currentBuffer.write(_wrapWithAncestors(escaped, ancestorWrappers));
          currentChunkTextLen += node.text.length;
        }
      }
    }

    processNodes(body.nodes, const []);
    flushChunk();

    return DomChunkResult(
      chunks: chunks.isNotEmpty ? chunks : [fullHtml],
      chunkStartOffsets: chunkOffsets.isNotEmpty ? chunkOffsets : [0],
    );
  }

  static String _wrapWithAncestors(String innerHtml, List<dom.Element> ancestors) {
    if (ancestors.isEmpty) return innerHtml;
    final openTags = StringBuffer();
    final closeTags = StringBuffer();
    for (final el in ancestors) {
      final tag = el.localName ?? 'div';
      // Strip 'id' on cloned wrappers to avoid duplicate IDs across chunks
      openTags.write('<$tag${_serializeAttributes(el, stripId: true)}>');
    }
    for (final el in ancestors.reversed) {
      closeTags.write('</${el.localName ?? 'div'}>');
    }
    return '$openTags$innerHtml$closeTags';
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
