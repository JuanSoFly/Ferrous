import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/src/rust/api/library.dart'; // FRB generated
import 'package:state_notifier/state_notifier.dart';
import 'package:uuid/uuid.dart';

class LibraryState {
  final bool isLoading;
  final List<Book> books;
  final String? error;

  const LibraryState({
    this.isLoading = false,
    this.books = const [],
    this.error,
  });

  LibraryState copyWith({
    bool? isLoading,
    List<Book>? books,
    String? error,
  }) {
    return LibraryState(
      isLoading: isLoading ?? this.isLoading,
      books: books ?? this.books,
      error: error,
    );
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  final BookRepository _bookRepository;

  LibraryController(this._bookRepository) : super(const LibraryState()) {
    loadBooks();
  }

  void loadBooks() {
    final books = _bookRepository.getAllBooks();
    // Sort by recently opened?
    books.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    state = state.copyWith(books: books);
  }

  Future<void> pickAndScanDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        return; // User canceled
      }

      state = state.copyWith(isLoading: true, error: null);

      // Call Rust backend
      // Call Rust backend
      final scannedMetadata = await scanLibrary(rootPath: selectedDirectory);

      for (var meta in scannedMetadata) {
        // Check if we already have this book (by path)
        if (!_bookRepository.bookExists(meta.path)) {
          final newBook = Book(
            id: const Uuid().v4(),
            title: meta.title,
            author: meta.author,
            path: meta.path,
            format: meta.path.split('.').last.toLowerCase(),
          );
          await _bookRepository.addBook(newBook);
        }
      }

      // Refresh list
      loadBooks();
      state = state.copyWith(isLoading: false);
      
      // Generate covers in background
      _generateCoversInBackground();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
  
  Future<void> _generateCoversInBackground() async {
    try {
      // Get the app's document directory for storing covers
      final appDir = await _getAppDocumentsDirectory();
      final coversDir = '$appDir/covers';
      
      // Create covers directory if it doesn't exist
      await _ensureDirectoryExists(coversDir);
      
      // Generate covers
      await _bookRepository.generateCovers(coversDir);
      
      // Refresh to show new covers
      loadBooks();
    } catch (e) {
      // Silently fail - cover generation is optional
    }
  }
  
  Future<String> _getAppDocumentsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
  
  Future<void> _ensureDirectoryExists(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
