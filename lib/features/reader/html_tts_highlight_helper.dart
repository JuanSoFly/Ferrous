import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:ferrous/core/utils/dom_text_utils.dart';
import 'package:ferrous/core/services/diagnostic_logger.dart';

class _TextNodeInfo {
  final dom.Text node;
  final String nodeText;
  final List<int> cleanToProcessed;
  final String cleanText;
  final int nodeStart;
  final int nodeEnd;

  _TextNodeInfo({
    required this.node,
    required this.nodeText,
    required this.cleanToProcessed,
    required this.cleanText,
    required this.nodeStart,
    required this.nodeEnd,
  });
}

/// Centralized helper for injecting TTS highlights into HTML DOM structures.
/// Guarantees whole-word highlighting and prevents word clipping or partial fragments.
class HtmlTtsHighlightHelper {
  static const String ttsHighlightTag = 'tts-highlight';

  static final RegExp _wordCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWordChar(String char) => _wordCharRegex.hasMatch(char);

  static bool _isInternalConnector(String char) {
    return char == "'" || char == '’' || char == '‘' || char == '-' || char == '\u2011';
  }

  static bool _isWordBoundary(String text, int start, int length) {
    if (start > 0) {
      if (_isWordChar(text[start - 1])) return false;
      if (start > 1 && _isInternalConnector(text[start - 1]) && _isWordChar(text[start - 2])) {
        return false;
      }
    }
    final end = start + length;
    if (end < text.length) {
      if (_isWordChar(text[end])) return false;
      if (end + 1 < text.length && _isInternalConnector(text[end]) && _isWordChar(text[end + 1])) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesWord(String a, String b) {
    if (a.toLowerCase() == b.toLowerCase()) return true;
    final normA = a.toLowerCase().replaceAll('’', "'").replaceAll('‘', "'");
    final normB = b.toLowerCase().replaceAll('’', "'").replaceAll('‘', "'");
    return normA == normB;
  }

  static int _findWholeWordMatch(String text, String query, {int preferredPos = 0}) {
    if (query.isEmpty || text.isEmpty || query.length > text.length) return -1;
    int bestIdx = -1;
    int bestDist = 1 << 30;

    for (var i = 0; i + query.length <= text.length; i++) {
      if (_matchesWord(text.substring(i, i + query.length), query) &&
          _isWordBoundary(text, i, query.length)) {
        final dist = (i - preferredPos).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = i;
        }
      }
    }
    return bestIdx;
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

    final nodeInfos = <_TextNodeInfo>[];
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

      final cleanText = cleanToProcessed.map((i) => nodeText[i]).join();
      nodeInfos.add(_TextNodeInfo(
        node: node,
        nodeText: nodeText,
        cleanToProcessed: cleanToProcessed,
        cleanText: cleanText,
        nodeStart: nodeStart,
        nodeEnd: nodeEnd,
      ));
    }

    int targetIdx = -1;
    for (var i = 0; i < nodeInfos.length; i++) {
      final info = nodeInfos[i];
      if (info.node.parent == null || info.cleanToProcessed.isEmpty) continue;
      if (rawEnd > info.nodeStart && rawStart < info.nodeEnd) {
        targetIdx = i;
        break;
      }
    }

    if (targetIdx == -1) {
      int minDiff = 1 << 30;
      for (var i = 0; i < nodeInfos.length; i++) {
        final info = nodeInfos[i];
        if (info.node.parent == null || info.cleanToProcessed.isEmpty) continue;
        final diff = (info.nodeStart - rawStart).abs();
        if (diff < minDiff) {
          minDiff = diff;
          targetIdx = i;
        }
      }
    }

    if (targetIdx == -1) return html;

    _TextNodeInfo activeInfo = nodeInfos[targetIdx];
    int exactCleanStart = (rawStart - activeInfo.nodeStart).clamp(0, activeInfo.cleanToProcessed.length);
    int exactCleanEnd = (rawEnd - activeInfo.nodeStart).clamp(0, activeInfo.cleanToProcessed.length);
    int matchIdx = -1;

    // Search for query with strict word boundary enforcement
    if (query != null && query.isNotEmpty) {
      final cleanText = activeInfo.cleanText;

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
          matchIdx = _findWholeWordMatch(cleanText, query, preferredPos: exactCleanStart);
        }
      }

