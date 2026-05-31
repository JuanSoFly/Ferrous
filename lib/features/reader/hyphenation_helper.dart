import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:flutter/foundation.dart';

class HyphenationHelper {
  static Hyphenator? _hyphenator;
  static bool _isLoading = false;

  static Future<void> init() async {
    if (_hyphenator != null || _isLoading) return;
    _isLoading = true;
    try {
      // Use loadAsyncByAbbr to avoid import issues and specify soft hyphen
      _hyphenator = await Hyphenator.loadAsyncByAbbr('en_us', symbol: '­');
    } catch (e) {
      debugPrint('Failed to load hyphenator: $e');
    } finally {
      _isLoading = false;
    }
  }

  static String processHtml(String html) {
    if (_hyphenator == null) return html;

    try {
      final document = html_parser.parse(html);
      _processNode(document.body);
      return document.body?.innerHtml ?? html;
    } catch (e) {
      return html;
    }
  }

  /// Entry point for compute() isolate - hyphenation only
  static Future<String> processHtmlIsolated(String html) async {
    await init();
    return processHtml(html);
  }

  /// Single-pass: applies both hyphenation and paragraph indentation.
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
    } catch (e) {
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

    if (hyphenation) await init();

    return processHtmlAndIndent(
      html,
      applyHyphenation: hyphenation,
      applyIndent: paragraphIndent,
    );
  }

  static void _processNode(dom.Node? node) {
    if (node == null) return;

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        // Hyphenate text content
        node.text = _hyphenator!.hyphenateText(text);
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNode(child);
      }
    }
  }

  /// Single-pass traversal: hyphenates text nodes and indents paragraphs.
  static void _processNodeHyphenateAndIndent(
    dom.Node? node, {
    required bool applyHyphenation,
    required bool applyIndent,
  }) {
    if (node == null) return;

    // If this is a <p> tag and indent is enabled, indent it
    if (applyIndent &&
        node is dom.Element &&
        node.localName == 'p' &&
        !_isAlignedParagraph(node)) {
      _indentFirstTextNode(node);
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.trim().isNotEmpty && applyHyphenation) {
        node.text = _hyphenator!.hyphenateText(text);
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

  static bool _isAlignedParagraph(dom.Element p) {
    final align = p.attributes['align']?.toLowerCase();
    final style = p.attributes['style']?.toLowerCase();
    return align == 'center' ||
        align == 'right' ||
        (style != null &&
            (style.contains('text-align: center') ||
                style.contains('text-align: right')));
  }

  static void _indentFirstTextNode(dom.Node node) {
    if (node.nodes.isEmpty) return;
    final firstChild = node.nodes.first;
    if (firstChild.nodeType == dom.Node.TEXT_NODE) {
      final text = firstChild.text;
      if (text != null && !text.startsWith('    ')) {
        firstChild.text = '    $text';
      }
    } else {
      _indentFirstTextNode(firstChild);
    }
  }
}
