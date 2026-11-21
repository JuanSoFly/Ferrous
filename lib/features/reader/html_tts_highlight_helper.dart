import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:ferrous/core/utils/dom_text_utils.dart';
import 'package:ferrous/core/services/diagnostic_logger.dart';

/// Centralized helper for injecting TTS highlights into HTML DOM structures.
/// Guarantees whole-word highlighting and prevents word clipping or partial fragments.
class HtmlTtsHighlightHelper {
  static const String ttsHighlightTag = 'tts-highlight';

  static final RegExp _wordCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWordChar(String char) => _wordCharRegex.hasMatch(char);

  static bool _isWordBoundary(String text, int start, int length) {
    if (start > 0 && _isWordChar(text[start - 1])) return false;
    final end = start + length;
    if (end < text.length && _isWordChar(text[end])) return false;
    return true;
  }

  static bool _matchesWord(String a, String b) {
    if (a.toLowerCase() == b.toLowerCase()) return true;
    final normA = a.toLowerCase().replaceAll('’', "'").replaceAll('‘', "'");
    final normB = b.toLowerCase().replaceAll('’', "'").replaceAll('‘', "'");
    return normA == normB;
  }

  static int findWordEnd(String text, int start) {
    var end = start;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    return end;
  }

  /// Resolves the true expected word being spoken.
  static String? resolveExpectedWord({
    String? ttsServiceWord,
    String? chapterPlainText,
    int? chapterRawStart,
    int? chapterRawEnd,
  }) {
    final ttsWord = ttsServiceWord?.trim();
    if (ttsWord != null && ttsWord.isNotEmpty) {
      return ttsWord;
    }
    if (chapterPlainText != null &&
        chapterRawStart != null &&
        chapterRawStart >= 0 &&
        chapterRawStart < chapterPlainText.length) {
      final safeEnd = (chapterRawEnd != null &&
              chapterRawEnd > chapterRawStart &&
              chapterRawEnd <= chapterPlainText.length)
          ? chapterRawEnd
          : findWordEnd(chapterPlainText, chapterRawStart);
      final candidate = chapterPlainText.substring(chapterRawStart, safeEnd).trim();
      if (candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  /// Injects `<tts-highlight>` around the target word at [rawStart..rawEnd] in [html].
  static String buildHighlightedHtml({
    required String html,
    required int rawStart,
    required int rawEnd,
    String? expectedWord,
  }) {
    if (rawStart < 0 || rawEnd <= rawStart) return html;

    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final textNodes = DomTextUtils.collectTextNodes(root);
    if (textNodes.isEmpty) return html;

    final strippedWord = expectedWord?.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
      '',
    );
    final query = (strippedWord != null && strippedWord.isNotEmpty)
        ? strippedWord
        : expectedWord;

    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;

      // Build mapping from clean index to processed index
      final cleanToProcessed = <int>[];
      int processedIdx = 0;
      int indentLen = 0;

      // Skip leading paragraph indent characters (em-spaces U+2003 or non-breaking spaces U+00A0)
      while (processedIdx < nodeText.length) {
        final cu = nodeText.codeUnitAt(processedIdx);
        if (cu == 0x2003 || cu == 0x00A0) {
          processedIdx++;
          indentLen++;
        } else {
          break;
        }
      }

      while (processedIdx < nodeText.length) {
        final codeUnit = nodeText.codeUnitAt(processedIdx);
        if (codeUnit == 0x00AD || codeUnit == 0x200B) {
          processedIdx++;
          continue;
        }
        cleanToProcessed.add(processedIdx);
        processedIdx++;
      }

      final nodeStart = offset;
      final rawEquivalentLen = cleanToProcessed.length + (indentLen > 0 ? 1 : 0);
      final nodeEnd = offset + rawEquivalentLen;
      offset = nodeEnd;

      // Skip nodes that don't overlap with highlight range
      if (rawEnd <= nodeStart || rawStart >= nodeEnd) continue;

      // Skip synthetic nodes (block separators)
      if (node.parent == null) continue;

      int exactCleanStart = (rawStart - nodeStart).clamp(0, cleanToProcessed.length);
      int exactCleanEnd = (rawEnd - nodeStart).clamp(0, cleanToProcessed.length);

      if (cleanToProcessed.isEmpty) continue;
      final cleanText = cleanToProcessed.map((i) => nodeText[i]).join();

      int matchIdx = -1;

      // Search for query with strict word boundary enforcement
      if (query != null && query.isNotEmpty) {
        // 1. Check exact position first
        if (exactCleanStart + query.length <= cleanText.length &&
            _matchesWord(cleanText.substring(exactCleanStart, exactCleanStart + query.length), query) &&
            _isWordBoundary(cleanText, exactCleanStart, query.length)) {
          matchIdx = exactCleanStart;
        } else {
          // 2. Search backwards in small window
          for (var delta = -1; delta >= -8; delta--) {
            final testPos = exactCleanStart + delta;
            if (testPos >= 0 && testPos + query.length <= cleanText.length) {
              if (_matchesWord(cleanText.substring(testPos, testPos + query.length), query) &&
                  _isWordBoundary(cleanText, testPos, query.length)) {
                matchIdx = testPos;
                break;
              }
            }
          }

          // 3. Search forwards in small window
          if (matchIdx < 0) {
            for (var delta = 1; delta <= 8; delta++) {
              final testPos = exactCleanStart + delta;
              if (testPos >= 0 && testPos + query.length <= cleanText.length) {
                if (_matchesWord(cleanText.substring(testPos, testPos + query.length), query) &&
                    _isWordBoundary(cleanText, testPos, query.length)) {
                  matchIdx = testPos;
                  break;
                }
              }
            }
          }

          // 4. Broader search for nearest whole-word match in the entire node
          if (matchIdx < 0) {
            int bestDistance = 1 << 30;
            for (var i = 0; i + query.length <= cleanText.length; i++) {
              if (_matchesWord(cleanText.substring(i, i + query.length), query) &&
                  _isWordBoundary(cleanText, i, query.length)) {
                final dist = (i - exactCleanStart).abs();
                if (dist < bestDistance) {
                  bestDistance = dist;
                  matchIdx = i;
                }
              }
            }
          }
        }

        if (matchIdx >= 0) {
          exactCleanStart = matchIdx;
          exactCleanEnd = matchIdx + query.length;
        }
      }

      // If query was not found or not provided: snap to whole word boundaries around exactCleanStart
      if (matchIdx < 0) {
        int wStart = exactCleanStart.clamp(0, cleanText.length);
        if (wStart < cleanText.length && !_isWordChar(cleanText[wStart])) {
          // If on whitespace or punctuation, find closest adjacent word character
          for (var d = 1; d <= 4; d++) {
            if (wStart + d < cleanText.length && _isWordChar(cleanText[wStart + d])) {
              wStart += d;
              break;
            } else if (wStart - d >= 0 && _isWordChar(cleanText[wStart - d])) {
              wStart -= d;
              break;
            }
          }
        }

        if (wStart < cleanText.length && _isWordChar(cleanText[wStart])) {
          var s = wStart;
          while (s > 0 && _isWordChar(cleanText[s - 1])) {
            s--;
          }
          var e = wStart;
          while (e < cleanText.length && _isWordChar(cleanText[e])) {
            e++;
          }
          exactCleanStart = s;
          exactCleanEnd = e;
        } else {
          exactCleanStart = (rawStart - nodeStart).clamp(0, cleanToProcessed.length);
          exactCleanEnd = (rawEnd - nodeStart).clamp(exactCleanStart + 1, cleanToProcessed.length);
        }
      }

      if (exactCleanStart >= exactCleanEnd) continue;

      // Map clean indices back to processed indices in nodeText
      final localStart = exactCleanStart < cleanToProcessed.length
          ? cleanToProcessed[exactCleanStart]
          : nodeText.length;
      final localEnd = exactCleanEnd < cleanToProcessed.length
          ? cleanToProcessed[exactCleanEnd]
          : (cleanToProcessed.isNotEmpty ? cleanToProcessed.last + 1 : nodeText.length);

      if (localStart >= localEnd) continue;

      final before = nodeText.substring(0, localStart);
      final mid = nodeText.substring(localStart, localEnd);
      final after = nodeText.substring(localEnd);

      final parent = node.parent;
      if (parent == null) continue;

      final index = parent.nodes.indexOf(node);
      if (index < 0) continue;

      final newNodes = <dom.Node>[];
      if (before.isNotEmpty) newNodes.add(dom.Text(before));
      if (mid.isNotEmpty) {
        final mark = dom.Element.tag(ttsHighlightTag);
        mark.append(dom.Text(mid));
        newNodes.add(mark);
      }
      if (after.isNotEmpty) newNodes.add(dom.Text(after));

      parent.nodes.removeAt(index);
      parent.nodes.insertAll(index, newNodes);

      DiagnosticLogger.instance.log(
        'TTS::Highlight',
        'Injected highlight for "${mid.trim()}" at clean [$exactCleanStart..$exactCleanEnd]',
      );

      // Successfully highlighted target word
      break;
    }

    return root.outerHtml;
  }
}
