/// Normalize plain text by collapsing whitespace and removing zero-width characters.
/// 
/// This is extracted from identical implementations in pdf_reader.dart and epub_reader.dart.
/// - Replaces non-breaking spaces (\\u00A0) with regular spaces
/// - Removes zero-width spaces (\\u200B)
/// - Collapses multiple whitespace characters into single spaces
/// - Trims leading/trailing whitespace
String normalizePlainText(String text) {
  return text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u200B', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
