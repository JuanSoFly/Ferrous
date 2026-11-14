import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';
import 'package:ferrous/core/utils/html_defragmenter.dart';

class HyphenationHelper {
  static const String softHyphen = '\u00AD';
  static const String continuationHyphen = '\u2010';
  static const String indentTag = 'p-indent';
  static final RegExp _wordRegex = RegExp(r'\p{L}+', unicode: true);

  static final Map<String, Hyphenator> _hyphenatorCache = {};

  /// Exact mapping of normalized primary language codes to hyphenatorx asset abbreviations.
  static const Map<String, String> _langToAbbr = {
    'de': 'de_1996',
    'en': 'en_us',
    'es': 'es',
    'fr': 'fr',
    'it': 'it',
    'la': 'la',
    'pt': 'pt',
    'ru': 'ru',
  };

  /// Returns synchronous hyphenator. If language is not warmed yet, safely returns English
  /// while preventing unhandled exceptions.
  static Hyphenator getHyphenator([String languageCode = 'en']) {
    final primary = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    final cached = _hyphenatorCache[primary];
    if (cached != null) return cached;
    return _hyphenatorCache.putIfAbsent(
      'en',
      () => Hyphenator(
        Language_en_us(),
        symbol: softHyphen,
        minWordLength: 7,
        minLetterCount: 3,
      ),
    );
  }

  static Hyphenator get hyphenator => getHyphenator('en');

  /// Pre-warms language hyphenator from bundled JSON asset without ANY static Dart dictionary codegen.
  static Future<void> init([String languageCode = 'en']) async {
    final primary = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    if (_hyphenatorCache.containsKey(primary)) return;

    if (primary == 'en') {
      getHyphenator('en');
      return;
    }

    final abbr = _langToAbbr[primary] ?? primary;
    try {
      final h = await Hyphenator.loadAsyncByAbbr(
        abbr,
        symbol: softHyphen,
        minWordLength: 7,
        minLetterCount: 3,
      );
      _hyphenatorCache[primary] = h;
    } catch (_) {
      // Fallback safely to English rules if language JSON is unavailable
      _hyphenatorCache[primary] = getHyphenator('en');
    }
  }

