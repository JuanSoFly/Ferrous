/// Utility to normalize XHTML/XML self-closing tags into canonical HTML5 syntax
/// before parsing with `package:html` (which adheres to HTML5 parsing rules).
class XmlHtmlNormalizer {
  static const Set<String> _voidElements = {
    'area',
    'base',
    'br',
    'col',
    'command',
    'embed',
    'hr',
    'img',
    'input',
    'keygen',
    'link',
    'menuitem',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };

  // Matches standard, hyphenated, and namespaced self-closing tags.
  // Correctly handles whitespace around '=', boolean attributes, and quoted strings containing '>'.
  static final RegExp _selfClosingTagRegex = RegExp(
    r'<([a-zA-Z][a-zA-Z0-9:-]*)((?:\s+[^\s>"\x27=/]+(?:\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s"\x27=<>`]+))?)*)\s*/>',
  );

  /// Converts self-closing XML tags into canonical HTML5 syntax:
  /// - Non-void tags: `<a id="foo"/>` -> `<a id="foo"></a>`
  /// - Void tags: `<br/>` -> `<br>` (stripping `/>` ensures downstream `contains('/>')` fast-paths evaluate to false)
  static String normalizeXmlSelfClosingTags(String html) {
    if (!html.contains('/>')) return html;
    return html.replaceAllMapped(_selfClosingTagRegex, (match) {
      final rawTag = match.group(1)!;
      final tagLower = rawTag.toLowerCase();
      final attrs = match.group(2) ?? '';
      if (_voidElements.contains(tagLower)) {
        return '<$rawTag$attrs>';
      }
      return '<$rawTag$attrs></$rawTag>';
    });
  }
}
