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
  final int indentLen;
  final bool isBlockSeparator;

  _TextNodeInfo({
    required this.node,
    required this.nodeText,
    required this.cleanToProcessed,
    required this.cleanText,
    required this.nodeStart,
    required this.nodeEnd,
    required this.indentLen,
    required this.isBlockSeparator,
  });

  int get cleanStartOffset => nodeStart + indentLen;
}

class _MatchCandidate {
  final int nodeIndex;
  final int localStart;
  final int localEnd;
  final int domOffset;
  final int score;
  final int dist;

  _MatchCandidate({
    required this.nodeIndex,
    required this.localStart,
    required this.localEnd,
    required this.domOffset,
    required this.score,
    required this.dist,
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

  static int findWordEnd(String text, int start) {
    var end = start;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    return end;
  }

  static int _rewindToWordStart(String text, int pos) {
    var s = pos.clamp(0, text.length);
    while (s > 0) {
      if (_isWordChar(text[s - 1])) {
        s--;
      } else if (s > 1 && _isInternalConnector(text[s - 1]) && _isWordChar(text[s - 2])) {
        s -= 2;
      } else {
        break;
      }
    }
    return s;
  }

  static int _advanceToWordEnd(String text, int pos) {
    var e = pos.clamp(0, text.length);
    while (e < text.length) {
      if (_isWordChar(text[e])) {
        e++;
      } else if (e + 1 < text.length && _isInternalConnector(text[e]) && _isWordChar(text[e + 1])) {
        e += 2;
      } else {
        break;
      }
    }
    return e;
  }

  /// Extracts the word immediately preceding [start] in [text], ignoring trailing punctuation/spaces.
  static String? extractPrevWord(String text, int start, {int? sentenceStart}) {
    if (start <= 0 || text.isEmpty) return null;
    final minBound = (sentenceStart != null && sentenceStart >= 0) ? sentenceStart : 0;
    var curStart = start.clamp(0, text.length);
    if (curStart <= minBound) return null;

    // If start lands mid-word, snap outward to the beginning of the current word first
    if (curStart > 0 && curStart < text.length && _isWordChar(text[curStart]) && _isWordChar(text[curStart - 1])) {
      curStart = _rewindToWordStart(text, curStart);
    }

    var end = curStart;
    while (end > minBound && !_isWordChar(text[end - 1])) {
      end--;
    }
    if (end <= minBound) return null;

    var s = end;
    while (s > minBound) {
      if (_isWordChar(text[s - 1])) {
        s--;
      } else if (s - 1 > minBound && _isInternalConnector(text[s - 1]) && _isWordChar(text[s - 2])) {
        s -= 2;
      } else {
        break;
      }
    }
    if (s >= end) return null;
    final word = text.substring(s, end).trim();
    return word.isEmpty ? null : word;
  }

  /// Extracts the word immediately following [end] in [text], ignoring leading punctuation/spaces.
  /// If [end] lands mid-word, it snaps to the end of the word first.
  /// When [sentenceEnd] is provided, extraction will not cross beyond it.
  static String? extractNextWord(String text, int end, {int? sentenceEnd}) {
    if (end >= text.length || text.isEmpty) return null;
    final maxBound = (sentenceEnd != null && sentenceEnd <= text.length) ? sentenceEnd : text.length;
    var curEnd = end.clamp(0, text.length);
    if (curEnd >= maxBound) return null;

    // If end lands mid-word, snap outward to the end of the current word first
    if (curEnd > 0 && curEnd < text.length && _isWordChar(text[curEnd]) && _isWordChar(text[curEnd - 1])) {
      curEnd = _advanceToWordEnd(text, curEnd);
    }

    var start = curEnd;
    while (start < maxBound && !_isWordChar(text[start])) {
      start++;
    }
    if (start >= maxBound) return null;

    var e = start;
    while (e < maxBound) {
      if (_isWordChar(text[e])) {
        e++;
      } else if (e + 1 < maxBound && _isInternalConnector(text[e]) && _isWordChar(text[e + 1])) {
        e += 2;
      } else {
        break;
      }
    }
    if (e <= start) return null;
    final word = text.substring(start, e).trim();
    return word.isEmpty ? null : word;
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

  static String _normalizeText(String s) {
    final buf = StringBuffer();
    bool lastWasSpace = false;
    for (var i = 0; i < s.length; i++) {
      final cu = s.codeUnitAt(i);
      final ch = s[i];
      if (cu <= 0x20 || cu == 0x00A0 || cu == 0x2003 || cu == 0x3000) {
        if (!lastWasSpace && buf.isNotEmpty) {
          buf.write(' ');
          lastWasSpace = true;
        }
      } else {
        lastWasSpace = false;
        if (ch == '’' || ch == '‘') {
          buf.write('\'');
        } else if (ch == '“' || ch == '”') {
          buf.write('"');
        } else {
          buf.write(ch);
        }
      }
    }
    return buf.toString();
  }

  static ({int start, int end})? _findSentenceBounds({
    required String flatNorm,
    required List<int> normIdxToDomOffset,
    required int totalDomLen,
    required String sentenceText,
    int? sentenceLocalStart,
    int? sentenceLocalEnd,
    int? wordOffsetInSentence,
    int? minForwardDomOffset,
  }) {
    if (flatNorm.isEmpty || normIdxToDomOffset.isEmpty) return null;
    final normSentence = _normalizeText(sentenceText).toLowerCase().trim();
    if (normSentence.isEmpty) return null;

    final flatLower = flatNorm.toLowerCase();

    // 1. Exact sentence match search
    final occurrences = <int>[];
    var sIdx = 0;
    while (sIdx < flatLower.length) {
      final idx = flatLower.indexOf(normSentence, sIdx);
      if (idx < 0) break;
      occurrences.add(idx);
      sIdx = idx + 1;
    }

    if (occurrences.isNotEmpty) {
      int bestIdx = -1;
      int bestPenalty = 1 << 30;
      int bestDist = 1 << 30;

      for (final occ in occurrences) {
        final domStart = normIdxToDomOffset[occ];
        final endNormIdx = occ + normSentence.length - 1;
        final domEnd = endNormIdx < normIdxToDomOffset.length
            ? normIdxToDomOffset[endNormIdx] + 1
            : totalDomLen;

        int penalty = 0;
        if (minForwardDomOffset != null && domEnd < minForwardDomOffset) {
          penalty = 1000000;
        }

        final dist = sentenceLocalStart != null
            ? (domStart - sentenceLocalStart).abs()
            : 0;

        if (penalty < bestPenalty || (penalty == bestPenalty && dist < bestDist)) {
          bestPenalty = penalty;
          bestDist = dist;
          bestIdx = occ;
        }
      }

      if (bestIdx >= 0) {
        final domStart = normIdxToDomOffset[bestIdx];
        final endNormIdx = bestIdx + normSentence.length - 1;
        final domEnd = endNormIdx < normIdxToDomOffset.length
            ? normIdxToDomOffset[endNormIdx] + 1
            : totalDomLen;
        return (start: domStart, end: domEnd);
      }
    }

    // 2. Page-split sentence: started on previous page/slice (sentenceLocalStart < 0)
    if (sentenceLocalStart != null && sentenceLocalStart < 0) {
      for (var len = normSentence.length; len >= 8; len--) {
        final suffix = normSentence.substring(normSentence.length - len);
        final idx = flatLower.indexOf(suffix);
        if (idx >= 0 && idx <= 30) {
          final domStart = normIdxToDomOffset[idx];
          final endNormIdx = idx + suffix.length - 1;
          final domEnd = endNormIdx < normIdxToDomOffset.length
              ? normIdxToDomOffset[endNormIdx] + 1
              : totalDomLen;
          return (start: domStart, end: domEnd);
        }
      }
    }

    // 3. Page-split sentence: continues onto next page/slice (sentenceLocalEnd > totalDomLen)
    if (sentenceLocalEnd != null && sentenceLocalEnd > totalDomLen) {
      for (var len = normSentence.length; len >= 8; len--) {
        final prefix = normSentence.substring(0, len);
        final idx = flatLower.lastIndexOf(prefix);
        if (idx >= 0) {
          final domStart = normIdxToDomOffset[idx];
          if (sentenceLocalStart == null || (domStart - sentenceLocalStart).abs() < 120) {
            return (start: domStart, end: totalDomLen);
          }
        }
      }
    }

    // 4. Local 3-5 word window fallback around wordOffsetInSentence
    if (wordOffsetInSentence != null && wordOffsetInSentence >= 0 && wordOffsetInSentence < sentenceText.length) {
      var wStart = wordOffsetInSentence;
      for (var i = 0; i < 2; i++) {
        final prev = extractPrevWord(sentenceText, wStart);
        if (prev != null) {
          final idx = sentenceText.lastIndexOf(prev, (wStart - 1).clamp(0, sentenceText.length));
          if (idx >= 0) wStart = idx;
        }
      }
      var wEnd = wordOffsetInSentence;
      for (var i = 0; i < 2; i++) {
        final next = extractNextWord(sentenceText, wEnd);
        if (next != null) {
          final idx = sentenceText.indexOf(next, wEnd);
          if (idx >= 0) wEnd = idx + next.length;
        }
      }
      if (wEnd > wStart) {
        final windowText = _normalizeText(sentenceText.substring(wStart, wEnd)).toLowerCase().trim();
        if (windowText.isNotEmpty) {
          final winIdx = flatLower.indexOf(windowText);
          if (winIdx >= 0) {
            var bStart = winIdx;
            while (bStart > 0) {
              final ch = flatLower[bStart - 1];
              if (ch == '.' || ch == '?' || ch == '!' || ch == '\n') break;
              bStart--;
            }
            var bEnd = winIdx + windowText.length;
            while (bEnd < flatLower.length) {
              final ch = flatLower[bEnd];
              if (ch == '.' || ch == '?' || ch == '!' || ch == '\n') {
                bEnd++;
                break;
              }
              bEnd++;
            }
            final domStart = normIdxToDomOffset[bStart];
            final endIdx = (bEnd - 1).clamp(0, normIdxToDomOffset.length - 1);
            final domEnd = normIdxToDomOffset[endIdx] + 1;
            return (start: domStart, end: domEnd);
          }
        }
      }
    }

    return null;
  }

  /// Injects `<tts-highlight>` around the target word at [rawStart..rawEnd] in [html].
  static String buildHighlightedHtml({
    required String html,
    required int rawStart,
    required int rawEnd,
    String? expectedWord,
    String? prevWord,
    String? nextWord,
    int? minForwardDomOffset,
    void Function(int matchedDomOffset)? onMatchedDomOffset,
    String? sentenceText,
    int? sentenceLocalStart,
    int? sentenceLocalEnd,
    int? wordOffsetInSentence,
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

    final cleanPrevWord = prevWord?.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
      '',
    );
    final cleanNextWord = nextWord?.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
      '',
    );

    final nodeInfos = <_TextNodeInfo>[];
    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;
      final isSeparator = node.parent == null;

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
      // In DomTextUtils.extractPlainText, indent characters in nodeText are written directly,
      // so raw text length strictly matches cleanToProcessed.length + indentLen.
      final rawEquivalentLen = cleanToProcessed.length + indentLen;
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
        indentLen: indentLen,
        isBlockSeparator: isSeparator,
      ));
    }

