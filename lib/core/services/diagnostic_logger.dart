import 'dart:collection';

enum LogLevel { debug, info, warning, error }

/// Represents an individual immutable log entry in the diagnostic buffer.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final StackTrace? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });
}

/// In-memory ring buffer logger for capturing diagnostics and errors
/// without disk I/O contention during active reading or 60/120fps animations.
class DiagnosticLogger {
  static final DiagnosticLogger instance = DiagnosticLogger._internal();
  factory DiagnosticLogger() => instance;
  DiagnosticLogger._internal();

  static const int maxCapacity = 200;
  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>(maxCapacity);

  /// Regex targeting Android storage paths:
  /// 1. Internal primary storage: /storage/emulated/0/...
  /// 2. Removable SD card storage: /storage/[0-9A-Fa-f-]+/...
  /// 3. App-specific storage: /data/user/0/... or /data/data/...
  /// Handles spaces in folder and book filenames.
  static final RegExp _storagePathRegex = RegExp(
    r'(\/(?:storage\/(?:emulated\/\d+|[0-9A-Fa-f-]+)|data\/(?:user\/\d+|data)\/[^\/\s]+))\/'
    r'(?:([^\r\n]+?)\/)?'
    r'([^/\r\n]+?\.[a-zA-Z0-9]+)',
    caseSensitive: false,
  );

  /// Secondary regex for raw directory paths without file extensions
  static final RegExp _rawDirectoryRegex = RegExp(
    r'(\/(?:storage\/(?:emulated\/\d+|[0-9A-Fa-f-]+)|data\/(?:user\/\d+|data)\/[^\/\s]+))'
    r'(\/[^\s\)\x22\x27<>]+)?',
    caseSensitive: false,
  );

  /// Appends an event to the ring buffer. Evicts oldest entries in O(1) time.
  /// Sanitizes messages on ingestion so UI rendering and screenshots never leak personal paths.
  void log(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    StackTrace? stackTrace,
  }) {
    if (_buffer.length >= maxCapacity) {
      _buffer.removeFirst();
    }
    _buffer.addLast(
      LogEntry(
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: sanitize(message),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Convenience method for recording an error with optional stack trace.
  void logError(String tag, Object error, [StackTrace? stackTrace]) {
    log(
      tag,
      error.toString(),
      level: LogLevel.error,
      stackTrace: stackTrace ?? (error is Error ? error.stackTrace : null),
    );
  }

  /// Returns an unmodifiable snapshot of the current buffer.
  List<LogEntry> getEntries() => List.unmodifiable(_buffer);

  /// Clears the in-memory buffer.
  void clear() => _buffer.clear();

  /// Scrubs local filesystem paths, personal folder names, and usernames
  /// while preserving the essential book format extension.
  static String sanitize(String input) {
    if (input.isEmpty) return input;

    // First scrub paths with files and extensions
    final scrubbedFiles = input.replaceAllMapped(_storagePathRegex, (match) {
      final filenameWithExt = match.group(3) ?? '';
      final dotIdx = filenameWithExt.lastIndexOf('.');
      final ext = dotIdx != -1 ? filenameWithExt.substring(dotIdx) : '';
      return '[STORAGE]/<redacted_path>/<book_file>$ext';
    });

    // Then scrub remaining raw storage directory paths
    return scrubbedFiles.replaceAllMapped(_rawDirectoryRegex, (_) {
      return '[STORAGE]/<redacted_path>';
    });
  }

  /// Exports the logs as sanitized, formatted plain text ready for clipboard or sharing.
  String formatPlainText({bool includeStack = true}) {
    if (_buffer.isEmpty) return 'No diagnostic logs recorded.';

    final sb = StringBuffer();
    sb.writeln('=== FERROUS DIAGNOSTIC LOG ===');
    sb.writeln('Generated (UTC): ${DateTime.now().toUtc().toIso8601String()}');
    sb.writeln('Buffered Events: ${_buffer.length}');
    sb.writeln('===============================\n');

    for (final entry in _buffer) {
      final timeStr = entry.timestamp.toIso8601String();
      final lvl = entry.level.name.toUpperCase().padRight(5);
      sb.writeln('[$timeStr] $lvl [${entry.tag}] ${entry.message}');
      if (includeStack && entry.stackTrace != null) {
        sb.writeln(entry.stackTrace.toString().trimRight());
      }
    }

    return sanitize(sb.toString());
  }
}
