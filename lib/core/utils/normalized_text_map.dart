class NormalizedTextMap {
  final String normalized;
  final List<int> normalizedToRaw;

  const NormalizedTextMap(this.normalized, this.normalizedToRaw);
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
    return const NormalizedTextMap('', []);
  }

  final buffer = StringBuffer();
  final map = <int>[];
  var inWhitespace = false;

  for (var i = 0; i < raw.length; i++) {
    var ch = raw[i];
    
    if (ch == '\u200B') {
      continue;
    }
    
    if (ch == '\u00A0') {
      ch = ' ';
    }

    final isWhitespace = ch.trim().isEmpty;
    if (isWhitespace) {
      if (buffer.isEmpty) continue;
      if (inWhitespace) continue;
      
      buffer.write(' ');
      map.add(i);
      inWhitespace = true;
      continue;
    }

    buffer.write(ch);
    map.add(i);
    inWhitespace = false;
  }

  var normalized = buffer.toString();
  if (normalized.endsWith(' ')) {
    normalized = normalized.substring(0, normalized.length - 1);
    if (map.isNotEmpty) {
      map.removeLast();
    }
  }

  return NormalizedTextMap(normalized, map);
}
