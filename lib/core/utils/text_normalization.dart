String normalizePlainText(String text) {
  return text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u200B', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
