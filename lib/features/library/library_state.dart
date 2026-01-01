import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/core/models/book.dart';
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
  final Book? splitPendingBook;

  // Memoization cache
  final List<Book>? _cachedFilteredBooks;
  final String? _cachedQuery;
  final List<Book>? _cachedSourceBooks;

  const LibraryState({
    this.isLoading = false,
    this.books = const [],
    this.error,
    this.statusMessage,
    this.searchQuery = '',
    this.splitPendingBook,
    List<Book>? cachedFilteredBooks,
    String? cachedQuery,
    List<Book>? cachedSourceBooks,
  })  : _cachedFilteredBooks = cachedFilteredBooks,
        _cachedQuery = cachedQuery,
        _cachedSourceBooks = cachedSourceBooks;

  LibraryState copyWith({
    bool? isLoading,
    List<Book>? books,
    String? error,
    String? statusMessage,
    String? searchQuery,
    Book? splitPendingBook,
    bool clearSplitPending = false,
  }) {
    final newBooks = books ?? this.books;
    final newQuery = searchQuery ?? this.searchQuery;

    // Preserve cache if underlying data hasn't changed
    final booksChanged = newBooks != this.books;
    final queryChanged = newQuery != this.searchQuery;

    return LibraryState(
      isLoading: isLoading ?? this.isLoading,
      books: newBooks,
      error: error,
      statusMessage: statusMessage,
      searchQuery: newQuery,
      splitPendingBook: clearSplitPending ? null : (splitPendingBook ?? this.splitPendingBook),
      cachedFilteredBooks: (booksChanged || queryChanged) ? null : _cachedFilteredBooks,
      cachedQuery: (booksChanged || queryChanged) ? null : _cachedQuery,
      cachedSourceBooks: (booksChanged || queryChanged) ? null : _cachedSourceBooks,
    );
  }

  /// Returns books filtered by searchQuery.
  List<Book> get filteredBooks {
    if (searchQuery.isEmpty) return books;
    
    // Check memoization cache
    if (_cachedFilteredBooks != null && 
        _cachedQuery == searchQuery && 
        _cachedSourceBooks == books) {
      return _cachedFilteredBooks;
    }

    final query = searchQuery.toLowerCase();
    final result = books.where((book) {
      return book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query);
    }).toList();
    return result;
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  final BookRepository _bookRepository;
  final SafService _safService = SafService();
  bool _coverGenerationStarted = false;
  Timer? _searchDebounce;

  LibraryController(this._bookRepository) : super(const LibraryState()) {
    loadBooks();
    _maybeGenerateMissingCovers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void loadBooks() {
    final books = _bookRepository.getAllBooks();
    books.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    state = state.copyWith(books: books);
  }

  void _maybeGenerateMissingCovers() {
    if (_coverGenerationStarted) return;
    final books = _bookRepository.getAllBooks();
    final needsCovers = books.any((book) {
      final coverPath = book.coverPath;
      if (coverPath == null || coverPath.isEmpty) return true;
      return !File(coverPath).existsSync();
    });
    if (!needsCovers) return;

    _coverGenerationStarted = true;
    unawaited(_generateCoversInBackground());
  }
  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      state = state.copyWith(searchQuery: query);
    });
  }

  void setSplitPendingBook(Book book) {
    state = state.copyWith(splitPendingBook: book);
  }

  void clearSplitPending() {
    state = state.copyWith(clearSplitPending: true);
  }

  Future<void> pickAndScanDirectory(SafStorageMode mode) async {
    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        statusMessage: 'Opening folder picker...',
      );

      final refs = await _safService.pickFolder(mode: mode);

      if (refs.isEmpty) {
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
      final appDir = await _getAppDocumentsDirectory();
      final coversDir = '$appDir/covers';

      await _ensureDirectoryExists(coversDir);

      await _bookRepository.generateCovers(coversDir);

      loadBooks();
    } catch (e) {
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
