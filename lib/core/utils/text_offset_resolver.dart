/// Pure, stateless resolver that maps a screen tap on rendered text
/// to the exact character offset in the raw chapter text.
class TextOffsetResolver {
  static final RegExp _wordTokenRegex = RegExp(
    r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*",
    unicode: true,
  );

  static final RegExp _invisibleArtifacts = RegExp(r'[\uFFFC\uFFFD\u00AD\u200B]');

  /// Resolves the exact character offset in [chapterText] for a tap at [rawHitOffset]
  /// inside [rawParagraphFragment].
  static ({String word, int offset})? resolveExactOffset({
    required String chapterText,
    required String rawParagraphFragment,
    required int rawHitOffset,
    required int windowStart,
    required int windowEnd,
    required int expectedOffset,
  }) {
    if (chapterText.isEmpty || rawParagraphFragment.isEmpty) return null;

    // 1. Sanitize fragment while adjusting rawHitOffset for stripped characters before the tap
    final clampedRawHit = rawHitOffset.clamp(0, rawParagraphFragment.length);
    final strippedBeforeHit = _invisibleArtifacts
        .allMatches(rawParagraphFragment.substring(0, clampedRawHit))
        .length;

    final cleanFragment = rawParagraphFragment
        .replaceAll(_invisibleArtifacts, '')
        .replaceAll('\u00A0', ' ');
    if (cleanFragment.isEmpty) return null;

    final cleanHitOffset = (clampedRawHit - strippedBeforeHit).clamp(0, cleanFragment.length);

    // 2. Tokenize the cleaned paragraph and locate the tapped word token
    final tokens = _wordTokenRegex.allMatches(cleanFragment).toList();
    if (tokens.isEmpty) return null;

    int targetTokenIdx = tokens.indexWhere(
      (m) => cleanHitOffset >= m.start && cleanHitOffset <= m.end,
    );
    if (targetTokenIdx == -1) {
      targetTokenIdx = tokens.indexWhere((m) => m.start >= cleanHitOffset);
      if (targetTokenIdx == -1) targetTokenIdx = tokens.length - 1;
    }

    final targetWord = tokens[targetTokenIdx].group(0)!;
    final safeStart = windowStart.clamp(0, chapterText.length);
    final safeEnd = windowEnd > safeStart
        ? windowEnd.clamp(safeStart, chapterText.length)
        : chapterText.length;
    final safeExpected = expectedOffset.clamp(safeStart, safeEnd);

    // 3. Tier 1: N-Gram Context Match (up to 3 words before and 3 words after)
    final startIdx = (targetTokenIdx - 3).clamp(0, tokens.length - 1);
    final endIdx = (targetTokenIdx + 3).clamp(0, tokens.length - 1);

    if (endIdx > startIdx) {
      // Pad window by ±300 chars so N-grams at page slice boundaries aren't clipped
      final paddedStart = (safeStart - 300).clamp(0, chapterText.length);
      final paddedEnd = (safeEnd + 300).clamp(paddedStart, chapterText.length);

      final windowedMatch = _matchNGramInWindow(
        chapterText: chapterText,
        tokens: tokens,
        startIdx: startIdx,
        targetIdx: targetTokenIdx,
        endIdx: endIdx,
        windowStart: paddedStart,
        windowEnd: paddedEnd,
        expectedOffset: safeExpected,
      );
      if (windowedMatch != null) {
        return (word: targetWord, offset: windowedMatch);
      }

      // Tier 1b: Full-chapter N-Gram fallback if scroll/page window missed
      if (paddedStart > 0 || paddedEnd < chapterText.length) {
        final fullChapterNGramMatch = _matchNGramInWindow(
          chapterText: chapterText,
          tokens: tokens,
          startIdx: startIdx,
          targetIdx: targetTokenIdx,
          endIdx: endIdx,
          windowStart: 0,
          windowEnd: chapterText.length,
          expectedOffset: safeExpected,
        );
        if (fullChapterNGramMatch != null) {
          return (word: targetWord, offset: fullChapterNGramMatch);
        }
      }
    }

    // 4. Tier 2: Strict Unicode Word-Boundary Search Near Anchor
    final boundaryPattern = RegExp(
      r'(?<![\p{L}\p{N}])(' + _softHyphenTolerantPattern(targetWord) + r')(?![\p{L}\p{N}])',
      unicode: true,
    );

    final windowSlice = chapterText.substring(safeStart, safeEnd);
    final windowMatches = boundaryPattern.allMatches(windowSlice);
    if (windowMatches.isNotEmpty) {
      final best = _closestMatch(
        matches: windowMatches,
        baseOffset: safeStart,
        expectedOffset: safeExpected,
      );
      return (word: targetWord, offset: best);
    }

    // Full-chapter single-word fallback with strict boundaries
    final allMatches = boundaryPattern.allMatches(chapterText);
    if (allMatches.isNotEmpty) {
      final best = _closestMatch(
        matches: allMatches,
        baseOffset: 0,
        expectedOffset: safeExpected,
      );
      return (word: targetWord, offset: best);
    }

    // 5. Tier 3: Safety clamp to active window start (never 0 unless on Page 1)
    return (word: targetWord, offset: safeStart);
  }

  /// Allows optional soft-hyphens (\u00AD) inside raw chapterText words without mutating DOM lengths.
  static String _softHyphenTolerantPattern(String word) {
    return word.split('').map(RegExp.escape).join(r'\u00AD?');
  }

  static int? _matchNGramInWindow({
    required String chapterText,
    required List<RegExpMatch> tokens,
    required int startIdx,
    required int targetIdx,
    required int endIdx,
    required int windowStart,
    required int windowEnd,
    required int expectedOffset,
  }) {
    const sep = r'[^\p{L}\p{N}]+';
    final beforeWords = [
      for (var i = startIdx; i < targetIdx; i++)
        _softHyphenTolerantPattern(tokens[i].group(0)!),
    ];
    final targetPattern = _softHyphenTolerantPattern(tokens[targetIdx].group(0)!);
    final afterWords = [
      for (var i = targetIdx + 1; i <= endIdx; i++)
        _softHyphenTolerantPattern(tokens[i].group(0)!),
    ];

    final prefixPart = beforeWords.isEmpty ? '' : '${beforeWords.join(sep)}$sep';
    final suffixPart = afterWords.isEmpty ? '' : '$sep${afterWords.join(sep)}';
    final pattern = RegExp('($prefixPart)($targetPattern)$suffixPart', unicode: true);

    final slice = chapterText.substring(windowStart, windowEnd);
    final matches = pattern.allMatches(slice);
    if (matches.isEmpty) return null;

    int? bestOffset;
    int bestDistance = 1 << 30;
    for (final m in matches) {
      final prefixLen = m.group(1)?.length ?? 0;
      final candidateOffset = windowStart + m.start + prefixLen;
      final distance = (candidateOffset - expectedOffset).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestOffset = candidateOffset;
      }
    }
    return bestOffset;
  }

  static int _closestMatch({
    required Iterable<RegExpMatch> matches,
    required int baseOffset,
    required int expectedOffset,
  }) {
    int bestOffset = baseOffset;
    int bestDistance = 1 << 30;
    for (final m in matches) {
      final candidateOffset = baseOffset + m.start;
      final distance = (candidateOffset - expectedOffset).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestOffset = candidateOffset;
      }
    }
    return bestOffset;
  }
}
