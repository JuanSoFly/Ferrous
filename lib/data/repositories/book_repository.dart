import 'package:hive/hive.dart';
import 'package:reader_app/data/models/book.dart';

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

  Future<void> updateReadingProgress(String id, int currentPage,
      {int? totalPages}) async {
    final book = getBook(id);
    if (book != null) {
      final updated = book.copyWith(
        currentPage: currentPage,
        totalPages: totalPages,
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

  bool bookExists(String path) {
    return box.values.any((book) => book.path == path);
  }
}