    final totalDomLen = nodeInfos.isNotEmpty ? nodeInfos.last.nodeEnd : 0;

    // Build flat normalized representation across DOM text nodes for sentence anchoring
    final flatNormBuffer = StringBuffer();
    final normIdxToDomOffset = <int>[];
    bool lastWasSpace = false;

    for (final info in nodeInfos) {
      if (info.isBlockSeparator) {
        if (!lastWasSpace && flatNormBuffer.isNotEmpty) {
          flatNormBuffer.write(' ');
          normIdxToDomOffset.add(info.nodeStart);
          lastWasSpace = true;
        }
        continue;
      }

      final cleanText = info.cleanText;
      for (var j = 0; j < cleanText.length; j++) {
        final cu = cleanText.codeUnitAt(j);
        final ch = cleanText[j];
        final domOffset = info.cleanStartOffset + j;

        if (cu <= 0x20 || cu == 0x00A0 || cu == 0x2003 || cu == 0x3000) {
          if (!lastWasSpace && flatNormBuffer.isNotEmpty) {
            flatNormBuffer.write(' ');
            normIdxToDomOffset.add(domOffset);
            lastWasSpace = true;
          }
        } else {
          lastWasSpace = false;
          if (ch == '’' || ch == '‘') {
            flatNormBuffer.write('\'');
          } else if (ch == '“' || ch == '”') {
            flatNormBuffer.write('"');
          } else {
            flatNormBuffer.write(ch);
          }
          normIdxToDomOffset.add(domOffset);
        }
      }
    }

