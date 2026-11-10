import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/models/library_location.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;
import 'package:uuid/uuid.dart';

class LibraryLocationScanResult {
  final int addedCount;
  final int totalScanned;
  final String? errorMessage;
  final bool isSuccess;

  const LibraryLocationScanResult({
    this.addedCount = 0,
    this.totalScanned = 0,
    this.errorMessage,
    this.isSuccess = true,
  });
}

/// Repository responsible for managing configured library scan directories,
/// folder persistence, rescan workflows, and storage mode configurations.
class LibraryLocationRepository extends ChangeNotifier {
  final BookRepository _bookRepository;
  final SafService _safService;

  List<LibraryLocation> _locations = const [];
  bool _isLoading = false;
  bool _isScanningAll = false;
  String? _error;

  Box<String>? _desktopLocationsBox;
  Box<String>? _desktopModesBox;

  LibraryLocationRepository({
    required BookRepository bookRepository,
    SafService? safService,
  })  : _bookRepository = bookRepository,
        _safService = safService ?? SafService();

  List<LibraryLocation> get locations => _locations;
  bool get isLoading => _isLoading;
  bool get isScanningAll => _isScanningAll;
  String? get error => _error;

  int get totalBooksInLocations {
    return _locations.fold<int>(0, (sum, loc) => sum + loc.bookCount);
  }

  int get totalStorageBytes {
    return _locations.fold<int>(0, (sum, loc) => sum + loc.totalSizeBytes);
  }

  Future<void> init() async {
    if (!Platform.isAndroid) {
      try {
        _desktopLocationsBox = await Hive.openBox<String>('desktop_library_locations');
        _desktopModesBox = await Hive.openBox<String>('desktop_library_location_modes');
      } catch (e) {
        debugPrint('Failed to open desktop location Hive boxes: $e');
      }
    }
    await refreshLocations();
  }

  /// Reloads all configured locations, calculates current book counts and storage sizes.
  Future<void> refreshLocations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final allBooks = _bookRepository.getAllBooks();
      final List<LibraryLocation> loadedLocations = [];

      if (Platform.isAndroid) {
        final folderDetails = await _safService.getPersistedFolderDetails();
        for (final info in folderDetails) {
          final matchingBooks = allBooks
              .where((b) => LibraryLocation.bookBelongsToLocation(b, info.uri))
              .toList();

          final totalBytes = matchingBooks.fold<int>(
            0,
            (sum, b) => sum + b.safeFileSize,
          );

          final displayName = info.displayName.isNotEmpty
              ? info.displayName
              : LibraryLocation.extractNameFromUri(info.uri);

          final readablePath = LibraryLocation.extractReadablePath(info.uri);

          loadedLocations.add(
            LibraryLocation(
              id: info.uri,
              uri: info.uri,
              displayName: displayName,
              readablePath: readablePath,
              storageMode: info.mode,
              isValid: info.isValid,
              bookCount: matchingBooks.length,
              totalSizeBytes: totalBytes,
            ),
          );
        }
      } else {
        // Desktop / non-Android platforms
        final paths = _desktopLocationsBox?.values.toList() ?? [];
        for (final path in paths) {
          final exists = Directory(path).existsSync();
          final modeStr = _desktopModesBox?.get(path);
          final mode = modeStr == 'imported'
              ? SafStorageMode.imported
              : SafStorageMode.linked;

          final matchingBooks = allBooks
              .where((b) => LibraryLocation.bookBelongsToLocation(b, path))
              .toList();

          final totalBytes = matchingBooks.fold<int>(
            0,
            (sum, b) => sum + b.safeFileSize,
          );

          loadedLocations.add(
            LibraryLocation(
              id: path,
              uri: path,
              displayName: LibraryLocation.extractNameFromUri(path),
              readablePath: path.replaceAll('\\', '/'),
              storageMode: mode,
              isValid: exists,
              bookCount: matchingBooks.length,
              totalSizeBytes: totalBytes,
            ),
          );
        }
      }

