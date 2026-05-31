class NormalizedTextMap {
  final String normalized;
  final List<int> normalizedToRaw;
  final List<int> normalizedRuneToCodeUnit;

  const NormalizedTextMap(this.normalized, this.normalizedToRaw, this.normalizedRuneToCodeUnit);

  int runeToCodeUnit(int runeIndex) {
    if (normalizedRuneToCodeUnit.isEmpty) return runeIndex;
    if (runeIndex < 0) return 0;
    if (runeIndex >= normalizedRuneToCodeUnit.length) return normalized.length;
    return normalizedRuneToCodeUnit[runeIndex];
  }

  int codeUnitToRune(int codeUnitIndex) {
    if (normalizedRuneToCodeUnit.isEmpty) return codeUnitIndex;
    if (codeUnitIndex <= 0) return 0;
    if (codeUnitIndex >= normalized.length) return normalizedRuneToCodeUnit.length;
    
    // Binary search
    var low = 0;
    var high = normalizedRuneToCodeUnit.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final val = normalizedRuneToCodeUnit[mid];
      if (val == codeUnitIndex) {
        return mid;
      } else if (val < codeUnitIndex) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return high.clamp(0, normalizedRuneToCodeUnit.length - 1);
  }

  int rawIndex(int normalizedPos) {
    if (normalizedPos < 0 || normalizedPos >= normalizedToRaw.length) {
      return -1;
    }
    return normalizedToRaw[normalizedPos];
  }
  ({int start, int end})? rawRange(int normalizedStart, int normalizedEnd) {
    if (normalizedStart < 0 || normalizedEnd <= normalizedStart) return null;
    if (normalizedStart >= normalizedToRaw.length) return null;

    final clampedEnd = normalizedEnd.clamp(0, normalizedToRaw.length);
    if (clampedEnd <= normalizedStart) return null;

    final rawStart = normalizedToRaw[normalizedStart];
    final rawEnd = normalizedToRaw[clampedEnd - 1] + 1;
    return (start: rawStart, end: rawEnd);
  }
  bool get isEmpty => normalized.isEmpty;
  bool get isNotEmpty => normalized.isNotEmpty;
}

/// Build a normalized text map from raw text.
NormalizedTextMap buildNormalizedTextMap(String raw) {
  if (raw.trim().isEmpty) {
    return const NormalizedTextMap('', [], []);
  }

  final buffer = StringBuffer();
  final map = <int>[];
  final runeToCodeUnit = <int>[];
  var inWhitespace = false;
  var i = 0;
  var currentCodeUnitOffset = 0;

  for (final rune in raw.runes) {
    var ch = String.fromCharCode(rune);
    final codeUnitLen = ch.length;
    
    if (ch == '\u200B') {
      i += codeUnitLen;
      continue;
    }
    
    if (ch == '\u00A0') {
      ch = ' ';
    }

    final isWhitespace = ch.trim().isEmpty;
    if (isWhitespace) {
      if (buffer.isEmpty) {
        i += codeUnitLen;
        continue;
      }
      if (inWhitespace) {
        i += codeUnitLen;
        continue;
      }
      
      buffer.write(' ');
      map.add(i);
      runeToCodeUnit.add(currentCodeUnitOffset);
      inWhitespace = true;
      i += codeUnitLen;
      currentCodeUnitOffset += 1;
      continue;
    }

    buffer.write(ch);
    map.add(i);
    runeToCodeUnit.add(currentCodeUnitOffset);
    inWhitespace = false;
    i += codeUnitLen;
    currentCodeUnitOffset += codeUnitLen;
  }

  var normalized = buffer.toString();
  if (normalized.endsWith(' ')) {
    normalized = normalized.substring(0, normalized.length - 1);
    if (map.isNotEmpty) {
      map.removeLast();
    }
    if (runeToCodeUnit.isNotEmpty) {
      runeToCodeUnit.removeLast();
    }
  }

  return NormalizedTextMap(normalized, map, runeToCodeUnit);
}