    final flatNorm = flatNormBuffer.toString();

    // Resolve sentence bounds in DOM space if sentence context is provided
    int? domSentenceStart;
    int? domSentenceEnd;
    if (sentenceText != null && sentenceText.trim().isNotEmpty) {
      final bounds = _findSentenceBounds(
        flatNorm: flatNorm,
        normIdxToDomOffset: normIdxToDomOffset,
        totalDomLen: totalDomLen,
        sentenceText: sentenceText,
        sentenceLocalStart: sentenceLocalStart,
        sentenceLocalEnd: sentenceLocalEnd,
        wordOffsetInSentence: wordOffsetInSentence,
        minForwardDomOffset: minForwardDomOffset,
      );
      if (bounds != null) {
        domSentenceStart = bounds.start;
        domSentenceEnd = bounds.end;
      }
    }

    final sentenceFloor = (minForwardDomOffset != null && (domSentenceStart == null || minForwardDomOffset > domSentenceStart))
        ? minForwardDomOffset
        : (domSentenceStart ?? minForwardDomOffset ?? 0);
    final sentenceCeil = domSentenceEnd;

    int effectiveExpectedPos = (minForwardDomOffset != null && minForwardDomOffset > rawStart)
        ? minForwardDomOffset
        : rawStart;
    if (domSentenceStart != null && domSentenceEnd != null) {
      effectiveExpectedPos = effectiveExpectedPos.clamp(
        sentenceFloor,
        (sentenceCeil! - 1).clamp(sentenceFloor, totalDomLen),
      );
    }

