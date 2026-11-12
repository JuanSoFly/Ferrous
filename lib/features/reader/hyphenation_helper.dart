import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';
import 'package:reader_app/core/utils/html_defragmenter.dart';

class HyphenationHelper {
  static const String softHyphen = '\u00AD';
  static const String indentTag = 'p-indent';

  static Hyphenator? _hyphenator;

  /// Returns the Hyphenator instance, lazily and synchronously initialized.
  static Hyphenator get hyphenator {
    return _hyphenator ??= Hyphenator(
      Language_en_us(),
      symbol: softHyphen,
    );
  }

  /// Strips \u00AD and &shy; unconditionally so words never break
  /// across lines without a visible hyphen glyph on Android SkParagraph.
  static String smartHyphenateText(String text) {
    if (text.isEmpty) return text;

    var clean = text;
    if (clean.contains('\u00AD')) {
      clean = clean.replaceAll('\u00AD', '');
    }
    if (clean.contains('&shy;')) {
      clean = clean.replaceAll('&shy;', '');
    }

    return clean;
  }

  /// Initialize the hyphenator synchronously. Returns a `Future<void>` so existing callers
  /// can continue to call `await HyphenationHelper.init()` without breaking.
  static Future<void> init() async {
    _hyphenator ??= Hyphenator(
      Language_en_us(),
      symbol: softHyphen,
    );
  }

  /// Injects `<p-indent></p-indent>` tags into all paragraph elements.
  static String injectIndentTags(String html) {
    if (html.isEmpty) return html;
    try {
      final document = html_parser.parse(html);
      HtmlDefragmenter.defragmentDocument(document);
      final body = document.body ?? document.documentElement;
      if (body == null) return html;
      _injectIndentTagsRecursive(body);
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  static void _injectIndentTagsRecursive(dom.Node node) {
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if ({'pre', 'code', 'script', 'style', 'tt'}.contains(tag)) {
        return;
      }
      if (_isParagraphElement(node)) {
        _indentParagraph(node);
      }
    }
    if (node.hasChildNodes()) {
      for (final child in List<dom.Node>.from(node.nodes)) {
        _injectIndentTagsRecursive(child);
      }
    }
  }

  /// Process HTML for hyphenation only.
  static String processHtml(String html, {bool applyHyphenation = false}) {
    try {
      final document = html_parser.parse(html);
      _processNode(document.body, applyHyphenation: applyHyphenation);
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Entry point for compute() isolate - hyphenation only.
  static Future<String> processHtmlIsolated(String html, {bool applyHyphenation = false}) async {
    return processHtml(html, applyHyphenation: applyHyphenation);
  }

  /// Single-pass: applies hyphenation, paragraph indentation, or both.
  /// [html] - raw HTML content
  /// [applyHyphenation] - whether to hyphenate text nodes
  /// [applyIndent] - whether to add paragraph indentation
  static String processHtmlAndIndent(
    String html, {
    bool applyHyphenation = false,
    bool applyIndent = true,
  }) {
    if (!applyHyphenation &&
        !applyIndent &&
        !html.contains('<p-indent') &&
        !html.contains('\u00AD') &&
        !html.contains('  ')) {
      return html;
    }

    try {
      final document = html_parser.parse(html);
      HtmlDefragmenter.defragmentDocument(document);
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
  static void _processNode(dom.Node? node, {bool applyHyphenation = false}) {
    if (node == null) return;

    if (node is dom.Element &&
        {'pre', 'code', 'script', 'style', 'tt'}.contains(node.localName?.toLowerCase())) {
      return;
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      var text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        text = smartHyphenateText(text);
        node.text = text;
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNode(child, applyHyphenation: applyHyphenation);
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

    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if ({'pre', 'code', 'script', 'style', 'tt'}.contains(tag)) {
        return;
      }

      if (_isParagraphElement(node)) {
        if (applyIndent) {
          _indentParagraph(node);
        } else {
          _removeIndentFromParagraph(node);
        }
      }
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      var text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        text = smartHyphenateText(text);
        if (text.contains('  ') || text.contains('\t')) {
          text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
        }
        node.text = text;
      }
    } else if (node.hasChildNodes()) {
      for (final child in List<dom.Node>.from(node.nodes)) {
        _processNodeHyphenateAndIndent(
          child,
          applyHyphenation: applyHyphenation,
          applyIndent: applyIndent,
        );
      }
    }
  }

  /// Determines whether an element represents a normal reading paragraph.
  static bool _isParagraphElement(dom.Element el) {
    final tag = el.localName?.toLowerCase();
    if (tag == null) return false;

    if ({
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'pre', 'code', 'table', 'th', 'td',
      'ul', 'ol', 'li', 'blockquote', 'caption',
      'p-indent', 'indent', 'annotation-highlight', 'tts-highlight'
    }.contains(tag)) {
      return false;
    }

    if (_isAlignedParagraph(el)) {
      return false;
    }

    final text = el.text.trim();
    if (text.isEmpty) return false;

    if (tag == 'p') {
      final hasOnlyImages = el.nodes.every((n) =>
          (n is dom.Element && {'img', 'svg', 'image', 'picture'}.contains(n.localName?.toLowerCase())) ||
          (n is dom.Text && n.text.trim().isEmpty));
      return !hasOnlyImages;
    }

    if (tag == 'div' || tag == 'section') {
      final hasChildParagraphs = el.querySelector('p') != null;
      if (hasChildParagraphs) return false;

      final hasOnlyImages = el.nodes.every((n) =>
          (n is dom.Element && {'img', 'svg', 'image', 'picture'}.contains(n.localName?.toLowerCase())) ||
          (n is dom.Text && n.text.trim().isEmpty));
      if (hasOnlyImages) return false;

      final isExplicitPara = el.classes.any((c) {
        final cl = c.toLowerCase();
        return cl.contains('para') || cl.contains('calibre') || cl == 'p' || cl == 'text' || cl == 'story' || cl == 'body';
      });

      return isExplicitPara || text.length > 20;
    }

    return false;
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

  /// Indents a paragraph by inserting a `<p-indent></p-indent>` element as the first child.
  static void _indentParagraph(dom.Element p) {
    if (p.children.isNotEmpty && p.children.first.localName == 'p-indent') {
      return;
    }
    // Remove any leading empty text nodes before inserting indent
    while (p.nodes.isNotEmpty && p.nodes.first is dom.Text && p.nodes.first.text!.trim().isEmpty) {
      p.nodes.removeAt(0);
    }
    p.nodes.insert(0, dom.Element.tag('p-indent'));
  }

  /// Removes `<p-indent>` tags from a paragraph.
  static void _removeIndentFromParagraph(dom.Element p) {
    p.nodes.removeWhere((node) => node is dom.Element && (node.localName == 'p-indent' || node.localName == 'indent'));
  }
}
