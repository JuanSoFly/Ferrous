import 'package:html/dom.dart' as dom;

/// Utility for extracting text from DOM with proper handling of block elements.
class DomTextUtils {
  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div',
    'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', 'form',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav',
    'noscript', 'ol', 'p', 'pre', 'section', 'table', 'tfoot', 'ul', 'tr',
  };

  static List<dom.Text> collectTextNodes(dom.Node? root) {
    if (root == null) return const [];
    
    final result = <dom.Text>[];
    _walkNode(root, result);
    return result;
  }

  static void _walkNode(dom.Node node, List<dom.Text> out) {
    if (node is dom.Text) {
      out.add(node);
      return;
    }

    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'script' || tag == 'style' || tag == 'noscript') {
        return;
      }
      if (tag == 'br') {
        out.add(dom.Text('\n'));
        return;
      }
      for (final child in node.nodes) {
        _walkNode(child, out);
      }
      if (tag != null && _blockTags.contains(tag)) {
        out.add(dom.Text('\n'));
      }
    } else {
      for (final child in node.nodes) {
        _walkNode(child, out);
      }
    }
  }

  /// Extract plain text from DOM with proper block-element spacing.
  static String extractPlainText(dom.Node? root) {
    if (root == null) return '';
    
    final nodes = collectTextNodes(root);
    if (nodes.isEmpty) return '';

    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer.write(node.data);
    }
    return buffer.toString();
  }
}
