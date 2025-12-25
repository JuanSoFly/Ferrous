import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/covers.dart' as covers_api;

/// Repository for managing book data with reactive notifications.
/// 
/// Uses ChangeNotifier to allow widgets to automatically rebuild when book
/// data changes, eliminating the need for manual refresh calls after navigation.
class BookRepository extends ChangeNotifier {
  static const String _boxName = 'books';

  Box<Book>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<Book>(_boxName);
  }

  Box<Book> get box {
    if (_box == null) {
      throw StateError('BookRepository not initialized. Call init() first.');
    }
    return _box!;
  }

  List<Book> getAllBooks() {
    return box.values.toList();
  }

  Book? getBook(String id) {
    return box.get(id);
  }

  Future<void> addBook(Book book) async {
    await box.put(book.id, book);
    notifyListeners();
  }

  Future<void> addBooks(List<Book> books) async {
    final Map<String, Book> bookMap = {for (var b in books) b.id: b};
    await box.putAll(bookMap);
    notifyListeners();
  }

  Future<void> updateBook(Book book) async {
    await box.put(book.id, book);
    notifyListeners();
  }

  Future<void> deleteBook(String id) async {
    await box.delete(id);
    notifyListeners();
  }

  /// Update reading progress silently (no notification).
  /// Progress updates happen frequently and don't need to trigger UI rebuilds.
  Future<void> updateReadingProgress(
    String id, {
    int? currentPage,
    int? totalPages,
    int? sectionIndex,
    double? scrollPosition,
    ReadingMode? readingMode,
    int? lastReadingSentenceStart,
    int? lastReadingSentenceEnd,
    int? lastTtsSentenceStart,
    int? lastTtsSentenceEnd,
    int? lastTtsPage,
    int? lastTtsSection,
  }) async {
    final book = getBook(id);
    if (book != null) {
      final updated = book.copyWith(
        currentPage: currentPage,
        totalPages: totalPages,
        sectionIndex: sectionIndex,
        scrollPosition: scrollPosition,
        readingMode: readingMode,
        lastReadingSentenceStart: lastReadingSentenceStart,
        lastReadingSentenceEnd: lastReadingSentenceEnd,
        lastTtsSentenceStart: lastTtsSentenceStart,
        lastTtsSentenceEnd: lastTtsSentenceEnd,
        lastTtsPage: lastTtsPage,
        lastTtsSection: lastTtsSection,
        lastOpened: DateTime.now(),
      );
      await box.put(book.id, updated);
      // Note: No notifyListeners() here - progress updates are silent
      // to avoid expensive rebuilds during reading
    }
  }

  /// Update reading progress and notify listeners.
  /// Use this when progress changes should be immediately reflected in UI.
  Future<void> updateReadingProgressAndNotify(
    String id, {
    int? currentPage,
    int? totalPages,
  }) async {
    await updateReadingProgress(id, currentPage: currentPage, totalPages: totalPages);
    notifyListeners();
  }

  List<Book> getRecentBooks({int limit = 10}) {
    final books = getAllBooks();
    books.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return books.take(limit).toList();
  }

  bool bookExists({String? filePath, String? sourceUri}) {
    return box.values.any((book) {
      if (sourceUri != null && sourceUri.isNotEmpty) {
        if (book.sourceUri == sourceUri) return true;
      }
      if (filePath != null && filePath.isNotEmpty) {
        if (book.filePath == filePath) return true;
      }
      return false;
    });
  }

  /// Generate covers for all books that don't have one.
  /// [coversDir] is the absolute path to the directory where covers will be saved.
  Future<int> generateCovers(String coversDir) async {
    final books = getAllBooks();
    int generated = 0;

    final resolver = BookFileResolver();
    for (final book in books) {
      final existingCoverPath = book.coverPath;
      final hasExistingCoverFile = existingCoverPath != null &&
          existingCoverPath.isNotEmpty &&
          File(existingCoverPath).existsSync();

      final expectedCoverPath = '$coversDir/${book.id}.png';

      // If we already have a valid on-disk cover, keep it.
      if (hasExistingCoverFile) {
        continue;
      }

      // If the cover file exists at the expected location but the Book points
      // to nothing (or a stale path), just relink it without re-extracting.
      if (File(expectedCoverPath).existsSync()) {
        final updated = book.copyWith(coverPath: expectedCoverPath);
        await box.put(book.id, updated);
        generated++;
        continue;
      }

      try {
        final resolved = await resolver.resolve(book);
        try {
          await _extractCover(resolved.path, expectedCoverPath);
        } finally {
          if (resolved.isTemp) {
            try {
              await File(resolved.path).delete();
            } catch (_) {
              // Ignore cleanup failures for temp files
            }
          }
        }

        // Update book with cover path (silently)
        final updated = book.copyWith(coverPath: expectedCoverPath);
        await box.put(book.id, updated);
        generated++;
      } catch (e) {
        // Silently fail for books where cover extraction fails
      }
    }

    // Notify once at the end after all covers are generated
    if (generated > 0) {
      notifyListeners();
    }

    return generated;
  }
  
  /// Update the cover path for a book
  Future<void> updateCoverPath(String id, String coverPath) async {
    final book = getBook(id);
    if (book != null) {
      final updated = book.copyWith(coverPath: coverPath);
      await updateBook(updated);
    }
  }

  Future<void> _extractCover(String bookPath, String savePath) async {
    await covers_api.extractCover(bookPath: bookPath, savePath: savePath);
  }
}
