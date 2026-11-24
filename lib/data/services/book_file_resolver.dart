import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/services/saf_service.dart';

class ResolvedBookFile {
  final String path;
  final bool isTemp;
  bool _isReleased = false;

  ResolvedBookFile({
    required this.path,
    required this.isTemp,
  });

  bool get isTemporary => isTemp;
  bool get isReleased => _isReleased;
}

class BookFileResolver {
  final SafService _safService;

  BookFileResolver({SafService? safService})
      : _safService = safService ?? SafService();

  // Static reference counting for active temporary files across all resolver instances
  static final Map<String, int> _activeRefs = {};
  // Static reference counting for active media directories
  static final Map<String, int> _activeMediaRefs = {};

  static String _normalize(String path) {
    return path.replaceAll('\\', '/');
  }

  /// Checks if a file path is currently in use by an active reader or task.
  static bool isPathInUse(String path) {
    final key = _normalize(path);
    final count = _activeRefs[key] ?? 0;
    return count > 0;
  }

  /// Checks if a media directory key is currently in use.
  static bool isMediaInUse(String key) {
    final count = _activeMediaRefs[key] ?? 0;
    return count > 0;
  }

  /// Increments reference count for an active media directory key.
  static void retainMedia(String key) {
    _activeMediaRefs[key] = (_activeMediaRefs[key] ?? 0) + 1;
  }

  /// Decrements reference count for a media key, and deletes [dir] recursively
  /// ONLY if the count drops to 0 and the directory is safe to delete.
  static Future<void> releaseMedia({
    required String key,
    required Directory dir,
  }) async {
    final current = _activeMediaRefs[key] ?? 1;
    final next = current - 1;
    if (next <= 0) {
      _activeMediaRefs.remove(key);
      try {
        if (await dir.exists()) {
          final normDir = _normalize(dir.path);
          // Strict safety guard: never delete user books directory or documents
          if (normDir.contains('/files/books/') && !normDir.endsWith('_media')) {
            debugPrint('Safety guard prevented deletion of non-media dir: $normDir');
            return;
          }
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('Failed to delete media dir ${dir.path}: $e');
      }
    } else {
      _activeMediaRefs[key] = next;
    }
  }

  /// Resolves the given book to a filesystem path.
  /// For linked books, copies to cache (or reuses existing cache) and increments reference count.
  Future<ResolvedBookFile> resolve(
    Book book, {
    bool forceRefresh = false,
  }) async {
    if (book.sourceType == BookSourceType.imported ||
        (book.sourceUri == null || book.sourceUri!.isEmpty)) {
      if (book.filePath.isEmpty) {
        throw StateError('Imported book has no file path.');
      }
      return ResolvedBookFile(path: book.filePath, isTemp: false);
    }

    final uri = book.sourceUri;
    if (uri == null || uri.isEmpty) {
      throw StateError('Linked book has no source URI.');
    }

    final suggestedName = _buildSuggestedName(book);
    final tempPath = await _safService.copyUriToCache(
      uri: uri,
      suggestedName: suggestedName,
      force: forceRefresh,
    );

    // Track active reference for temporary cached file
    final key = _normalize(tempPath);
    _activeRefs[key] = (_activeRefs[key] ?? 0) + 1;

    return ResolvedBookFile(path: tempPath, isTemp: true);
  }

  /// Decrements reference count for a resolved temporary file.
  /// If reference count drops to 0 AND the file is temporary AND inside the cache directory,
  /// deletes the file safely. Idempotent per ResolvedBookFile handle.
  Future<void> release(ResolvedBookFile? resolved) async {
    if (resolved == null || resolved._isReleased) return;
    resolved._isReleased = true;

    final key = _normalize(resolved.path);
    final current = _activeRefs[key];
    if (current != null) {
      final next = current - 1;
      if (next <= 0) {
        _activeRefs.remove(key);
      } else {
        _activeRefs[key] = next;
        return; // Still in use by another reader or task
      }
    }

    // Only delete if it was marked temporary
    if (!resolved.isTemp) return;

    try {
      final file = File(resolved.path);
      if (!await file.exists()) return;

      // Strict safety guards:
      final normPath = _normalize(resolved.path);
      // NEVER delete inside filesDir/books/ or app_flutter
      if (normPath.contains('/files/books/') || normPath.contains('/app_flutter/')) {
        debugPrint('Safety guard prevented deletion of book in user data: $normPath');
        return;
      }

      // Verify the path is inside temporary / cache directory
      bool isUnderTemp = false;
      try {
        final tempDir = await getTemporaryDirectory();
        final normTemp = _normalize(tempDir.path);
        if (normPath.startsWith(normTemp)) {
          isUnderTemp = true;
        }
      } catch (_) {}

      if (!isUnderTemp) {
        final sysTemp = _normalize(Directory.systemTemp.path);
        if (normPath.startsWith(sysTemp)) {
          isUnderTemp = true;
        }
      }

      if (!isUnderTemp) {
        debugPrint('Safety guard: path is not within temporary directory: $normPath');
        return;
      }

      await file.delete();
    } catch (e) {
      debugPrint('Failed to delete temporary resolved file ${resolved.path}: $e');
    }
  }

  String _buildSuggestedName(Book book) {
    var base = book.title.trim();
    if (base.isEmpty) {
      base = 'book_${book.id.substring(0, 8)}';
    }
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ext = book.format.trim().toLowerCase();
    if (ext.isEmpty) return base;
    if (base.toLowerCase().endsWith('.$ext')) return base;
    return '$base.$ext';
  }

  @visibleForTesting
  static void resetRefCountsForTesting() {
    _activeRefs.clear();
    _activeMediaRefs.clear();
  }

  @visibleForTesting
  static int getActiveRefCount(String path) {
    return _activeRefs[_normalize(path)] ?? 0;
  }

  @visibleForTesting
  static int getActiveMediaRefCount(String key) {
    return _activeMediaRefs[key] ?? 0;
  }
}
