import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Defragments paragraphs in book HTML where line breaks or page boundaries from
/// PDF/OCR conversions inappropriately split sentences into multiple `<p>` elements.
class HtmlDefragmenter {
  static final RegExp _terminalPunctuationRegex = RegExp(r'[.!?…][’”"\s\x27]*$');
  static final RegExp _ellipsisEndingRegex = RegExp(r'(?:\.\s*\.\s*\.|…)[’”"\s\x27]*$');
  static final RegExp _dashOrColonEndingRegex = RegExp(r'[:—–][’”"\s\x27]*$');
  static final RegExp _commaEndingRegex = RegExp(r',[’”"\s\x27]*$');

  static final RegExp _lowercaseStartRegex =
      RegExp(r'^\s*[‘“"\x27]*(?:[—–\-]+\s*)?[‘“"\x27]*[a-z]');

  static final RegExp _attributionStartRegex =
      RegExp(r'^\s*[‘“"\x27]?[—–\-]\s*[A-Z]');

  static final RegExp _capitalizedContinuationRegex = RegExp(
    r'^\s*[‘“"\x27]?[A-Z][a-zA-Z\-]*(?:\s+[A-Z][a-zA-Z\-]*)*[),;—:]\s+[‘“"\x27]?[a-z]',
  );

  static final RegExp _parentheticalCitationRegex = RegExp(
    r'^\s*\([A-Z][^\)]*\)[,;:]?\s+[a-z]',
  );

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

    // Rule 2e: Neither should be a standalone link (TOC entries)
    if (_isStandaloneLink(p1) || _isStandaloneLink(p2)) return false;

    final p1Text = p1.text.trim();
    final p2Text = p2.text.trim();
    if (p1Text.isEmpty || p2Text.isEmpty) return false;

    // Guardrail G1: Never merge an attribution (e.g. "—Arthur Schopenhauer") into preceding text
    if (_attributionStartRegex.hasMatch(p2Text) && _terminalPunctuationRegex.hasMatch(p1Text)) {
      return false;
    }

    // Italic rule: Only allow italic merging when BOTH elements are entirely italic (e.g. Screenshot 6)
    final p1Italic = _isEntirelyItalic(p1);
    final p2Italic = _isEntirelyItalic(p2);
    if ((p1Italic || p2Italic) && !(p1Italic && p2Italic)) return false;
    if (p1Italic && p2Italic && p1Text.length < 40 && _terminalPunctuationRegex.hasMatch(p1Text)) {
      return false;
    }

    final hasUnclosedParen = _hasUnclosedParen(p1Text);
    final isLowercaseContinuation = _lowercaseStartRegex.hasMatch(p2Text);
    final isCapitalizedContinuation = _capitalizedContinuationRegex.hasMatch(p2Text);
    final isParentheticalCitation = _parentheticalCitationRegex.hasMatch(p2Text);

    // Terminal punctuation check:
    // . ! ? … can only merge if p1 ends with an ellipsis AND p2 starts lowercase (Break 1)
    if (_terminalPunctuationRegex.hasMatch(p1Text)) {
      final isEllipsis = _ellipsisEndingRegex.hasMatch(p1Text);
      if (!isEllipsis || !isLowercaseContinuation) {
        return false;
      }
    }

    // Em-dash (—) or colon (:) ends: allow merge if p2 is a lowercase continuation (Breaks 3 & 4)
    if (_dashOrColonEndingRegex.hasMatch(p1Text)) {
      return isLowercaseContinuation;
    }

    // Comma (,) ends: allow merge if p1 has unclosed paren OR (p1 >= 45 chars AND p2 continues)
    if (_commaEndingRegex.hasMatch(p1Text)) {
      if (hasUnclosedParen) return true;
      if (p1Text.length >= 45 && (isLowercaseContinuation || isCapitalizedContinuation)) {
        return true;
      }
      return false;
    }

