import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/utils/dom_text_utils.dart';

/// Helper to inject annotation highlight tags into chapter HTML.
class AnnotationHighlightHelper {
  static const String highlightTag = 'annotation-highlight';

  // Small LRU cache to avoid re-parsing DOM on every UI frame/rebuild
  static final Map<String, String> _cache = {};

  static String _generateCacheKey(String html, List<Annotation> annotations) {
    final annotationSig = annotations.map((a) => '${a.id}:${a.color}').join(',');
    return '${html.hashCode}:$annotationSig';
  }

  /// Injects `<annotation-highlight>` elements into [html] for each annotation in [annotations].
  static String applyHighlights(String html, List<Annotation> annotations) {
    if (annotations.isEmpty || html.isEmpty) return html;

    final key = _generateCacheKey(html, annotations);
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final document = html_parser.parse(html);
      final root = document.body ?? document.documentElement;
      if (root == null) return html;

      for (final annotation in annotations) {
        final targetText = annotation.selectedText.trim();
        if (targetText.isEmpty) continue;

        final textNodes = DomTextUtils.collectTextNodes(root)
            .where((n) => n.parent != null && n.data.isNotEmpty)
            .toList();
        if (textNodes.isEmpty) continue;

        _highlightInDom(textNodes, annotation, targetText);
      }

      final result = root.outerHtml;
      if (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = result;
      return result;
    } catch (_) {
      // Fallback safely to original HTML on any parse exception
      return html;
    }
  }

  static String _normalize(String s) {
    return s
        .replaceAll('\u00AD', '') // soft hyphen
        .replaceAll('\u200B', '') // zero-width space
        .replaceAll('\u00A0', ' ') // non-breaking space
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static ({String normalized, List<int> rawOffsets}) _buildNormalizedNodeMap(String raw) {
    final buffer = StringBuffer();
    final rawOffsets = <int>[];
    var inWhitespace = false;
    var rawOffset = 0;

    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final codeUnitLen = ch.length;

      if (ch == '\u00AD' || ch == '\u200B') {
        rawOffset += codeUnitLen;
        continue;
      }

      var charToUse = ch;
      if (ch == '\u00A0') {
        charToUse = ' ';
      } else if (ch == '’' || ch == '‘') {
        charToUse = "'";
      } else if (ch == '“' || ch == '”') {
        charToUse = '"';
      } else if (ch == '—' || ch == '–') {
        charToUse = '-';
      }

      final isWhitespace = charToUse.trim().isEmpty;
      if (isWhitespace) {
        if (buffer.isEmpty) {
          rawOffset += codeUnitLen;
          continue;
        }
        if (inWhitespace) {
          rawOffset += codeUnitLen;
          continue;
        }

        buffer.write(' ');
        rawOffsets.add(rawOffset);
        inWhitespace = true;
        rawOffset += codeUnitLen;
        continue;
      }

      inWhitespace = false;
      buffer.write(charToUse);
      for (int k = 0; k < codeUnitLen; k++) {
        rawOffsets.add(rawOffset + k);
      }
      rawOffset += codeUnitLen;
    }

    var normalized = buffer.toString();
    if (normalized.endsWith(' ') && rawOffsets.isNotEmpty) {
      normalized = normalized.substring(0, normalized.length - 1);
      rawOffsets.removeLast();
    }

    return (normalized: normalized, rawOffsets: rawOffsets);
  }

  static void _highlightInDom(
    List<dom.Text> textNodes,
    Annotation annotation,
    String targetText,
  ) {
    // 1. Try fast single-node direct match
    for (int i = 0; i < textNodes.length; i++) {
      final node = textNodes[i];
      if (node.parent == null) continue;
      final nodeText = node.data;
      if (nodeText.isEmpty) continue;

      final directIdx = nodeText.indexOf(targetText);
      if (directIdx != -1) {
        _splitAndWrapNode(node, directIdx, directIdx + targetText.length, annotation);
        return;
      }
    }

    // 2. Single-node normalized match
    final normTarget = _normalize(targetText);
    if (normTarget.isEmpty) return;

    for (int i = 0; i < textNodes.length; i++) {
      final node = textNodes[i];
      if (node.parent == null) continue;
      final nodeText = node.data;
      if (nodeText.isEmpty) continue;

      final nodeMap = _buildNormalizedNodeMap(nodeText);
      final matchIdx = nodeMap.normalized.indexOf(normTarget);
      if (matchIdx != -1) {
        final matchEnd = matchIdx + normTarget.length;
        final rawStart = nodeMap.rawOffsets[matchIdx];
        final rawEnd = nodeMap.rawOffsets[matchEnd - 1] + 1;
        _splitAndWrapNode(node, rawStart, rawEnd, annotation);
        return;
      }
    }

    // 3. Multi-node match across inline elements
    _highlightAcrossNodes(textNodes, annotation, normTarget);
  }