  /// Strips \u00AD and &shy; unconditionally without touching \u2010.
  static String stripSoftHyphens(String text) {
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

  /// Applies smart hyphenation to text:
  /// - Only words of length >= 7 are considered.
  /// - Non-German: skips words with any uppercase character (proper nouns, CamelCase, acronyms).
  /// - German: allows leading uppercase (nouns), but requires subsequent letters to be lowercase.
  /// - Words with numbers or symbols are untouched.
  /// - Inserts \u00AD soft hyphen using Liang's hyphenation algorithm via hyphenatorx.
  static String smartHyphenateText(
    String text, {
    bool applyHyphenation = false,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) {
    if (text.isEmpty) return text;

    final clean = preserveExistingHyphens ? text : stripSoftHyphens(text);
    if (!applyHyphenation || clean.length < 7) {
      return clean;
    }

    final primaryLang = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    final h = getHyphenator(primaryLang);

    return clean.replaceAllMapped(_wordRegex, (match) {
      final word = match[0]!;
      if (word.length < 7) return word;

      if (primaryLang != 'de') {
        if (word != word.toLowerCase()) return word;
      } else {
        if (word.length > 1 && word.substring(1) != word.substring(1).toLowerCase()) {
          return word;
        }
      }

      try {
        return h.hyphenateWord(word);
      } catch (_) {
        return word;
      }
    });
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
      if ({'pre', 'code', 'script', 'style', 'tt', 'kbd', 'samp', 'var', 'a'}.contains(tag)) {
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
  static String processHtml(
    String html, {
    bool applyHyphenation = false,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) {
    try {
      final document = html_parser.parse(html);
      _processNode(
        document.body,
        applyHyphenation: applyHyphenation,
        languageCode: languageCode,
        preserveExistingHyphens: preserveExistingHyphens,
      );
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Entry point for compute() isolate - hyphenation only.
  static Future<String> processHtmlIsolated(
    String html, {
    bool applyHyphenation = false,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) async {
    return processHtml(
      html,
      applyHyphenation: applyHyphenation,
      languageCode: languageCode,
      preserveExistingHyphens: preserveExistingHyphens,
    );
  }

  /// Single-pass processing on a DOM element (or cloned element):
  /// - Injects or removes paragraph indentation tags (`<p-indent>`)
  /// - Hyphenates or cleans text nodes
  /// - Traverses children while respecting non-prose tag exclusion rules
  static void processElement(
    dom.Element element, {
    bool applyHyphenation = false,
    bool applyIndent = true,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) {
    _processNodeHyphenateAndIndent(
      element,
      applyHyphenation: applyHyphenation,
      applyIndent: applyIndent,
      languageCode: languageCode,
      preserveExistingHyphens: preserveExistingHyphens,
    );
  }

  /// Single-pass: applies hyphenation, paragraph indentation, or both.
  static String processHtmlAndIndent(
    String html, {
    bool applyHyphenation = false,
    bool applyIndent = true,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
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
      if (!preserveExistingHyphens) {
        HtmlDefragmenter.defragmentDocument(document);
      }
      final body = document.body ?? document.documentElement;
      if (body != null) {
        _processNodeHyphenateAndIndent(
          body,
          applyHyphenation: applyHyphenation,
          applyIndent: applyIndent,
          languageCode: languageCode,
          preserveExistingHyphens: preserveExistingHyphens,
        );
      }
      return document.body?.innerHtml ?? html;
    } catch (_) {
      return html;
    }
  }

  /// Entry point for compute() isolate - combined hyphenation + indentation.
  static Future<String> processHtmlAndIndentIsolated(
    Map<String, dynamic> params,
  ) async {
    final html = params['html'] as String;
    final hyphenation = params['hyphenation'] as bool? ?? false;
    final paragraphIndent = params['paragraphIndent'] as bool? ?? false;
    final languageCode = params['languageCode'] as String? ?? 'en';
    final preserveExistingHyphens = params['preserveExistingHyphens'] as bool? ?? false;

    return processHtmlAndIndent(
      html,
      applyHyphenation: hyphenation,
      applyIndent: paragraphIndent,
      languageCode: languageCode,
      preserveExistingHyphens: preserveExistingHyphens,
    );
  }

  static void _processNode(
    dom.Node? node, {
    bool applyHyphenation = false,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) {
    if (node == null) return;

    if (node is dom.Element &&
        {'pre', 'code', 'script', 'style', 'tt', 'kbd', 'samp', 'var', 'a'}.contains(node.localName?.toLowerCase())) {
      return;
    }

    if (node.nodeType == dom.Node.TEXT_NODE) {
      var text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        text = smartHyphenateText(
          text,
          applyHyphenation: applyHyphenation,
          languageCode: languageCode,
          preserveExistingHyphens: preserveExistingHyphens,
        );
        node.text = text;
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNode(
          child,
          applyHyphenation: applyHyphenation,
          languageCode: languageCode,
          preserveExistingHyphens: preserveExistingHyphens,
        );
      }
    }
  }

  /// Single-pass traversal: indents paragraphs and hyphenates text nodes.
  static void _processNodeHyphenateAndIndent(
    dom.Node? node, {
    required bool applyHyphenation,
    required bool applyIndent,
    String languageCode = 'en',
    bool preserveExistingHyphens = false,
  }) {
    if (node == null) return;

    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if ({'pre', 'code', 'script', 'style', 'tt', 'kbd', 'samp', 'var', 'a'}.contains(tag)) {
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
        text = smartHyphenateText(
          text,
          applyHyphenation: applyHyphenation,
          languageCode: languageCode,
          preserveExistingHyphens: preserveExistingHyphens,
        );
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
          languageCode: languageCode,
          preserveExistingHyphens: preserveExistingHyphens,
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
    if (p.classes.contains('page-continuation') ||
        (p.attributes['style'] ?? '').contains('text-indent: 0') ||
        (p.attributes['style'] ?? '').contains('text-indent:0')) {
      return;
    }
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
