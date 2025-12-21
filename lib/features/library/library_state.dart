import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:uuid/uuid.dart';

class LibraryState {
  final bool isLoading;
  final List<Book> books;
  final String? error;
  final String? statusMessage;
  final String searchQuery;
  final Book? splitPendingBook; // For split-screen: first book selected

  const LibraryState({
    this.isLoading = false,
    this.books = const [],
    this.error,
    this.statusMessage,
    this.searchQuery = '',
    this.splitPendingBook,
  });

  LibraryState copyWith({
    bool? isLoading,
    List<Book>? books,
    String? error,
    String? statusMessage,
    String? searchQuery,
    Book? splitPendingBook,
    bool clearSplitPending = false,
  }) {
    return LibraryState(
      isLoading: isLoading ?? this.isLoading,
      books: books ?? this.books,
      error: error,
      statusMessage: statusMessage,
      searchQuery: searchQuery ?? this.searchQuery,
      splitPendingBook: clearSplitPending ? null : (splitPendingBook ?? this.splitPendingBook),
    );
  }

  /// Returns books filtered by searchQuery.
  List<Book> get filteredBooks {
    if (searchQuery.isEmpty) return books;
    final query = searchQuery.toLowerCase();
    return books.where((book) {
      return book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query);
    }).toList();
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  final BookRepository _bookRepository;
  final SafService _safService = SafService();

  LibraryController(this._bookRepository) : super(const LibraryState()) {
    loadBooks();
  }

  void loadBooks() {
    final books = _bookRepository.getAllBooks();
    // Sort by recently opened
    books.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    state = state.copyWith(books: books);
  }

  /// Updates the search query for filtering books.
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Sets a book as pending for split-screen view.
  void setSplitPendingBook(Book book) {
    state = state.copyWith(splitPendingBook: book);
  }

  /// Clears the split-pending book.
  void clearSplitPending() {
    state = state.copyWith(clearSplitPending: true);
  }

  /// Opens the folder picker using SAF and links or imports any ebook files found.
  Future<void> pickAndScanDirectory(SafStorageMode mode) async {
    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        statusMessage: 'Opening folder picker...',
      );

      final refs = await _safService.pickFolder(mode: mode);

      if (refs.isEmpty) {
        // User canceled or no supported files found
        state = state.copyWith(isLoading: false, statusMessage: null);
        return;
      }

      state = state.copyWith(
        statusMessage: mode == SafStorageMode.linked
            ? 'Linking ${refs.length} books...'
            : 'Importing ${refs.length} books...',
      );

      final addedCount = await _addBooksFromRefs(refs);

      // Refresh list
      loadBooks();
      state = state.copyWith(
        isLoading: false,
        statusMessage: addedCount > 0 
            ? 'Added $addedCount new books'
            : 'No new books found',
      );

      // Generate covers in background
      _generateCoversInBackground();
      
      // Clear status message after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          state = state.copyWith(statusMessage: null);
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        statusMessage: null,
      );
    }
  }

  /// Rescans all previously granted folders for new books.
  Future<void> rescanFolders() async {
    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        statusMessage: 'Rescanning folders...',
      );

      final refs = await _safService.rescanPersistedFolders();

      if (refs.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          statusMessage: 'No new books found',
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            state = state.copyWith(statusMessage: null);
          }
        });
        return;
      }

      final addedCount = await _addBooksFromRefs(refs);

      loadBooks();
      state = state.copyWith(
        isLoading: false,
        statusMessage: addedCount > 0
            ? 'Added $addedCount new books'
            : 'No new books found',
      );

      if (addedCount > 0) {
        _generateCoversInBackground();
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          state = state.copyWith(statusMessage: null);
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        statusMessage: null,
      );
    }
  }

  Future<int> _addBooksFromRefs(List<SafBookRef> refs) async {
    int addedCount = 0;
    for (final ref in refs) {
      if (_bookRepository.bookExists(
        filePath: ref.filePath,
        sourceUri: ref.sourceUri,
      )) {
        continue;
      }

      final title = _titleFromDisplayName(ref.displayName);
      final format = ref.format.isNotEmpty ? ref.format : _formatFromName(ref.displayName);
      final newBook = Book(
        id: const Uuid().v4(),
        title: title,
        author: 'Unknown Author',
        filePath: ref.filePath ?? '',
        format: format.toLowerCase(),
        sourceType: ref.sourceType,
        sourceUri: ref.sourceUri,
      );
      await _bookRepository.addBook(newBook);
      addedCount++;
    }
    return addedCount;
  }

  String _titleFromDisplayName(String name) {
    if (name.isEmpty) return 'Unknown Title';
    final dot = name.lastIndexOf('.');
    if (dot > 0) return name.substring(0, dot);
    return name;
  }

  String _formatFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
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
