/// Canonical book format enum for type-safe format handling.
/// 
/// Replaces string-based format checks with a proper enum,
/// enabling exhaustive switch statements and better IDE support.
enum BookFormat {
  pdf,
  epub,
  cbz,
  cbr,
  docx,
  mobi,
  azw,
  azw3,
  unknown;

  /// Parse a format string (case-insensitive) to BookFormat.
  static BookFormat fromString(String format) {
    switch (format.toLowerCase().trim()) {
      case 'pdf':
        return BookFormat.pdf;
      case 'epub':
        return BookFormat.epub;
      case 'cbz':
        return BookFormat.cbz;
      case 'cbr':
        return BookFormat.cbr;
      case 'docx':
        return BookFormat.docx;
      case 'mobi':
        return BookFormat.mobi;
      case 'azw':
        return BookFormat.azw;
      case 'azw3':
        return BookFormat.azw3;
      default:
        return BookFormat.unknown;
    }
  }

  /// Parse a file extension (with or without leading dot) to BookFormat.
  static BookFormat fromExtension(String extension) {
    final ext = extension.toLowerCase().trim();
    final normalized = ext.startsWith('.') ? ext.substring(1) : ext;
    return fromString(normalized);
  }

  /// Get the normalized format string for this format.
  String get formatString {
    switch (this) {
      case BookFormat.pdf:
        return 'pdf';
      case BookFormat.epub:
        return 'epub';
      case BookFormat.cbz:
        return 'cbz';
      case BookFormat.cbr:
        return 'cbr';
      case BookFormat.docx:
        return 'docx';
      case BookFormat.mobi:
        return 'mobi';
      case BookFormat.azw:
        return 'azw';
      case BookFormat.azw3:
        return 'azw3';
      case BookFormat.unknown:
        return 'unknown';
    }
  }

  /// Get all file extensions associated with this format.
  List<String> get extensions {
    switch (this) {
      case BookFormat.pdf:
        return ['.pdf'];
      case BookFormat.epub:
        return ['.epub'];
      case BookFormat.cbz:
        return ['.cbz'];
      case BookFormat.cbr:
        return ['.cbr'];
      case BookFormat.docx:
        return ['.docx'];
      case BookFormat.mobi:
        return ['.mobi'];
      case BookFormat.azw:
        return ['.azw'];
      case BookFormat.azw3:
        return ['.azw3'];
      case BookFormat.unknown:
        return [];
    }
  }

  /// Whether this format supports TTS (text-to-speech).
  bool get supportsTts {
    switch (this) {
      case BookFormat.pdf:
      case BookFormat.epub:
      case BookFormat.docx:
      case BookFormat.mobi:
      case BookFormat.azw:
      case BookFormat.azw3:
        return true;
      case BookFormat.cbz:
      case BookFormat.cbr:
      case BookFormat.unknown:
        return false;
    }
  }

  /// Whether this format is image-based (comics).
  bool get isImageBased {
    switch (this) {
      case BookFormat.cbz:
      case BookFormat.cbr:
        return true;
      default:
        return false;
    }
  }

  /// Get the reader type category for this format.
  BookReaderType get readerType {
    switch (this) {
      case BookFormat.pdf:
        return BookReaderType.pdf;
      case BookFormat.epub:
        return BookReaderType.epub;
      case BookFormat.cbz:
      case BookFormat.cbr:
        return BookReaderType.cbz;
      case BookFormat.docx:
        return BookReaderType.html;
      case BookFormat.mobi:
      case BookFormat.azw:
      case BookFormat.azw3:
        return BookReaderType.html;
      case BookFormat.unknown:
        return BookReaderType.unsupported;
    }
  }
}

/// Reader type categories for grouping similar formats.
enum BookReaderType {
  pdf,
  epub,
  cbz,
  html,
  unsupported,
}
