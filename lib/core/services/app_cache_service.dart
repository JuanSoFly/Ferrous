import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ferrous/data/services/book_file_resolver.dart';

/// Centralized service for measuring, managing, and purging temporary application caches.
/// Strictly manages temporary cache subdirectories without ever touching user data
/// (such as imported books in `filesDir/books/`, covers, or Hive databases).
class AppCacheService {
  static const int defaultMaxTotalBytes = 50 * 1024 * 1024; // 50 MB
  static const Duration defaultMaxAge = Duration(hours: 24);

  /// Computes the exact djb2 64-bit hash matching Rust mobi.rs:
  /// `book_path.bytes().fold(5381u64, |h, b| (h << 5).wrapping_add(h).wrapping_add(b as u64))`
  static String mobiHash(String bookPath) {
    var hash = BigInt.from(5381);
    final mask64 = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(bookPath)) {
      hash = (((hash << 5) + hash) + BigInt.from(b)) & mask64;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  /// Locates the MOBI media cache directory for a given book file path.
  static Future<Directory?> getMobiMediaDirForPath(String bookPath) async {
    final hash = mobiHash(bookPath);
    try {
      final tempDir = await getTemporaryDirectory();
      final androidDir = Directory('${tempDir.path}/mobi_media/$hash');
      if (await androidDir.exists()) return androidDir;
    } catch (_) {}

    final sysDir = Directory('${Directory.systemTemp.path}/ferrous_mobi_media/$hash');
    if (await sysDir.exists()) return sysDir;

    // Default to the standard tempDir location
    try {
      final tempDir = await getTemporaryDirectory();
      return Directory('${tempDir.path}/mobi_media/$hash');
    } catch (_) {
      return sysDir;
    }
  }

  /// Returns the list of managed cache root directories.
  static Future<List<Directory>> getManagedCacheDirectories() async {
    final dirs = <Directory>[];
    try {
      final tempDir = await getTemporaryDirectory();
      dirs.add(Directory('${tempDir.path}/saf_cache'));
      dirs.add(Directory('${tempDir.path}/epub_media'));
      dirs.add(Directory('${tempDir.path}/mobi_media'));
    } catch (e) {
      debugPrint('Error getting temporary directory: $e');
    }

    // Also include desktop fallback MOBI cache directory if present
    final sysMobi = Directory('${Directory.systemTemp.path}/ferrous_mobi_media');
    dirs.add(sysMobi);

    return dirs;
  }

  /// Recursively computes the total size in bytes of all managed temporary caches.
  static Future<int> calculateCacheSizeBytes() async {
    var totalBytes = 0;
    final managedDirs = await getManagedCacheDirectories();

    for (final dir in managedDirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              totalBytes += await entity.length();
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('Error calculating cache size for ${dir.path}: $e');
      }
    }

    // Also account for loose legacy temporary files in root temporary directory
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (name.startsWith('linked_') || name.contains('.tmp_')) {
              try {
                totalBytes += await entity.length();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    return totalBytes;
  }

  /// Enforces a strict storage budget on startup.
  /// Prunes orphaned atomic temp files, stale cache entries older than [maxAge],
  /// and LRU items if total size exceeds [maxTotalBytes].
  /// Skips any path currently in active use according to [BookFileResolver.isPathInUse].
  static Future<void> enforceStartupBudget({
    int maxTotalBytes = defaultMaxTotalBytes,
    Duration maxAge = defaultMaxAge,
  }) async {
    final now = DateTime.now();

    // Phase 1: Prune loose temporary files in the root temporary directory
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (name.startsWith('linked_') || name.contains('.tmp_')) {
              if (!BookFileResolver.isPathInUse(entity.path)) {
                try {
                  await entity.delete();
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}

    final managedDirs = await getManagedCacheDirectories();

    // Phase 2: Delete orphaned .tmp_* files and entries older than maxAge across managed directories
    for (final dir in managedDirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entry in dir.list(recursive: false, followLinks: false)) {
          final path = entry.path;
          if (BookFileResolver.isPathInUse(path)) continue;

          final name = path.split(Platform.pathSeparator).last;
          if (name.contains('.tmp_')) {
            try {
              await entry.delete(recursive: true);
              continue;
            } catch (_) {}
          }

          try {
            final stat = await entry.stat();
            if (now.difference(stat.modified) > maxAge) {
              await entry.delete(recursive: true);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Phase 3: If still exceeding maxTotalBytes, evict oldest items first
    var currentSize = await calculateCacheSizeBytes();
    if (currentSize <= maxTotalBytes) return;

    final candidates = <MapEntry<FileSystemEntity, DateTime>>[];
    for (final dir in managedDirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entry in dir.list(recursive: false, followLinks: false)) {
          if (BookFileResolver.isPathInUse(entry.path)) continue;
          try {
            final stat = await entry.stat();
            candidates.add(MapEntry(entry, stat.modified));
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Sort oldest first
    candidates.sort((a, b) => a.value.compareTo(b.value));

    for (final candidate in candidates) {
      if (currentSize <= maxTotalBytes) break;
      final entity = candidate.key;
      if (BookFileResolver.isPathInUse(entity.path)) continue;

      var entitySize = 0;
      try {
        if (entity is File) {
          entitySize = await entity.length();
        } else if (entity is Directory) {
          await for (final f in entity.list(recursive: true, followLinks: false)) {
            if (f is File) {
              entitySize += await f.length();
            }
          }
        }
        await entity.delete(recursive: true);
        currentSize -= entitySize;
      } catch (_) {}
    }
  }

  /// Purges all non-active entries from managed cache directories.
  /// Returns the total number of bytes freed.
  /// Strict safety guard: NEVER touches `filesDir/books/`, `covers/`, or `*.hive`.
  static Future<int> clearAllCaches() async {
    final beforeBytes = await calculateCacheSizeBytes();
    final managedDirs = await getManagedCacheDirectories();

    for (final dir in managedDirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entry in dir.list(recursive: false, followLinks: false)) {
          final path = entry.path;
          // Safety guard: skip any file/media currently in active use
          if (BookFileResolver.isPathInUse(path)) continue;

          // Extra safety check: ensure the path is NOT inside books/ or covers/ or hive
          final normalized = path.replaceAll('\\', '/');
          if (normalized.contains('/files/books/') ||
              normalized.contains('/covers/') ||
              normalized.endsWith('.hive')) {
            debugPrint('Safety guard prevented deletion in clearAllCaches: $normalized');
            continue;
          }

          try {
            await entry.delete(recursive: true);
          } catch (e) {
            debugPrint('Failed to delete cache entry $path: $e');
          }
        }
      } catch (e) {
        debugPrint('Error clearing cache directory ${dir.path}: $e');
      }
    }

    // Clean loose temp files in root temp directory
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entry in tempDir.list(recursive: false, followLinks: false)) {
          if (entry is File) {
            final name = entry.path.split(Platform.pathSeparator).last;
            if ((name.startsWith('linked_') || name.contains('.tmp_')) &&
                !BookFileResolver.isPathInUse(entry.path)) {
              try {
                await entry.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    // Clean plugin temporary files on non-Android platforms if available
    if (!Platform.isAndroid) {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}
    }

    final afterBytes = await calculateCacheSizeBytes();
    final freedBytes = beforeBytes - afterBytes;
    return freedBytes > 0 ? freedBytes : 0;
  }

  /// Formats byte counts into human-readable strings.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
