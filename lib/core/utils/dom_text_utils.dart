import 'package:html/dom.dart' as dom;

/// Utility for extracting text from DOM with proper handling of block elements.
/// 
/// Unlike [Element.text] which simply concatenates text nodes, this utility
/// inserts separators (newlines) at block element boundaries so that TTS
/// and highlighting logic can properly align word positions.
class DomTextUtils {
  /// Block-level HTML tags that imply visual separation.
  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div',
    'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', 'form',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav',
    'noscript', 'ol', 'p', 'pre', 'section', 'table', 'tfoot', 'ul', 'tr',
  };

  /// Collect text nodes from DOM, inserting synthetic newline nodes at block boundaries.
  /// 
  /// Returns a list of [dom.Text] nodes. Some nodes may be "synthetic" (not attached
  /// to the DOM tree) representing structural breaks. These have `parent == null`.
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
      
      // Skip script/style content
      if (tag == 'script' || tag == 'style' || tag == 'noscript') {
        return;
      }

      // Handle <br> as line break
      if (tag == 'br') {
        out.add(dom.Text('\n'));
        return;
      }

      // Recurse into children
      for (final child in node.nodes) {
        _walkNode(child, out);
      }

      // Add separator after block elements
      if (tag != null && _blockTags.contains(tag)) {
        out.add(dom.Text('\n'));
      }
    } else {
      // DocumentFragment or other node types
      for (final child in node.nodes) {
        _walkNode(child, out);
      }
    }
  }

  /// Extract plain text from DOM with proper block-element spacing.
  /// 
  /// This produces text that matches what TTS engines expect, with words
  /// properly separated even across block boundaries.
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
