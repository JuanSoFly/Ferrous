import 'dart:io';
import 'package:hive/hive.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/covers.dart' as covers_api;

class BookRepository {
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
  }

  Future<void> addBooks(List<Book> books) async {
    final Map<String, Book> bookMap = {for (var b in books) b.id: b};
    await box.putAll(bookMap);
  }

  Future<void> updateBook(Book book) async {
    await box.put(book.id, book);
  }

  Future<void> deleteBook(String id) async {
    await box.delete(id);
  }

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
      await updateBook(updated);
    }
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
    // Import dynamically to avoid circular dependencies
    // Using direct import since it's a simple API call
    final books = getAllBooks();
    int generated = 0;

    final resolver = BookFileResolver();
    for (final book in books) {
      if (book.coverPath != null && book.coverPath!.isNotEmpty) {
        continue; // Already has a cover
      }

      try {
        final savePath = '$coversDir/${book.id}.png';
        final resolved = await resolver.resolve(book);
        try {
          // Call Rust API - this will be imported from the generated bindings
          await _extractCover(resolved.path, savePath);
        } finally {
          if (resolved.isTemp) {
            try {
              await File(resolved.path).delete();
            } catch (_) {
              // Ignore cleanup failures for temp files
            }
          }
        }

        // Update book with cover path
        final updated = book.copyWith(coverPath: savePath);
        await updateBook(updated);
        generated++;
      } catch (e) {
        // Silently fail for books where cover extraction fails
        // This is expected for some formats or corrupted files
      }
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
