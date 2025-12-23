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
      _hyphenator = await Hyphenator.loadAsyncByAbbr('en_us', symbol: '\u00AD');
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

  /*
  static void _processNode(dom.Node? node) {
    if (node == null) return;

    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text != null && text.trim().isNotEmpty) {
        // Only hyphenate words to avoid breaking HTML entities or causing issues
        // But HyphenatorX usually handles text well. 
        // We rely on it returning text with soft hyphens.
        // Warning: Re-hyphenating already hyphenated text?
        // Hyphenator usually ignores soft hyphens present?
        // Let's assume input is clean from previous passes or we just overwrite.
        node.text = _hyphenator!.hyphenate(text);
      }
    } else if (node.hasChildNodes()) {
      for (final child in node.nodes) {
        _processNode(child);
      }
    }
  }
  */
}
