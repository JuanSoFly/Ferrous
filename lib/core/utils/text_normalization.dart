import 'package:reader_app/core/utils/html_defragmenter.dart';

String normalizePlainText(String text) {
  // First heal replacement characters identically to the DOM pipeline
  // to preserve exact character offset alignment for search and accurate TTS pronunciation.
  final healed = HtmlDefragmenter.healReplacementCharacters(text);

  return healed
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u200B', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
