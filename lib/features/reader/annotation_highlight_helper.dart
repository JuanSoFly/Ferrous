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

      final textNodes = DomTextUtils.collectTextNodes(root);
      if (textNodes.isEmpty) return html;

      for (final annotation in annotations) {
        final targetText = annotation.selectedText.trim();
        if (targetText.isEmpty) continue;

        _highlightInDom(root, textNodes, annotation, targetText);
      }

      final result = root.outerHtml;
      if (_cache.length > 30) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = result;
      return result;
    } catch (_) {
      // Fallback safely to original HTML on any parse exception
      return html;
    }
  }

  static void _highlightInDom(
    dom.Node root,
    List<dom.Text> textNodes,
    Annotation annotation,
    String targetText,
  ) {
    // 1. Try fast single-node match first
    for (int i = 0; i < textNodes.length; i++) {
      final node = textNodes[i];
      if (node.parent == null) continue;

      final nodeText = node.data;
      if (nodeText.isEmpty) continue;

      // Direct match
      final directIdx = nodeText.indexOf(targetText);
      if (directIdx != -1) {
        _splitAndWrapNode(node, directIdx, directIdx + targetText.length, annotation, textNodes, i);
        return;
      }

      // Soft-hyphen / whitespace aware match
      if (nodeText.contains('\u00AD') || nodeText.contains('\u00A0')) {
        final cleanText = nodeText.replaceAll('\u00AD', '').replaceAll('\u00A0', ' ');
        final cleanIdx = cleanText.indexOf(targetText);
        if (cleanIdx != -1) {
          final range = _mapCleanRangeToRaw(nodeText, cleanIdx, cleanIdx + targetText.length);
          if (range != null) {
            _splitAndWrapNode(node, range.$1, range.$2, annotation, textNodes, i);
            return;
          }
        }
      }
    }

    // 2. Fallback to multi-node match across inline elements
    _highlightAcrossNodes(textNodes, annotation, targetText);
  }

  static (int, int)? _mapCleanRangeToRaw(String raw, int cleanStart, int cleanEnd) {
    int rawIdx = 0;
    int cleanIdx = 0;
    int? mappedStart;
    int? mappedEnd;

    while (rawIdx <= raw.length) {
      if (cleanIdx == cleanStart && mappedStart == null) {
        mappedStart = rawIdx;
      }
      if (cleanIdx == cleanEnd && mappedEnd == null) {
        mappedEnd = rawIdx;
        break;
      }
      if (rawIdx >= raw.length) break;

      final code = raw.codeUnitAt(rawIdx);
      if (code != 0x00AD) {
        cleanIdx++;
      }
      rawIdx++;
    }

    if (mappedStart != null && mappedEnd != null && mappedStart < mappedEnd) {
      return (mappedStart, mappedEnd);
    }
    return null;
  }

  static void _splitAndWrapNode(
    dom.Text node,
    int start,
    int end,
    Annotation annotation,
    List<dom.Text> textNodes,
    int nodeIndex,
  ) {
    final parent = node.parent;
    if (parent == null) return;
    final indexInParent = parent.nodes.indexOf(node);
    if (indexInParent < 0) return;

    final nodeText = node.data;
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

    dom.Text? remainingText;
    if (after.isNotEmpty) {
      remainingText = dom.Text(after);
      newNodes.add(remainingText);
    }

    parent.nodes.removeAt(indexInParent);
    parent.nodes.insertAll(indexInParent, newNodes);

    if (remainingText != null && nodeIndex < textNodes.length) {
      textNodes[nodeIndex] = remainingText;
    }
  }

  static void _highlightAcrossNodes(
    List<dom.Text> textNodes,
    Annotation annotation,
    String targetText,
  ) {
    final buffer = StringBuffer();
    final nodeStarts = <int>[];
    final nodeEnds = <int>[];

    for (final node in textNodes) {
      final start = buffer.length;
      final clean = node.data.replaceAll('\u00AD', '').replaceAll('\u00A0', ' ');
      buffer.write(clean);
      nodeStarts.add(start);
      nodeEnds.add(buffer.length);
    }

    final fullText = buffer.toString();
    final matchStart = fullText.indexOf(targetText);
    if (matchStart == -1) return;
    final matchEnd = matchStart + targetText.length;

    for (int i = 0; i < textNodes.length; i++) {
      final nStart = nodeStarts[i];
      final nEnd = nodeEnds[i];
      if (matchEnd <= nStart || matchStart >= nEnd) continue;

      final node = textNodes[i];
      final parent = node.parent;
      if (parent == null) continue;

      final localCleanStart = (matchStart - nStart).clamp(0, nEnd - nStart);
      final localCleanEnd = (matchEnd - nStart).clamp(0, nEnd - nStart);
      if (localCleanStart >= localCleanEnd) continue;

      final range = _mapCleanRangeToRaw(node.data, localCleanStart, localCleanEnd);
      if (range == null) continue;

      _splitAndWrapNode(node, range.$1, range.$2, annotation, textNodes, i);
    }
  }
}
