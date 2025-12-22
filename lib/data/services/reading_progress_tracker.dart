import 'dart:async';
import 'package:reader_app/data/repositories/book_repository.dart';

/// A debounced reading progress tracker that batches frequent progress updates.
/// 
/// This centralizes the repeated progress saving logic from all reader implementations,
/// providing consistent debouncing and separating high-frequency progress updates
/// from immediate "lastOpened" updates.
class ReadingProgressTracker {
  final BookRepository repository;
  final Duration debounceDuration;

  Timer? _debounceTimer;
  String? _pendingBookId;
  int? _pendingPage;
  int? _pendingTotalPages;
  double? _pendingScrollPosition;

  ReadingProgressTracker({
    required this.repository,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  /// Update reading progress with debouncing.
  /// High-frequency updates (e.g., during scrolling) are batched.
  void updateProgress(
    String bookId, {
    int? currentPage,
    int? totalPages,
    double? scrollPosition,
  }) {
    _pendingBookId = bookId;
    _pendingPage = currentPage ?? _pendingPage;
    _pendingTotalPages = totalPages ?? _pendingTotalPages;
    _pendingScrollPosition = scrollPosition ?? _pendingScrollPosition;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _flushProgress);
  }

  /// Update progress immediately without debouncing.
  /// Use for critical save points (e.g., page change, app pause).
  void updateProgressImmediately(
    String bookId, {
    int? currentPage,
    int? totalPages,
    double? scrollPosition,
  }) {
    _debounceTimer?.cancel();
    _pendingBookId = null;
    _pendingPage = null;
    _pendingTotalPages = null;
    _pendingScrollPosition = null;

    repository.updateReadingProgress(
      bookId,
      currentPage: currentPage,
      totalPages: totalPages,
      scrollPosition: scrollPosition,
    );
  }

  /// Update TTS sentence position (separate from progress).
  void updateTtsSentence(
    String bookId, {
    required int sentenceStart,
    required int sentenceEnd,
    required int page,
    int? totalPages,
  }) {
    repository.updateReadingProgress(
      bookId,
      currentPage: page,
      totalPages: totalPages,
      lastTtsSentenceStart: sentenceStart,
      lastTtsSentenceEnd: sentenceEnd,
      lastTtsPage: page,
    );
  }

  /// Force flush any pending progress updates.
  /// Call this on dispose, app pause, or before any async operation that might fail.
  void flush() {
    _flushProgress();
  }

  void _flushProgress() {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final bookId = _pendingBookId;
    if (bookId == null) return;

    final page = _pendingPage;
    final totalPages = _pendingTotalPages;
    final scroll = _pendingScrollPosition;

    _pendingBookId = null;
    _pendingPage = null;
    _pendingTotalPages = null;
    _pendingScrollPosition = null;

    repository.updateReadingProgress(
      bookId,
      currentPage: page,
      totalPages: totalPages,
      scrollPosition: scroll,
    );
  }

  /// Dispose of the tracker and flush any pending updates.
  void dispose() {
    flush();
  }
}