    int targetIdx = -1;
    for (var i = 0; i < nodeInfos.length; i++) {
      final info = nodeInfos[i];
      if (info.isBlockSeparator || info.cleanToProcessed.isEmpty) continue;
      if (rawEnd > info.nodeStart && effectiveExpectedPos < info.nodeEnd) {
        targetIdx = i;
        break;
      }
    }

    if (targetIdx == -1) {
      int minDiff = 1 << 30;
      for (var i = 0; i < nodeInfos.length; i++) {
        final info = nodeInfos[i];
        if (info.isBlockSeparator || info.cleanToProcessed.isEmpty) continue;
        final diff = (info.cleanStartOffset - effectiveExpectedPos).abs();
        if (diff < minDiff) {
          minDiff = diff;
          targetIdx = i;
        }
      }
    }

    if (targetIdx == -1) return html;

    _TextNodeInfo activeInfo = nodeInfos[targetIdx];
    final candidates = <_MatchCandidate>[];

    if (query != null && query.isNotEmpty) {
      final nodesToSearch = <int>[];
      if (domSentenceStart != null && domSentenceEnd != null) {
        for (var i = 0; i < nodeInfos.length; i++) {
          final info = nodeInfos[i];
          if (info.isBlockSeparator || info.cleanToProcessed.isEmpty) continue;
          if (info.nodeEnd > domSentenceStart && info.nodeStart < domSentenceEnd) {
            nodesToSearch.add(i);
          }
        }
      } else {
        nodesToSearch.add(targetIdx);

        // Search backwards within the same block (never cross block boundaries backwards)
        for (var i = targetIdx - 1; i >= 0; i--) {
          if (nodeInfos[i].isBlockSeparator) break;
          nodesToSearch.add(i);
        }

        // Search forwards (capped window ~60 chars from effectiveExpectedPos)
        for (var i = targetIdx + 1; i < nodeInfos.length; i++) {
          if (nodeInfos[i].nodeStart > effectiveExpectedPos + 60) break;
          if (nodeInfos[i].isBlockSeparator) continue;
          nodesToSearch.add(i);
        }
      }

      for (final i in nodesToSearch) {
        final info = nodeInfos[i];
        if (info.isBlockSeparator || info.cleanToProcessed.isEmpty) continue;
        final cleanText = info.cleanText;

        for (var pos = 0; pos + query.length <= cleanText.length; pos++) {
          if (_matchesWord(cleanText.substring(pos, pos + query.length), query) &&
              _isWordBoundary(cleanText, pos, query.length)) {
            final domOffset = info.cleanStartOffset + pos;

            // Enforce monotonic forward cursor: disallow backward jumps before minForwardDomOffset
            if (minForwardDomOffset != null && domOffset < minForwardDomOffset) {
              continue;
            }

            // Enforce sentence boundaries: candidate MUST be inside [domSentenceStart..domSentenceEnd]
            if (domSentenceStart != null && domOffset < domSentenceStart) {
              continue;
            }
            if (domSentenceEnd != null && domOffset >= domSentenceEnd) {
              continue;
            }

            // Cap forward search window when sentence bounds are not available
            if (domSentenceEnd == null && domOffset > effectiveExpectedPos + 60) {
              continue;
            }

            // Extract DOM neighbor words across inline nodes in the same block/sentence
            String? candPrev = extractPrevWord(cleanText, pos, sentenceStart: domSentenceStart);
            if (candPrev == null && i > 0 && !nodeInfos[i - 1].isBlockSeparator) {
              candPrev = extractPrevWord(nodeInfos[i - 1].cleanText, nodeInfos[i - 1].cleanText.length, sentenceStart: domSentenceStart);
            }

            String? candNext = extractNextWord(cleanText, pos + query.length, sentenceEnd: domSentenceEnd);
            if (candNext == null && i + 1 < nodeInfos.length && !nodeInfos[i + 1].isBlockSeparator) {
              candNext = extractNextWord(nodeInfos[i + 1].cleanText, 0, sentenceEnd: domSentenceEnd);
            }

            int score = 0;
            if (cleanPrevWord != null && candPrev != null && _matchesWord(candPrev, cleanPrevWord)) {
              score += 100;
            }
            if (cleanNextWord != null && candNext != null && _matchesWord(candNext, cleanNextWord)) {
              score += 100;
            }

            final dist = (domOffset - effectiveExpectedPos).abs();

            candidates.add(_MatchCandidate(
              nodeIndex: i,
              localStart: pos,
              localEnd: pos + query.length,
              domOffset: domOffset,
              score: score,
              dist: dist,
            ));
          }
        }
      }
    }