    // Unclosed parenthesis continuation (Breaks 5B & 5C):
    // e.g. "(Wilfred Bion," / "Elliot Aronson)." or "(George Eliot, Henry James, Ralph" / "Ellison), who..."
    if (hasUnclosedParen && _p2ClosesParen(p2Text)) {
      return true;
    }

    // Break 5A: Unpunctuated prose line followed by parenthetical citation
    // e.g. "of our economic behavior" / "(Daniel Kahneman), and of how..."
    if (p1Text.length >= 40 && isParentheticalCitation) {
      return true;
    }

    // Capitalized name + mid-sentence punctuation continuation (Break 5C)
    if (isCapitalizedContinuation) {
      return true;
    }

    // Lowercase continuation (Break 2 & general prose wraps)
    if (isLowercaseContinuation) {
      return true;
    }

    // Dangling function word continuation (e.g. "...into a calmer and" / "more strategic...")
    if (p1Text.length >= 45 &&
        _danglingFunctionWordRegex.hasMatch(p1Text) &&
        RegExp(r'^\s*[‘“"\x27]?[A-Z]').hasMatch(p2Text)) {
      return true;
    }

    return false;
  }

  static bool _hasUnclosedParen(String text) {
    var depth = 0;
    for (final char in text.runes) {
      if (char == 0x28) depth++; // '('
      if (char == 0x29) depth = (depth - 1).clamp(0, 9999); // ')'
    }
    return depth > 0;
  }

  static bool _p2ClosesParen(String text) {
    final closeIdx = text.indexOf(')');
    final openIdx = text.indexOf('(');
    if (closeIdx == -1) return false;
    return openIdx == -1 || closeIdx < openIdx;
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
    if (p.children.isEmpty) return false;
    // Reject if there is any non-whitespace text directly inside <p> outside of <i>/<em>
    for (final node in p.nodes) {
      if (node is dom.Text && node.text.trim().isNotEmpty) return false;
    }
    return p.children.every(
      (c) => c.localName == 'i' || c.localName == 'em',
    );
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
    // 1. Remove whitespace nodes between p1 and p2 in parent container
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

    // 2. Trim trailing whitespace text nodes in p1 and leading whitespace text nodes in p2
    while (p1.nodes.isNotEmpty &&
        p1.nodes.last is dom.Text &&
        (p1.nodes.last as dom.Text).text.trim().isEmpty) {
      p1.nodes.removeLast();
    }
    while (p2.nodes.isNotEmpty &&
        p2.nodes.first is dom.Text &&
        (p2.nodes.first as dom.Text).text.trim().isEmpty) {
      p2.nodes.removeAt(0);
    }

    // 3. Coalesce matching inline elements (e.g. <i class="calibre3"> + <i class="calibre3">)
    final last1 = p1.nodes.isNotEmpty ? p1.nodes.last : null;
    final first2 = p2.nodes.isNotEmpty ? p2.nodes.first : null;

    final needsSpace = !p1.text.endsWith(' ') &&
        !p1.text.endsWith('\n') &&
        !p2.text.startsWith(' ') &&
        !p2.text.startsWith('\n');

    if (last1 is dom.Element &&
        first2 is dom.Element &&
        last1.localName == first2.localName &&
        last1.attributes['class'] == first2.attributes['class'] &&
        last1.attributes['style'] == first2.attributes['style']) {
      if (needsSpace) {
        last1.nodes.add(dom.Text(' '));
      }
      for (final child in List<dom.Node>.from(first2.nodes)) {
        last1.nodes.add(child);
      }
      first2.remove();
    } else if (needsSpace) {
      p1.nodes.add(dom.Text(' '));
    }

    // 4. Move remaining child nodes from p2 into p1 (stripping any inner <p-indent> tags)
    for (final child in List<dom.Node>.from(p2.nodes)) {
      if (child is dom.Element &&
          (child.localName == 'p-indent' || child.localName == 'indent')) {
        continue;
      }
      p1.nodes.add(child);
    }

    // 5. Remove p2 from container
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
      if (text.contains('&shy;')) {
        text = text.replaceAll('&shy;', '');
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
