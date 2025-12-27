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
