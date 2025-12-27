class SentenceSpan {
  final int start;
  final int end;

  const SentenceSpan(this.start, this.end);
}

bool _isSentencePunctuation(int codeUnit) {
  return codeUnit == 46 || // .
      codeUnit == 33 || // !
      codeUnit == 63 || // ?
      codeUnit == 8230; // ellipsis
}

bool _isWhitespace(int codeUnit) {
  return codeUnit <= 32;
}

List<SentenceSpan> splitIntoSentences(String text) {
  if (text.trim().isEmpty) return const [];

  final spans = <SentenceSpan>[];
  var start = 0;
  var i = 0;

  while (i < text.length) {
    final code = text.codeUnitAt(i);
    final isLineBreak = code == 10 || code == 13; // \n or \r
    final isBoundary = _isSentencePunctuation(code) || isLineBreak;

    if (isBoundary) {
      var end = i + 1;
      while (end < text.length && _isSentencePunctuation(text.codeUnitAt(end))) {
        end++;
      }

      final hasTrailingSpace = end >= text.length ||
          _isWhitespace(text.codeUnitAt(end)) ||
          text.codeUnitAt(end) == 10 ||
          text.codeUnitAt(end) == 13;

      if (hasTrailingSpace || isLineBreak) {
        var trimmedEnd = end;
        while (trimmedEnd > start && _isWhitespace(text.codeUnitAt(trimmedEnd - 1))) {
          trimmedEnd--;
        }
        if (trimmedEnd > start) {
          spans.add(SentenceSpan(start, trimmedEnd));
        }

        var nextStart = end;
        while (nextStart < text.length && _isWhitespace(text.codeUnitAt(nextStart))) {
          nextStart++;
        }
        start = nextStart;
        i = start;
        continue;
      }
    }

    i++;
  }

  if (start < text.length) {
    var end = text.length;
    while (end > start && _isWhitespace(text.codeUnitAt(end - 1))) {
      end--;
    }
    if (end > start) {
      spans.add(SentenceSpan(start, end));
    }
  }

  return spans.isEmpty ? [SentenceSpan(0, text.length)] : spans;
}

SentenceSpan? sentenceForOffset(List<SentenceSpan> spans, int offset) {
  if (spans.isEmpty) return null;
  if (offset <= spans.first.start) return spans.first;
  if (offset >= spans.last.end) return spans.last;

  var low = 0;
  var high = spans.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final span = spans[mid];
    if (offset < span.start) {
      high = mid - 1;
    } else if (offset >= span.end) {
      low = mid + 1;
    } else {
      return span;
    }
  }

  return spans.first;
}

int findSentenceStart(String text, int approxIndex) {
  if (text.trim().isEmpty) return 0;

  final clamped = approxIndex.clamp(0, text.length - 1);
  var index = clamped;

  while (index > 0) {
    final code = text.codeUnitAt(index - 1);
    if (_isSentencePunctuation(code) || code == 10 || code == 13) {
      break;
    }
    index--;
  }

  while (index < text.length && _isWhitespace(text.codeUnitAt(index))) {
    index++;
  }

  return index.clamp(0, text.length);
}

String sliceFromSentenceStart(String text, int approxIndex) {
  if (text.trim().isEmpty) return '';
  final start = findSentenceStart(text, approxIndex);
  if (start >= text.length) return '';
  return text.substring(start);
}
