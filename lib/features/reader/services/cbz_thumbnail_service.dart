import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;

/// Service for asynchronous extraction, thumbnailing, and LRU memory caching
/// of comic/manga page thumbnails.
class CbzThumbnailService {
  static final Map<String, ui.Image> _cache = {};
  static final List<String> _order = [];
  static const int maxCacheEntries = 80;
  static final Map<String, Future<ui.Image?>> _inFlight = {};

  // Simple semaphore to limit concurrent extraction tasks (avoids I/O saturation)
  static int _runningTasks = 0;
  static const int _maxConcurrentTasks = 4;
  static final List<Completer<void>> _waitQueue = [];

  static Future<T> _runWithLimit<T>(Future<T> Function() action) async {
    while (_runningTasks >= _maxConcurrentTasks) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _runningTasks++;
    try {
      return await action();
    } finally {
      _runningTasks--;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }

  static String _cacheKey(String archivePath, int pageIndex, int maxWidth) =>
      '$archivePath:$pageIndex:$maxWidth';

  /// Check if a decoded thumbnail image is already in memory.
  static ui.Image? getCachedThumbnail({
    required String archivePath,
    required int pageIndex,
    int maxWidth = 220,
  }) {
    final key = _cacheKey(archivePath, pageIndex, maxWidth);
    if (_cache.containsKey(key)) {
      _order.remove(key);
      _order.add(key);
      return _cache[key];
    }
    return null;
  }

  /// Load and decode a thumbnail for a specific page.
  static Future<ui.Image?> getThumbnail({
    required String archivePath,
    required int pageIndex,
    int maxWidth = 220,
  }) async {
    final key = _cacheKey(archivePath, pageIndex, maxWidth);

    // 1. Check cache
    if (_cache.containsKey(key)) {
      _order.remove(key);
      _order.add(key);
      return _cache[key];
    }

    // 2. Share in-flight request
    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _load(archivePath, pageIndex, maxWidth, key);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<ui.Image?> _load(
    String archivePath,
    int pageIndex,
    int maxWidth,
    String key,
  ) async {
    return _runWithLimit(() async {
      try {
        final data = await cbz_api.getCbzPage(
          path: archivePath,
          index: pageIndex,
          maxWidth: maxWidth,
        );

        if (data.width <= 0 || data.height <= 0 || data.rgbaBytes.isEmpty) {
          return null;
        }

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          data.rgbaBytes,
          data.width,
          data.height,
          ui.PixelFormat.rgba8888,
          (image) {
            completer.complete(image);
          },
        );

        final image = await completer.future;

        // Save in LRU cache
        if (_cache.containsKey(key)) {
          _cache[key]?.dispose();
        }
        _cache[key] = image;
        _order.remove(key);
        _order.add(key);

        // Evict oldest if exceeding limit
        while (_order.length > maxCacheEntries) {
          final oldest = _order.removeAt(0);
          _cache[oldest]?.dispose();
          _cache.remove(oldest);
        }

        return image;
      } catch (e) {
        debugPrint('CbzThumbnailService: failed to load thumbnail for page $pageIndex: $e');
        return null;
      }
    });
  }

  /// Clear all cached thumbnails and dispose native image handles.
  static void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _order.clear();
    _inFlight.clear();
  }
}
