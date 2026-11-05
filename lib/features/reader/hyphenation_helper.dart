import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';

class HyphenationHelper {
  static const String softHyphen = '\u00AD';
  static const String indentString = '\u00A0\u00A0\u00A0\u00A0';

  static Hyphenator? _hyphenator;

  /// Returns the Hyphenator instance, lazily and synchronously initialized.
  static Hyphenator get hyphenator {
    return _hyphenator ??= Hyphenator(
      Language_en_us(),
      symbol: softHyphen,
    );
  }

  /// Initialize the hyphenator synchronously. Returns a `Future<void>` so existing callers
  /// can continue to call `await HyphenationHelper.init()` without breaking.
  static Future<void> init() async {
    _hyphenator ??= Hyphenator(
      Language_en_us(),
      symbol: softHyphen,
    );
  }

  /// Process HTML for hyphenation only.
  static String processHtml(String html) {
    try {
      final document = html_parser.parse(html);
      _processNode(document.body);
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Entry point for compute() isolate - hyphenation only.
  static Future<String> processHtmlIsolated(String html) async {
    return processHtml(html);
  }

  /// Single-pass: applies hyphenation, paragraph indentation, or both.
  /// [html] - raw HTML content
  /// [applyHyphenation] - whether to hyphenate text nodes
  /// [applyIndent] - whether to add paragraph indentation
  static String processHtmlAndIndent(
    String html, {
    bool applyHyphenation = true,
    bool applyIndent = true,
  }) {
    if (!applyHyphenation && !applyIndent) return html;

    try {
      final document = html_parser.parse(html);
      _processNodeHyphenateAndIndent(
        document.body,
        applyHyphenation: applyHyphenation,
        applyIndent: applyIndent,
      );
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Entry point for compute() isolate - combined hyphenation + indentation.
  /// Params: {html: String, hyphenation: bool, paragraphIndent: bool}
  static Future<String> processHtmlAndIndentIsolated(
    Map<String, dynamic> params,
  ) async {
    final html = params['html'] as String;
    final hyphenation = params['hyphenation'] as bool? ?? false;
    final paragraphIndent = params['paragraphIndent'] as bool? ?? false;

    return processHtmlAndIndent(
      html,
      applyHyphenation: hyphenation,
      applyIndent: paragraphIndent,
    );
  }

  /// Traversal for hyphenation only.
  static void _processNode(dom.Node? node) {
    if (node == null) return;

    if (node is dom.Element &&
        {'pre', 'code', 'script', 'style', 'tt'}.contains(node.localName?.toLowerCase())) {
      return;
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        node.text = hyphenator.hyphenateText(text);
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNode(child);
      }
    }
  }

  /// Single-pass traversal: indents paragraphs and hyphenates text nodes.
  static void _processNodeHyphenateAndIndent(
    dom.Node? node, {
    required bool applyHyphenation,
    required bool applyIndent,
  }) {
    if (node == null) return;

    if (node is dom.Element &&
        {'pre', 'code', 'script', 'style', 'tt'}.contains(node.localName?.toLowerCase())) {
      return;
    }

    // If this is a <p> tag and indent is enabled, indent it
    if (applyIndent &&
        node is dom.Element &&
        node.localName == 'p') {
      _indentParagraph(node);
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.trim().isNotEmpty && applyHyphenation) {
        // Hyphenate text content; preserve leading indent non-breaking spaces
        if (text.startsWith(indentString)) {
          final content = text.substring(indentString.length);
          node.text = '$indentString${hyphenator.hyphenateText(content)}';
        } else {
          node.text = hyphenator.hyphenateText(text);
        }
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNodeHyphenateAndIndent(
          child,
          applyHyphenation: applyHyphenation,
          applyIndent: applyIndent,
        );
      }
    }
  }

  /// Checks if a paragraph is explicitly aligned or styled (centered, right-aligned, or a list/choice item).
  static bool _isAlignedParagraph(dom.Element p) {
    final align = p.attributes['align']?.toLowerCase();
    final style = p.attributes['style']?.toLowerCase();
    final className = p.attributes['class']?.toLowerCase() ?? '';
    return align == 'center' ||
        align == 'right' ||
        (style != null &&
            (style.contains('text-align: center') ||
                style.contains('text-align: right') ||
                style.contains('text-align:center') ||
                style.contains('text-align:right'))) ||
        className.contains('center') ||
        className.contains('choice-item') ||
        className.contains('list-item');
  }

  /// Indents the first visible text node of a paragraph by prepending 4 non-breaking spaces.
  static void _indentParagraph(dom.Element p) {
    if (_isAlignedParagraph(p)) return;

    final leadingWhitespaceNodes = <dom.Text>[];
    dom.Text? targetTextNode;

    void findTarget(dom.Node node) {
      if (targetTextNode != null) return;

      if (node is dom.Text) {
        if (node.text.trim().isEmpty) {
          leadingWhitespaceNodes.add(node);
        } else {
          targetTextNode = node;
          return;
        }
      } else if (node.hasChildNodes()) {
        for (final child in node.nodes) {
          findTarget(child);
          if (targetTextNode != null) return;
        }
      }
    }

    findTarget(p);

    if (targetTextNode != null) {
      final text = targetTextNode!.text;
      if (!text.startsWith(indentString)) {
        // Clear preceding whitespace-only nodes in this paragraph so indent isn't preceded by newlines
        for (final wsNode in leadingWhitespaceNodes) {
          wsNode.text = '';
        }
        // Strip leading whitespace before adding non-breaking spaces
        final trimmed = text.replaceFirst(RegExp(r'^\s+'), '');
        targetTextNode!.text = '$indentString$trimmed';
      }
    }
  }
}
