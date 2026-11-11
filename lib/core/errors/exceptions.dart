/// Base exception for all Ferrous app errors.
abstract class FerrousException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const FerrousException(
    this.message, {
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'FerrousException: $message';
}

/// Exception thrown when Storage Access Framework (SAF) operations fail.
class SafException extends FerrousException {
  const SafException(
    super.message, {
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => 'SafException: $message';
}

/// Exception thrown when extracting or decoding a page from an archive (CBZ, CBR, etc.) fails.
class ArchiveExtractionException extends FerrousException {
  final int pageIndex;

  const ArchiveExtractionException(
    super.message, {
    required this.pageIndex,
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() => message;
}