  static void _highlightAcrossNodes(
    List<dom.Text> textNodes,
    Annotation annotation,
    String normTarget,
  ) {
    final buffer = StringBuffer();
    final mappings = <({int nodeIndex, int rawOffset})>[];
    var inWhitespace = false;

    for (int nodeIdx = 0; nodeIdx < textNodes.length; nodeIdx++) {
      final raw = textNodes[nodeIdx].data;
      var rawOffset = 0;

      for (final rune in raw.runes) {
        final ch = String.fromCharCode(rune);
        final codeUnitLen = ch.length;

        if (ch == '\u00AD' || ch == '\u200B') {
          rawOffset += codeUnitLen;
          continue;
        }

        var charToUse = ch;
        if (ch == '\u00A0') {
          charToUse = ' ';
        } else if (ch == '’' || ch == '‘') {
          charToUse = "'";
        } else if (ch == '“' || ch == '”') {
          charToUse = '"';
        } else if (ch == '—' || ch == '–') {
          charToUse = '-';
        }

        final isWhitespace = charToUse.trim().isEmpty;
        if (isWhitespace) {
          if (buffer.isEmpty) {
            rawOffset += codeUnitLen;
            continue;
          }
          if (inWhitespace) {
            rawOffset += codeUnitLen;
            continue;
          }

          buffer.write(' ');
          mappings.add((nodeIndex: nodeIdx, rawOffset: rawOffset));
          inWhitespace = true;
          rawOffset += codeUnitLen;
          continue;
        }

        inWhitespace = false;
        buffer.write(charToUse);
        for (int k = 0; k < codeUnitLen; k++) {
          mappings.add((nodeIndex: nodeIdx, rawOffset: rawOffset + k));
        }
        rawOffset += codeUnitLen;
      }
    }

    var combinedNormalized = buffer.toString();
    if (combinedNormalized.endsWith(' ') && mappings.isNotEmpty) {
      combinedNormalized = combinedNormalized.substring(0, combinedNormalized.length - 1);
      mappings.removeLast();
    }

    final matchIdx = combinedNormalized.indexOf(normTarget);
    if (matchIdx == -1) return;

    final matchEnd = matchIdx + normTarget.length;
    final nodeSlices = <int, List<int>>{};
    for (int i = matchIdx; i < matchEnd; i++) {
      final m = mappings[i];
      nodeSlices.putIfAbsent(m.nodeIndex, () => []).add(m.rawOffset);
    }

    final sortedNodeIndices = nodeSlices.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final nodeIdx in sortedNodeIndices) {
      final offsets = nodeSlices[nodeIdx]!;
      final node = textNodes[nodeIdx];
      if (node.parent == null) continue;
      final rawStart = offsets.first;
      final rawEnd = offsets.last + 1;
      _splitAndWrapNode(node, rawStart, rawEnd, annotation);
    }
  }

  static void _splitAndWrapNode(
    dom.Text node,
    int start,
    int end,
    Annotation annotation,
  ) {
    final parent = node.parent;
    if (parent == null) return;
    final indexInParent = parent.nodes.indexOf(node);
    if (indexInParent < 0) return;

    final nodeText = node.data;
    if (start < 0 || end > nodeText.length || start >= end) return;

    final before = nodeText.substring(0, start);
    final mid = nodeText.substring(start, end);
    final after = nodeText.substring(end);

    final newNodes = <dom.Node>[];
    if (before.isNotEmpty) newNodes.add(dom.Text(before));

    final highlightEl = dom.Element.tag(highlightTag);
    highlightEl.attributes['data-id'] = annotation.id;
    highlightEl.attributes['data-color'] = '${annotation.color}';
    highlightEl.append(dom.Text(mid));
    newNodes.add(highlightEl);

    if (after.isNotEmpty) {
      newNodes.add(dom.Text(after));
    }

    parent.nodes.removeAt(indexInParent);
    parent.nodes.insertAll(indexInParent, newNodes);
  }
}
