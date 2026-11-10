import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Defragments paragraphs in book HTML where line breaks or page boundaries from
/// PDF/OCR conversions inappropriately split sentences into multiple `<p>` elements.
class HtmlDefragmenter {
  static final RegExp _terminalPunctuationRegex = RegExp(r'[.!?…][’”"\s\x27]*$');
  static final RegExp _nonMergeEndingsRegex = RegExp(r'[:;—–][’”"\s\x27]*$');
  static final RegExp _lowercaseStartRegex = RegExp(r'^\s*[‘“"\x27]?[a-z]');
  static final RegExp _capitalStartRegex = RegExp(r'^\s*[‘“"\x27]?[A-Z]');
  static final RegExp _danglingFunctionWordRegex = RegExp(
    r'\b(of|to|in|for|with|from|by|at|on|into|upon|towards|between|through|under|over|after|before|the|a|an|his|her|their|my|our|your|its|and|but|or|as|than|that|which|who|whom|whose)$',
    caseSensitive: true,
  );

  /// Defragments all broken paragraphs across the document in place,
  /// preserving navigation anchors and stripping soft hyphens.
  static void defragmentDocument(dom.Document document) {
    final root = document.body ?? document.documentElement;
    if (root == null) return;
    _cleanTextNodes(root);
    _defragmentContainer(root);
  }

