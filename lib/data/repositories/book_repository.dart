import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/covers.dart' as covers_api;

import 'package:reader_app/core/utils/performance.dart';

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
    }
  }
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

  static final Semaphore _coverSemaphore = Semaphore(2);

  Future<int> generateCovers(String coversDir) async {
    final books = getAllBooks();
    final resolver = BookFileResolver();
    
    final List<Future<bool>> tasks = [];

    for (final book in books) {
      tasks.add(() async {
        final existingCoverPath = book.coverPath;
        final hasExistingCoverFile = existingCoverPath != null &&
            existingCoverPath.isNotEmpty &&
            File(existingCoverPath).existsSync();

        final expectedCoverPath = '$coversDir/${book.id}.png';

        if (hasExistingCoverFile) {
          return false;
        }

        if (File(expectedCoverPath).existsSync()) {
          final updated = book.copyWith(coverPath: expectedCoverPath);
          await box.put(book.id, updated);
          return true;
        }

        await _coverSemaphore.acquire();
        try {
          final resolved = await resolver.resolve(book);
          try {
            await _extractCover(resolved.path, expectedCoverPath);
          } finally {
            if (resolved.isTemp) {
              try {
                await File(resolved.path).delete();
              } catch (_) {}
            }
          }

          final updated = book.copyWith(coverPath: expectedCoverPath);
          await box.put(book.id, updated);
          return true;
        } catch (e) {
          debugPrint('Cover Extraction failed for ${book.title}: $e');
          return false;
        } finally {
          _coverSemaphore.release();
        }
      }());
    }

    final results = await Future.wait(tasks);
    final generated = results.where((r) => r).length;

    if (generated > 0) {
      notifyListeners();
    }

    return generated;
  }
  
  Future<void> updateCoverPath(String id, String coverPath) async {
    final book = getBook(id);
    if (book != null) {
      final updated = book.copyWith(coverPath: coverPath);
      await updateBook(updated);
    }
  }

  Future<void> _extractCover(String bookPath, String savePath) async {
    await measureAsync('extract_cover', () => covers_api.extractCover(bookPath: bookPath, savePath: savePath), metadata: {'format': bookPath.split('.').last});
  }
}