    int exactCleanStart = 0;
    int exactCleanEnd = 0;
    int matchedDomOffset = -1;

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        // 1. Candidate matching neighbor context strictly beats bare single-word match
        if (a.score != b.score) {
          return b.score.compareTo(a.score);
        }
        // 2. Closer to effectiveExpectedPos wins
        if (a.dist != b.dist) {
          return a.dist.compareTo(b.dist);
        }
        // 3. Monotonic forward preference
        return a.domOffset.compareTo(b.domOffset);
      });

      final best = candidates.first;
      activeInfo = nodeInfos[best.nodeIndex];
      exactCleanStart = best.localStart;
      exactCleanEnd = best.localEnd;
      matchedDomOffset = best.domOffset;
    } else {
      // Fallback: snap to whole-word boundaries around effectiveExpectedPos in activeInfo
      final cleanText = activeInfo.cleanText;
      int clampedPos = effectiveExpectedPos;
      if (domSentenceStart != null && domSentenceEnd != null) {
        clampedPos = clampedPos.clamp(sentenceFloor, (sentenceCeil! - 1).clamp(sentenceFloor, totalDomLen));
      }
      int wStart = (clampedPos - activeInfo.cleanStartOffset).clamp(0, cleanText.length);
      if (wStart < cleanText.length && !_isWordChar(cleanText[wStart])) {
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
        exactCleanStart = (clampedPos - activeInfo.cleanStartOffset).clamp(0, activeInfo.cleanToProcessed.length);
        final desiredLen = (rawEnd - rawStart).clamp(1, double.maxFinite.toInt());
        exactCleanEnd = (exactCleanStart + desiredLen).clamp(exactCleanStart + 1, activeInfo.cleanToProcessed.length);
      }
      matchedDomOffset = activeInfo.cleanStartOffset + exactCleanStart;
      if (domSentenceStart != null && matchedDomOffset < domSentenceStart) {
        matchedDomOffset = domSentenceStart;
      }
      if (domSentenceEnd != null && matchedDomOffset >= domSentenceEnd) {
        matchedDomOffset = domSentenceEnd - 1;
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
      'Injected highlight for "${mid.trim()}" at clean [$exactCleanStart..$exactCleanEnd] (domOffset: $matchedDomOffset)',
    );

    if (matchedDomOffset >= 0) {
      onMatchedDomOffset?.call(matchedDomOffset);
    }

    final hasHeadContent = document.head != null && document.head!.nodes.isNotEmpty;
    final hasDocEnvelope = html.contains(RegExp(r'<!doctype|<html|<head', caseSensitive: false));

    if (hasHeadContent || hasDocEnvelope) {
      return document.outerHtml;
    }

    return root.outerHtml;
  }
}
