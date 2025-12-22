/// A mapping between normalized text and the original raw text positions.
/// 
/// This is used for TTS highlighting where we need to map word positions
/// in normalized text back to character positions in the original text.
class NormalizedTextMap {
  /// The normalized text with collapsed whitespace.
  final String normalized;

  /// Maps each character index in [normalized] to its original index in raw text.
  final List<int> normalizedToRaw;

  const NormalizedTextMap(this.normalized, this.normalizedToRaw);

  /// Get the raw text index for a normalized text position.
  /// Returns -1 if the position is out of bounds.
  int rawIndex(int normalizedPos) {
    if (normalizedPos < 0 || normalizedPos >= normalizedToRaw.length) {
      return -1;
    }
    return normalizedToRaw[normalizedPos];
  }

  /// Get a range of raw indices for a normalized range.
  /// Returns null if the range is invalid.
  ({int start, int end})? rawRange(int normalizedStart, int normalizedEnd) {
    if (normalizedStart < 0 || normalizedEnd <= normalizedStart) return null;
    if (normalizedStart >= normalizedToRaw.length) return null;

    final clampedEnd = normalizedEnd.clamp(0, normalizedToRaw.length);
    if (clampedEnd <= normalizedStart) return null;

    final rawStart = normalizedToRaw[normalizedStart];
    final rawEnd = normalizedToRaw[clampedEnd - 1] + 1;
    return (start: rawStart, end: rawEnd);
  }

  /// Whether this map is empty.
  bool get isEmpty => normalized.isEmpty;

  /// Whether this map is not empty.
  bool get isNotEmpty => normalized.isNotEmpty;
}

/// Build a normalized text map from raw text.
/// 
/// This is extracted from identical implementations in pdf_reader.dart and epub_reader.dart.
/// - Collapses multiple whitespace into single space
/// - Removes zero-width spaces (\\u200B)
/// - Converts non-breaking spaces (\\u00A0) to regular spaces
/// - Trims trailing whitespace
/// - Maintains character index mapping for TTS highlighting
NormalizedTextMap buildNormalizedTextMap(String raw) {
  if (raw.trim().isEmpty) {
    return const NormalizedTextMap('', []);
  }

  final buffer = StringBuffer();
  final map = <int>[];
  var inWhitespace = false;

  for (var i = 0; i < raw.length; i++) {
    var ch = raw[i];
    
    // Skip zero-width spaces
    if (ch == '\u200B') {
      continue;
    }
    
    // Convert non-breaking space to regular space
    if (ch == '\u00A0') {
      ch = ' ';
    }

    final isWhitespace = ch.trim().isEmpty;
    if (isWhitespace) {
      // Skip leading whitespace
      if (buffer.isEmpty) continue;
      // Skip consecutive whitespace
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
  
  // Trim trailing whitespace
  if (normalized.endsWith(' ')) {
    normalized = normalized.substring(0, normalized.length - 1);
    if (map.isNotEmpty) {
      map.removeLast();
    }
  }

  return NormalizedTextMap(normalized, map);
}