      _locations = loadedLocations;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Prompts user to pick a folder and adds all discovered books.
  Future<LibraryLocationScanResult> addLocation({
    required SafStorageMode mode,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        final refs = await _safService.pickFolder(mode: mode);
        if (refs.isEmpty) {
          _isLoading = false;
          notifyListeners();
          return const LibraryLocationScanResult(
            addedCount: 0,
            totalScanned: 0,
            isSuccess: true,
          );
        }

        final addedCount = await _addBooksFromRefs(refs);
        await _generateCoversInBackground();
        await refreshLocations();

        return LibraryLocationScanResult(
          addedCount: addedCount,
          totalScanned: refs.length,
          isSuccess: true,
        );
      } else {
        // Desktop directory picker
        final selectedDir = await FilePicker.platform.getDirectoryPath();
        if (selectedDir == null || selectedDir.isEmpty) {
          _isLoading = false;
          notifyListeners();
          return const LibraryLocationScanResult(
            addedCount: 0,
            totalScanned: 0,
            isSuccess: true,
          );
        }

        // Save path to desktop locations box
        if (_desktopLocationsBox != null) {
          if (!_desktopLocationsBox!.values.contains(selectedDir)) {
            await _desktopLocationsBox!.add(selectedDir);
          }
          await _desktopModesBox?.put(selectedDir, mode.name);
        }

        final refs = await _scanDirectoryDesktop(selectedDir, mode);
        final addedCount = await _addBooksFromRefs(refs);
        await _generateCoversInBackground();
        await refreshLocations();

        return LibraryLocationScanResult(
          addedCount: addedCount,
          totalScanned: refs.length,
          isSuccess: true,
        );
      }
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return LibraryLocationScanResult(
        addedCount: 0,
        totalScanned: 0,
        errorMessage: e.toString(),
        isSuccess: false,
      );
    }
  }

  /// Rescans a specific location for newly added or modified books.
  Future<LibraryLocationScanResult> rescanLocation(
    LibraryLocation location,
  ) async {
    // Set scanning flag on target location
    _locations = _locations.map((loc) {
      if (loc.id == location.id) {
        return loc.copyWith(isScanning: true);
      }
      return loc;
    }).toList();
    notifyListeners();

    try {
      List<SafBookRef> refs = [];
      if (Platform.isAndroid) {
        refs = await _safService.rescanFolder(
          uri: location.uri,
          mode: location.storageMode,
        );
      } else {
        refs = await _scanDirectoryDesktop(location.uri, location.storageMode);
      }

      final addedCount = await _addBooksFromRefs(refs);
      if (addedCount > 0) {
        await _generateCoversInBackground();
      }

      await refreshLocations();

      return LibraryLocationScanResult(
        addedCount: addedCount,
        totalScanned: refs.length,
        isSuccess: true,
      );
    } catch (e) {
      await refreshLocations();
      return LibraryLocationScanResult(
        addedCount: 0,
        totalScanned: 0,
        errorMessage: e.toString(),
        isSuccess: false,
      );
    }
  }

  /// Rescans all configured locations.
  Future<LibraryLocationScanResult> rescanAllLocations() async {
    _isScanningAll = true;
    notifyListeners();

    try {
      List<SafBookRef> refs = [];
      if (Platform.isAndroid) {
        refs = await _safService.rescanPersistedFolders();
      } else {
        for (final loc in _locations) {
          final locRefs = await _scanDirectoryDesktop(loc.uri, loc.storageMode);
          refs.addAll(locRefs);
        }
      }

      final addedCount = await _addBooksFromRefs(refs);
      if (addedCount > 0) {
        await _generateCoversInBackground();
      }

      _isScanningAll = false;
      await refreshLocations();

      return LibraryLocationScanResult(
        addedCount: addedCount,
        totalScanned: refs.length,
        isSuccess: true,
      );
    } catch (e) {
      _isScanningAll = false;
      await refreshLocations();
      return LibraryLocationScanResult(
        addedCount: 0,
        totalScanned: 0,
        errorMessage: e.toString(),
        isSuccess: false,
      );
    }
  }

  /// Removes a configured location, optionally deleting all associated books from library.
  Future<void> removeLocation(
    LibraryLocation location, {
    required bool removeAssociatedBooks,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (removeAssociatedBooks) {
        final booksToDelete = getBooksForLocation(location);
        for (final book in booksToDelete) {
          // Delete cover file if present
          if (book.coverPath != null && book.coverPath!.isNotEmpty) {
            try {
              final coverFile = File(book.coverPath!);
              if (await coverFile.exists()) {
                await coverFile.delete();
              }
            } catch (_) {}
          }
          await _bookRepository.deleteBook(book.id);
        }
      }

      if (Platform.isAndroid) {
        await _safService.removePersistedFolder(location.uri);
      } else {
        if (_desktopLocationsBox != null) {
          final keysToRemove = <dynamic>[];
          for (var key in _desktopLocationsBox!.keys) {
            if (_desktopLocationsBox!.get(key) == location.uri) {
              keysToRemove.add(key);
            }
          }
          for (var key in keysToRemove) {
            await _desktopLocationsBox!.delete(key);
          }
          await _desktopModesBox?.delete(location.uri);
        }
      }

      await refreshLocations();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Cleans up stale permissions for locations that are no longer accessible.
  Future<int> cleanupStaleLocations() async {
    _isLoading = true;
    notifyListeners();

    int removed = 0;
    try {
      if (Platform.isAndroid) {
        removed = await _safService.cleanupStalePermissions();
      } else {
        if (_desktopLocationsBox != null) {
          final keysToRemove = <dynamic>[];
          for (var key in _desktopLocationsBox!.keys) {
            final path = _desktopLocationsBox!.get(key);
            if (path != null && !Directory(path).existsSync()) {
              keysToRemove.add(key);
              await _desktopModesBox?.delete(path);
              removed++;
            }
          }
          for (var key in keysToRemove) {
            await _desktopLocationsBox!.delete(key);
          }
        }
      }
      await refreshLocations();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
    return removed;
  }

  /// Updates storage mode for a location.
  Future<void> updateLocationMode(
    LibraryLocation location,
    SafStorageMode newMode,
  ) async {
    try {
      if (Platform.isAndroid) {
        await _safService.updateFolderMode(uri: location.uri, mode: newMode);
      } else {
        await _desktopModesBox?.put(location.uri, newMode.name);
      }
      await refreshLocations();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Returns all books associated with this location.
  List<Book> getBooksForLocation(LibraryLocation location) {
    return _bookRepository
        .getAllBooks()
        .where((b) => LibraryLocation.bookBelongsToLocation(b, location.uri))
        .toList();
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

      var title = _titleFromDisplayName(ref.displayName);
      var author = 'Unknown Author';
      final format = ref.format.isNotEmpty ? ref.format : _formatFromName(ref.displayName);
      final fmtLower = format.toLowerCase();

      if ((fmtLower == 'mobi' || fmtLower == 'azw' || fmtLower == 'azw3') &&
          ref.filePath != null &&
          ref.filePath!.isNotEmpty &&
          File(ref.filePath!).existsSync()) {
        try {
          final realTitle = await rust_mobi.getMobiTitle(path: ref.filePath!);
          if (realTitle.isNotEmpty && realTitle != 'Unknown Title') {
            title = realTitle;
          }
          final realAuthor = await rust_mobi.getMobiAuthor(path: ref.filePath!);
          if (realAuthor.isNotEmpty && realAuthor != 'Unknown Author') {
            author = realAuthor;
          }
        } catch (_) {}
      }

      final newBook = Book(
        id: const Uuid().v4(),
        title: title,
        author: author,
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

  Future<List<SafBookRef>> _scanDirectoryDesktop(
    String dirPath,
    SafStorageMode mode,
  ) async {
    final List<SafBookRef> refs = [];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return refs;

    const supportedExts = {
      'pdf',
      'epub',
      'cbz',
      'cbr',
      'docx',
      'txt',
      'mobi',
      'azw',
      'azw3',
    };

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final dot = name.lastIndexOf('.');
        if (dot <= 0 || dot == name.length - 1) continue;
        final ext = name.substring(dot + 1).toLowerCase();

        if (supportedExts.contains(ext)) {
          final stat = await entity.stat();
          refs.add(
            SafBookRef(
              sourceType: mode == SafStorageMode.linked
                  ? BookSourceType.linked
                  : BookSourceType.imported,
              filePath: entity.path,
              sourceUri: entity.uri.toString(),
              displayName: name,
              format: ext,
              size: stat.size,
              lastModified: stat.modified.millisecondsSinceEpoch,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Desktop folder scan error: $e');
    }
    return refs;
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
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = '${appDir.path}/covers';
      final dir = Directory(coversDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _bookRepository.generateCovers(coversDir);
    } catch (e) {
      debugPrint('Background cover generation error: $e');
    }
  }
}
