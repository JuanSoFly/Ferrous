import 'package:reader_app/core/utils/normalized_text_map.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';

/// Tracks where a PDF page's text lives within the assembled document text.
class PdfPageOffset {
  /// The page index in the PDF.
  final int pageIndex;

  /// Start character offset in the assembled (raw) document text.
  final int documentCharStart;

  /// End character offset (exclusive) in the assembled (raw) document text.
  final int documentCharEnd;

  /// Number of characters in the page's own raw text.
  final int pageCharCount;

  const PdfPageOffset({
    required this.pageIndex,
    required this.documentCharStart,
    required this.documentCharEnd,
    required this.pageCharCount,
  });
}

/// Holds the full document text assembled from all PDF pages, with mappings
/// to convert between document-level offsets and per-page offsets.
///
/// This is the PDF equivalent of the EPUB chapter text — a single continuous
/// string that the TTS engine can speak without breaking at page boundaries.
class PdfDocumentText {
  /// The assembled raw text (all pages concatenated).
  final String fullText;

  /// The normalized version of [fullText].
  final String normalizedText;

  /// Mapping between normalized and raw text offsets.
  final NormalizedTextMap normalizedMap;

  /// Per-page offset information, ordered by page index.
  final List<PdfPageOffset> pageOffsets;

  /// Sentence boundaries in the normalized text.
  final List<SentenceSpan> sentences;

  const PdfDocumentText({
    required this.fullText,
    required this.normalizedText,
    required this.normalizedMap,
    required this.pageOffsets,
    required this.sentences,
  });

  bool get isEmpty => normalizedText.isEmpty;
  bool get isNotEmpty => normalizedText.isNotEmpty;
  int get pageCount => pageOffsets.length;

  /// Find which page contains the given offset in the assembled raw text.
  /// Returns -1 if the offset is out of range.
  int pageForDocumentOffset(int docOffset) {
    if (docOffset < 0 || pageOffsets.isEmpty) return -1;
    // Binary search for the page containing this offset.
    var low = 0;
    var high = pageOffsets.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = pageOffsets[mid];
      if (docOffset < page.documentCharStart) {
        high = mid - 1;
      } else if (docOffset >= page.documentCharEnd) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    // Clamp to last page if offset is at the very end.
    if (docOffset >= pageOffsets.last.documentCharEnd) {
      return pageOffsets.length - 1;
    }
    return -1;
  }

  /// Convert a document-level raw offset to a page-local raw offset.
  /// Returns -1 if the page index is invalid.
  int localOffset(int docOffset, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pageOffsets.length) return -1;
    final page = pageOffsets[pageIndex];
    return (docOffset - page.documentCharStart).clamp(0, page.pageCharCount);
  }

  /// Get the page-local text for a given page index.
  /// Returns the trimmed content for this page (excludes inter-page separators).
  String pageText(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pageOffsets.length) return '';
    final page = pageOffsets[pageIndex];
    if (page.pageCharCount <= 0) return '';
    return fullText.substring(page.documentCharStart, page.documentCharEnd).trim();
  }
}

/// Assemble document text from per-page extracted texts.
///
/// [pageTexts] is a map from page index to the page's raw extracted text.
/// [pageCount] is the total number of pages in the PDF.
///
/// Pages with empty or whitespace-only text are included with zero-length
/// offsets so that page indices remain consistent.
PdfDocumentText buildPdfDocumentText(Map<int, String> pageTexts, int pageCount) {
  if (pageCount <= 0) {
    return PdfDocumentText(
      fullText: '',
      normalizedText: '',
      normalizedMap: const NormalizedTextMap('', [], []),
      pageOffsets: const [],
      sentences: const [],
    );
  }

  final buffer = StringBuffer();
  final pageOffsets = <PdfPageOffset>[];

  for (var i = 0; i < pageCount; i++) {
    final rawText = pageTexts[i] ?? '';
    final trimmed = rawText.trim();

    if (trimmed.isNotEmpty) {
      final rangeStart = buffer.length;
      if (buffer.isNotEmpty) {
        buffer.write(' \n\n '); // sentence-boundary-friendly separator
      }
      buffer.write(trimmed);
      final rangeEnd = buffer.length;

      pageOffsets.add(PdfPageOffset(
        pageIndex: i,
        documentCharStart: rangeStart,
        documentCharEnd: rangeEnd,
        pageCharCount: trimmed.length,
      ));
    } else {
      // Empty page — share the previous page's end to avoid gaps in the
      // offset range (so pageForDocumentOffset binary search works correctly).
      final pos = buffer.length;
      pageOffsets.add(PdfPageOffset(
        pageIndex: i,
        documentCharStart: pos,
        documentCharEnd: pos,
        pageCharCount: 0,
      ));
    }
  }

  final fullText = buffer.toString();
  final normalizedMap = buildNormalizedTextMap(fullText);
  final normalizedText = normalizedMap.normalized;
  final sentences = splitIntoSentences(normalizedText);

  return PdfDocumentText(
    fullText: fullText,
    normalizedText: normalizedText,
    normalizedMap: normalizedMap,
    pageOffsets: pageOffsets,
    sentences: sentences,
  );
}
