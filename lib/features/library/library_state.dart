import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:uuid/uuid.dart';

enum SortType {
  name,
  fileName,
  fileFormat,
  fileSize,
  modifiedTime,
  dateRead,
}

enum SortOrder {
  ascending,
  descending,
}

class LibraryState {
  final bool isLoading;
  final List<Book> books;
  final String? error;
  final String? statusMessage;
  final String searchQuery;
  final Book? splitPendingBook;
  final bool isGeneratingCovers;
  final int totalCoversToGenerate;

  final SortType sortBy;
  final SortOrder sortOrder;
  final Set<String> selectedFormats;

  final bool filterNoAuthor;
  final bool filterNoCollection;
  final bool filterUnread;
  final Set<String> bookIdsInCollections;

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
    this.isGeneratingCovers = false,
    this.totalCoversToGenerate = 0,
    this.sortBy = SortType.dateRead,
    this.sortOrder = SortOrder.descending,
    this.selectedFormats = const {},
    this.filterNoAuthor = false,
    this.filterNoCollection = false,
    this.filterUnread = false,
    this.bookIdsInCollections = const {},
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
    bool? isGeneratingCovers,
    int? totalCoversToGenerate,
    SortType? sortBy,
    SortOrder? sortOrder,
    Set<String>? selectedFormats,
    bool? filterNoAuthor,
    bool? filterNoCollection,
    bool? filterUnread,
    Set<String>? bookIdsInCollections,
  }) {
    final newBooks = books ?? this.books;
    final newQuery = searchQuery ?? this.searchQuery;
    final newSortBy = sortBy ?? this.sortBy;
    final newSortOrder = sortOrder ?? this.sortOrder;
    final newSelectedFormats = selectedFormats ?? this.selectedFormats;
    final newFilterNoAuthor = filterNoAuthor ?? this.filterNoAuthor;
    final newFilterNoCollection = filterNoCollection ?? this.filterNoCollection;
    final newFilterUnread = filterUnread ?? this.filterUnread;
    final newBookIdsInCollections = bookIdsInCollections ?? this.bookIdsInCollections;

    // Preserve cache if underlying data hasn't changed
    final booksChanged = newBooks != this.books;
    final queryChanged = newQuery != this.searchQuery;
    final sortByChanged = newSortBy != this.sortBy;
    final sortOrderChanged = newSortOrder != this.sortOrder;
    final formatsChanged = newSelectedFormats != this.selectedFormats;
    final noAuthorChanged = newFilterNoAuthor != this.filterNoAuthor;
    final noCollectionChanged = newFilterNoCollection != this.filterNoCollection;
    final unreadChanged = newFilterUnread != this.filterUnread;
    final collectionsChanged = newBookIdsInCollections != this.bookIdsInCollections;

    final changed = booksChanged ||
        queryChanged ||
        sortByChanged ||
        sortOrderChanged ||
        formatsChanged ||
        noAuthorChanged ||
        noCollectionChanged ||
        unreadChanged ||
        collectionsChanged;

    return LibraryState(
      isLoading: isLoading ?? this.isLoading,
      books: newBooks,
      error: error,
      statusMessage: statusMessage,
      searchQuery: newQuery,
      splitPendingBook: clearSplitPending ? null : (splitPendingBook ?? this.splitPendingBook),
      isGeneratingCovers: isGeneratingCovers ?? this.isGeneratingCovers,
      totalCoversToGenerate: totalCoversToGenerate ?? this.totalCoversToGenerate,
      sortBy: newSortBy,
      sortOrder: newSortOrder,
      selectedFormats: newSelectedFormats,
      filterNoAuthor: newFilterNoAuthor,
      filterNoCollection: newFilterNoCollection,
      filterUnread: newFilterUnread,
      bookIdsInCollections: newBookIdsInCollections,
      cachedFilteredBooks: changed ? null : _cachedFilteredBooks,
      cachedQuery: changed ? null : _cachedQuery,
      cachedSourceBooks: changed ? null : _cachedSourceBooks,
    );
  }

  /// Returns books filtered and sorted.
  List<Book> get filteredBooks {
    // Check memoization cache
    if (_cachedFilteredBooks != null && 
        _cachedQuery == searchQuery && 
        _cachedSourceBooks == books) {
      return _cachedFilteredBooks;
    }

    Iterable<Book> result = books;

    // 1. Filter by search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((book) {
        return book.title.toLowerCase().contains(query) ||
            book.author.toLowerCase().contains(query);
      });
    }

    // 2. Filter by selected file formats
    if (selectedFormats.isNotEmpty) {
      result = result.where((book) => selectedFormats.contains(book.format.toLowerCase()));
    }

    // 2a. Filter by No Author
    if (filterNoAuthor) {
      result = result.where((book) => book.author.isEmpty || book.author.toLowerCase() == 'unknown author');
    }

    // 2b. Filter by No Collection
    if (filterNoCollection) {
      result = result.where((book) => !bookIdsInCollections.contains(book.id));
    }

    // 2c. Filter by Unread
    if (filterUnread) {
      result = result.where((book) => book.progress == 0.0);
    }

    // 3. Sort books
    final sortedList = result.toList();
    sortedList.sort((a, b) {
      int comparison = 0;
      switch (sortBy) {
        case SortType.name:
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SortType.fileName:
          final aName = a.filePath.split('/').last.toLowerCase();
          final bName = b.filePath.split('/').last.toLowerCase();
          comparison = aName.compareTo(bName);
          break;
        case SortType.fileFormat:
          comparison = a.format.toLowerCase().compareTo(b.format.toLowerCase());
          break;
        case SortType.fileSize:
          comparison = a.safeFileSize.compareTo(b.safeFileSize);
          break;
        case SortType.modifiedTime:
          comparison = a.safeFileLastModified.compareTo(b.safeFileLastModified);
          break;
        case SortType.dateRead:
          comparison = a.lastOpened.compareTo(b.lastOpened);
          break;
      }
      return sortOrder == SortOrder.ascending ? comparison : -comparison;
    });

    return sortedList;
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  final BookRepository _bookRepository;
  final SafService _safService = SafService();
  bool _coverGenerationStarted = false;
  Timer? _searchDebounce;

  LibraryController(this._bookRepository) : super(const LibraryState()) {
    loadBooks();
    unawaited(_maybeGenerateMissingCovers());
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

  Future<void> _maybeGenerateMissingCovers() async {
    if (_coverGenerationStarted) return;
    final books = _bookRepository.getAllBooks();

    int booksNeedingCovers = 0;
    for (final book in books) {
      final coverPath = book.coverPath;
      if (coverPath == null || coverPath.isEmpty) {
        booksNeedingCovers++;
        continue;
      }
      if (!await File(coverPath).exists()) {
        booksNeedingCovers++;
      }
    }

    if (booksNeedingCovers == 0) return;

    _coverGenerationStarted = true;
    state = state.copyWith(
      isGeneratingCovers: true,
      totalCoversToGenerate: booksNeedingCovers,
    );
    await _generateCoversInBackground();
  }

  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      state = state.copyWith(searchQuery: query);
    });
  }

  void setSortBy(SortType type) {
    state = state.copyWith(sortBy: type);
  }

  void setSortOrder(SortOrder order) {
    state = state.copyWith(sortOrder: order);
  }

  void toggleFormatFilter(String format) {
    final normalized = format.toLowerCase();
    final newFormats = Set<String>.from(state.selectedFormats);
    if (newFormats.contains(normalized)) {
      newFormats.remove(normalized);
    } else {
      newFormats.add(normalized);
    }
    state = state.copyWith(selectedFormats: newFormats);
  }

  void clearFormatFilters() {
    state = state.copyWith(selectedFormats: const {});
  }

  void applyFilters({
    required Set<String> selectedFormats,
    required bool filterNoAuthor,
    required bool filterNoCollection,
    required bool filterUnread,
    required Set<String> bookIdsInCollections,
  }) {
    state = state.copyWith(
      selectedFormats: selectedFormats,
      filterNoAuthor: filterNoAuthor,
      filterNoCollection: filterNoCollection,
      filterUnread: filterUnread,
      bookIdsInCollections: bookIdsInCollections,
    );
  }

  void clearAllFilters() {
    state = state.copyWith(
      selectedFormats: const {},
      filterNoAuthor: false,
      filterNoCollection: false,
      filterUnread: false,
    );
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
        fileSize: ref.size,
        fileLastModified: ref.lastModified != null 
            ? DateTime.fromMillisecondsSinceEpoch(ref.lastModified!) 
            : null,
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

      state = state.copyWith(isGeneratingCovers: false);
      loadBooks();
    } catch (e) {
      state = state.copyWith(isGeneratingCovers: false);
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