  /// Defragments HTML string and returns defragmented HTML.
  static String defragmentHtml(String html) {
    if (html.isEmpty || !html.contains('<p')) return html;
    try {
      final document = html_parser.parse(html);
      defragmentDocument(document);
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Recursively processes block containers and merges eligible adjacent `<p>` elements.
  static void _defragmentContainer(dom.Element container) {
    // 1. Recursively defragment child containers
    for (final child in List<dom.Element>.from(container.children)) {
      if (child.localName != 'p' && child.children.any((c) => c.localName == 'p')) {
        _defragmentContainer(child);
      }
    }

    // 2. Scan and merge consecutive paragraph siblings in this container
    var i = 0;
    while (i < container.children.length - 1) {
      final p1 = container.children[i];
      final p2 = container.children[i + 1];

      if (_canMerge(p1, p2)) {
        _mergeParagraphs(p1, p2);
        // Do not increment i; re-check p1 against the new next sibling
      } else {
        i++;
      }
    }
  }

  /// Determines whether paragraph [p2] should be merged into paragraph [p1].
  static bool _canMerge(dom.Element p1, dom.Element p2) {
    // Must both be <p> tags
    if (p1.localName != 'p' || p2.localName != 'p') return false;

    // Rule 2a: Exact same class and style attributes
    if (p1.attributes['class'] != p2.attributes['class']) return false;
    if (p1.attributes['style'] != p2.attributes['style']) return false;

    // Rule 2b: Neither should be aligned (center, right) or verse/special classes
    if (_isAlignedOrSpecial(p1) || _isAlignedOrSpecial(p2)) return false;

    // Rule 2c: Neither should contain line breaks (<br>)
    if (p1.querySelector('br') != null || p2.querySelector('br') != null) return false;

    // Rule 2d: Neither should be entirely wrapped in <i> or <em> (poems, songs)
    if (_isEntirelyItalic(p1) || _isEntirelyItalic(p2)) return false;

    // Rule 2e: Neither should be a standalone link (TOC entries)
    if (_isStandaloneLink(p1) || _isStandaloneLink(p2)) return false;

    final p1Text = p1.text.trim();
    final p2Text = p2.text.trim();
    if (p1Text.isEmpty || p2Text.isEmpty) return false;

    // Terminal punctuation check:
    // . ! ? … : ; — – can NEVER be merged
    if (_terminalPunctuationRegex.hasMatch(p1Text)) return false;
    if (_nonMergeEndingsRegex.hasMatch(p1Text)) return false;

    // Condition A: P2 starts with lowercase letter or quote + lowercase
    if (_lowercaseStartRegex.hasMatch(p2Text)) {
      return true;
    }

    // Condition B: P1 has >= 45 chars AND ends with a dangling lowercase function word
    // AND P2 starts with a capital letter (or quote + capital letter)
    if (p1Text.length >= 45 &&
        _danglingFunctionWordRegex.hasMatch(p1Text) &&
        _capitalStartRegex.hasMatch(p2Text)) {
      return true;
    }

    return false;
  }

  /// Checks if a paragraph is explicitly aligned or styled for special presentation.
  static bool _isAlignedOrSpecial(dom.Element p) {
    final align = p.attributes['align']?.toLowerCase() ?? '';
    final style = p.attributes['style']?.toLowerCase() ?? '';
    final className = p.attributes['class']?.toLowerCase() ?? '';

    if (align == 'center' || align == 'right') return true;
    if (style.contains('text-align: center') ||
        style.contains('text-align:center') ||
        style.contains('text-align: right') ||
        style.contains('text-align:right')) {
      return true;
    }
    if (className.contains('center') ||
        className.contains('title') ||
        className.contains('subtitle') ||
        className.contains('verse') ||
        className.contains('stanza') ||
        className.contains('poem') ||
        className.contains('song') ||
        className.contains('choice') ||
        className.contains('list')) {
      return true;
    }
    return false;
  }

  /// Checks if a paragraph's visible text is entirely wrapped in an <i> or <em> tag.
  static bool _isEntirelyItalic(dom.Element p) {
    final nonAnchorChildren = p.children.where((c) {
      final tag = c.localName?.toLowerCase();
      return tag != 'a' && tag != 'p-indent' && tag != 'indent';
    }).toList();
    if (nonAnchorChildren.length == 1) {
      final tag = nonAnchorChildren.first.localName?.toLowerCase();
      if (tag == 'i' || tag == 'em') {
        return nonAnchorChildren.first.text.trim() == p.text.trim();
      }
    }
    return false;
  }

  /// Checks if a paragraph consists solely of an anchor tag.
  static bool _isStandaloneLink(dom.Element p) {
    final nonIndentChildren = p.children.where((c) {
      final tag = c.localName?.toLowerCase();
      return tag != 'p-indent' && tag != 'indent';
    }).toList();
    if (nonIndentChildren.length == 1 &&
        nonIndentChildren.first.localName?.toLowerCase() == 'a') {
      return nonIndentChildren.first.text.trim() == p.text.trim();
    }
    return false;
  }

  /// Merges [p2] into [p1], preserving all inline anchors and child elements.
  static void _mergeParagraphs(dom.Element p1, dom.Element p2) {
    // 1. Remove any whitespace-only text nodes between p1 and p2 in the container
    final p1Index = p1.parentNode?.nodes.indexOf(p1) ?? -1;
    final p2Index = p2.parentNode?.nodes.indexOf(p2) ?? -1;
    if (p1Index != -1 && p2Index != -1 && p2Index > p1Index + 1) {
      for (var k = p2Index - 1; k > p1Index; k--) {
        final node = p1.parentNode!.nodes[k];
        if (node is dom.Text && node.text.trim().isEmpty) {
          node.remove();
        }
      }
    }

    // 2. Ensure a space separates p1 from p2 if needed
    final p1Text = p1.text;
    final p2Text = p2.text;
    if (!p1Text.endsWith(' ') &&
        !p1Text.endsWith('\n') &&
        !p2Text.startsWith(' ') &&
        !p2Text.startsWith('\n')) {
      p1.nodes.add(dom.Text(' '));
    }

    // 3. Move all child nodes from p2 into p1 (stripping any inner <p-indent> tags)
    for (final child in List<dom.Node>.from(p2.nodes)) {
      if (child is dom.Element &&
          (child.localName == 'p-indent' || child.localName == 'indent')) {
        continue;
      }
      p1.nodes.add(child);
    }

    // 4. Remove p2 from container
    p2.remove();
  }

  /// Cleans text nodes by stripping soft hyphens and collapsing consecutive ASCII spaces.
  static void _cleanTextNodes(dom.Node node) {
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'pre' || tag == 'code' || tag == 'script' || tag == 'style') {
        return;
      }
    }
    if (node is dom.Text) {
      var text = node.text;
      if (text.contains('\u00AD')) {
        text = text.replaceAll('\u00AD', '');
      }
      if (text.contains('  ') || text.contains('\t')) {
        text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
      }
      node.text = text;
    }
    for (final child in node.nodes) {
      _cleanTextNodes(child);
    }
  }
}