      // If query not found in initially overlapping text node, check adjacent text nodes
      if (matchIdx < 0) {
        int prevMatch = -1;
        int prevIdx = -1;
        if (targetIdx > 0) {
          for (var i = targetIdx - 1; i >= 0; i--) {
            if (nodeInfos[i].node.parent != null && nodeInfos[i].cleanToProcessed.isNotEmpty) {
              prevIdx = i;
              prevMatch = _findWholeWordMatch(
                nodeInfos[i].cleanText,
                query,
                preferredPos: nodeInfos[i].cleanText.length - query.length,
              );
              break;
            }
          }
        }

        int nextMatch = -1;
        int nextIdx = -1;
        if (targetIdx + 1 < nodeInfos.length) {
          for (var i = targetIdx + 1; i < nodeInfos.length; i++) {
            if (nodeInfos[i].node.parent != null && nodeInfos[i].cleanToProcessed.isNotEmpty) {
              nextIdx = i;
              nextMatch = _findWholeWordMatch(
                nodeInfos[i].cleanText,
                query,
                preferredPos: 0,
              );
              break;
            }
          }
        }

        if (prevMatch >= 0 && nextMatch >= 0) {
          final prevDist = (rawStart - (nodeInfos[prevIdx].nodeStart + prevMatch)).abs();
          final nextDist = ((nodeInfos[nextIdx].nodeStart + nextMatch) - rawStart).abs();
          if (prevDist <= nextDist) {
            activeInfo = nodeInfos[prevIdx];
            matchIdx = prevMatch;
          } else {
            activeInfo = nodeInfos[nextIdx];
            matchIdx = nextMatch;
          }
        } else if (prevMatch >= 0) {
          activeInfo = nodeInfos[prevIdx];
          matchIdx = prevMatch;
        } else if (nextMatch >= 0) {
          activeInfo = nodeInfos[nextIdx];
          matchIdx = nextMatch;
        }
      }

      if (matchIdx >= 0) {
        exactCleanStart = matchIdx;
        exactCleanEnd = matchIdx + query.length;
      }
    }

    // If query was not found or not provided: snap to whole word boundaries around exactCleanStart
    if (matchIdx < 0) {
      final cleanText = activeInfo.cleanText;
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
        while (s > 0) {
          if (_isWordChar(cleanText[s - 1])) {
            s--;
          } else if (s > 1 && _isInternalConnector(cleanText[s - 1]) && _isWordChar(cleanText[s - 2])) {
            s -= 2;
          } else {
            break;
          }
        }
        var e = wStart;
        while (e < cleanText.length) {
          if (_isWordChar(cleanText[e])) {
            e++;
          } else if (e + 1 < cleanText.length && _isInternalConnector(cleanText[e]) && _isWordChar(cleanText[e + 1])) {
            e += 2;
          } else {
            break;
          }
        }
        exactCleanStart = s;
        exactCleanEnd = e;
      } else {
        exactCleanStart = (rawStart - activeInfo.nodeStart).clamp(0, activeInfo.cleanToProcessed.length);
        exactCleanEnd = (rawEnd - activeInfo.nodeStart).clamp(exactCleanStart + 1, activeInfo.cleanToProcessed.length);
      }
    }

    if (exactCleanStart >= exactCleanEnd) return html;

    // Map clean indices back to processed indices in nodeText
    final nodeText = activeInfo.nodeText;
    final cleanToProcessed = activeInfo.cleanToProcessed;
    final localStart = exactCleanStart < cleanToProcessed.length
        ? cleanToProcessed[exactCleanStart]
        : nodeText.length;
    final localEnd = exactCleanEnd < cleanToProcessed.length
        ? cleanToProcessed[exactCleanEnd]
        : (cleanToProcessed.isNotEmpty ? cleanToProcessed.last + 1 : nodeText.length);

    if (localStart >= localEnd) return html;

    final before = nodeText.substring(0, localStart);
    final mid = nodeText.substring(localStart, localEnd);
    final after = nodeText.substring(localEnd);

    final parent = activeInfo.node.parent;
    if (parent == null) return html;

    final index = parent.nodes.indexOf(activeInfo.node);
    if (index < 0) return html;

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

    final hasHeadContent = document.head != null && document.head!.nodes.isNotEmpty;
    final hasDocEnvelope = html.contains(RegExp(r'<!doctype|<html|<head', caseSensitive: false));

    if (hasHeadContent || hasDocEnvelope) {
      return document.outerHtml;
    }

    return root.outerHtml;
  }
}
