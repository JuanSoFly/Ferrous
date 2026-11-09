import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;
import 'package:reader_app/core/utils/performance.dart';
import '../models/page_corner_colors.dart';

class _ExtractionTask {
  final int pageIndex;
  final int maxWidth;
  int priority; // 1 = Immediate (visible page), 2 = Preload
  final Completer<ui.Image?> completer;
  final DateTime createdAt;

  _ExtractionTask({
    required this.pageIndex,
    required this.maxWidth,
    required this.priority,
    required this.completer,
  }) : createdAt = DateTime.now();
}

typedef CbzPageExtractor = Future<cbz_api.CbzPageData> Function(
  String path,
  int index,
  int? maxWidth,
);

/// Controller for serialized, priority-aware CBZ/CBR page image caching and preloading.
///
/// Features:
/// 1. Serialized archive extraction queue: never allows concurrent uncoordinated
///    reads against archive handles.
/// 2. Priority-aware scheduling: visible page (Priority 1) takes precedence over
///    background preloads (Priority 2).
/// 3. In-flight request sharing: swiping to a preloading page attaches to the existing
///    in-flight future and promotes it rather than duplicating or returning null.
/// 4. Persistent LRU page cache: keeps [currentPage - 2 ... currentPage + 3] alive in memory;
///    only evicts pages > 5 away when memory pressure requires it.
/// 5. Automatic retries with backoff on intermittent read errors.
class CbzCacheController {
  final String archivePath;
  final List<String> pageNames;
  final int maxCacheSize;

  // LRU cache of decoded images keyed by pageIndex
  final Map<int, ui.Image> _imageCache = {};
  final List<int> _cacheOrder = [];

  // In-flight extraction requests
  final Map<int, Future<ui.Image?>> _inFlightRequests = {};

  // Serialized task queue
  final List<_ExtractionTask> _taskQueue = [];
  bool _isProcessingQueue = false;
  bool _disposed = false;
  int _currentPage = 0;

  final Map<int, double> _aspectRatios = {};
  double? _averageAspectRatio;

  final Map<int, PageCornerColors> _cornerColors = {};

  final CbzPageExtractor? pageExtractor;
  final Duration retryDelay;

  CbzCacheController({
    required this.archivePath,
    required this.pageNames,
    this.maxCacheSize = 16,
    this.pageExtractor,
    this.retryDelay = const Duration(milliseconds: 100),
  });

  /// Current reading page index for distance-based priority and eviction.
  int get currentPage => _currentPage;

  /// Number of currently cached decoded images.
  int get cachedCount => _imageCache.length;

  /// Check whether an image is decoded in cache and immediately ready to render.
  bool isPageDecoded(int index, [int? maxWidth]) {
    return _imageCache.containsKey(index);
  }

  /// Get estimated aspect ratio for a page, or the global average if unknown.
  double? getEstimatedAspectRatio(int index, {double fallback = 0.70}) {
    return _aspectRatios[index] ?? _averageAspectRatio ?? fallback;
  }

  /// Get strictly verified known aspect ratio for a page, if already decoded.
  double? getKnownAspectRatio(int index) {
    return _aspectRatios[index];
  }

  /// All currently learned aspect ratios for the comic.
  Map<int, double> get allKnownAspectRatios => Map.unmodifiable(_aspectRatios);

  /// Get detected corner and edge colors for a page, if already extracted.
  PageCornerColors? getCornerColors(int index) {
    return _cornerColors[index];
  }

  /// All currently extracted corner colors for the comic.
  Map<int, PageCornerColors> get allKnownCornerColors => Map.unmodifiable(_cornerColors);

  /// Get an image for a specific page. Returns null if loading or not in cache.
  ui.Image? getCachedImage(int index, [int? maxWidth]) {
    if (index < 0 || index >= pageNames.length) return null;
    final img = _imageCache[index];
    if (img != null) {
      _touchCache(index);
      return img;
    }
    return null;
  }

  /// Load a page and add it to cache.
  ///
  /// If [isImmediate] is true (default), this task is assigned Priority 1 and processed ahead
  /// of any background preloads. If the page is already in flight, it attaches to the existing
  /// future and promotes its priority.
  Future<ui.Image?> loadPage(
    int index,
    int maxWidth, {
    bool isImmediate = true,
  }) async {
    if (_disposed) return null;
    if (index < 0 || index >= pageNames.length) return null;

    if (isImmediate) {
      _currentPage = index;
    }

    // 1. Return cached if available
    final cached = _imageCache[index];
    if (cached != null) {
      _touchCache(index);
      return cached.clone();
    }

    // 2. Attach to existing in-flight request if present
    if (_inFlightRequests.containsKey(index)) {
      if (isImmediate) {
        // Promote task in queue if pending
        final idx = _taskQueue.indexWhere((t) => t.pageIndex == index);
        if (idx != -1) {
          final task = _taskQueue.removeAt(idx);
          task.priority = 1;
          _taskQueue.insert(0, task);
        }
      }
      final future = _inFlightRequests[index]!;
      final result = await future;
      return result?.clone();
    }

    // 3. Queue new extraction task
    final completer = Completer<ui.Image?>();
    _inFlightRequests[index] = completer.future;

    final task = _ExtractionTask(
      pageIndex: index,
      maxWidth: maxWidth,
      priority: isImmediate ? 1 : 2,
      completer: completer,
    );

    if (isImmediate) {
      final insertPos = _taskQueue.lastIndexWhere((t) => t.priority == 1);
      if (insertPos == -1) {
        _taskQueue.insert(0, task);
      } else {
        _taskQueue.insert(insertPos + 1, task);
      }
    } else {
      _taskQueue.add(task);
    }

    _processQueue();

    final result = await completer.future;
    return result?.clone();
  }

  /// Process serialized extraction queue one task at a time.
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _disposed) return;
    _isProcessingQueue = true;

    try {
      while (_taskQueue.isNotEmpty && !_disposed) {
        // Sort by priority (1 before 2), then by insertion order for Priority 1,
        // or by distance to _currentPage for Priority 2.
        _taskQueue.sort((a, b) {
          if (a.priority != b.priority) {
            return a.priority.compareTo(b.priority);
          }
          if (a.priority == 1) {
            return a.createdAt.compareTo(b.createdAt);
          }
          final distA = (a.pageIndex - _currentPage).abs();
          final distB = (b.pageIndex - _currentPage).abs();
          if (distA != distB) {
            return distA.compareTo(distB);
          }
          return a.createdAt.compareTo(b.createdAt);
        });

        final task = _taskQueue.removeAt(0);

        if (_disposed) {
          if (!task.completer.isCompleted) {
            task.completer.complete(null);
          }
          _inFlightRequests.remove(task.pageIndex);
          continue;
        }

        // Drop stale background preloads if the user has navigated far away (> 5 pages away)
        if (task.priority == 2 && (task.pageIndex - _currentPage).abs() > 5) {
          if (!task.completer.isCompleted) {
            task.completer.complete(null);
          }
          _inFlightRequests.remove(task.pageIndex);
          continue;
        }

        // If page became cached while waiting in queue, complete immediately
        if (_imageCache.containsKey(task.pageIndex)) {
          _touchCache(task.pageIndex);
          final img = _imageCache[task.pageIndex]!;
          if (!task.completer.isCompleted) {
            task.completer.complete(img);
          }
          _inFlightRequests.remove(task.pageIndex);
          continue;
        }

        // Execute extraction with up to 2 retries (100ms backoff)
        ui.Image? decodedImage;
        int attempt = 0;
        const maxAttempts = 3;

        while (attempt < maxAttempts && decodedImage == null && !_disposed) {
          attempt++;
          try {
            decodedImage = await _extractAndDecodePage(task.pageIndex, task.maxWidth);
          } catch (e) {
            debugPrint('Extraction attempt $attempt failed for page ${task.pageIndex}: $e');
            if (attempt < maxAttempts && !_disposed) {
              if (retryDelay > Duration.zero) {
                await Future.delayed(retryDelay);
              }
            }
          }
        }

        if (decodedImage != null && !_disposed) {
          _addToCache(task.pageIndex, decodedImage);
          if (!task.completer.isCompleted) {
            task.completer.complete(decodedImage);
          }
        } else {
          if (!task.completer.isCompleted) {
            task.completer.complete(null);
          }
        }
        _inFlightRequests.remove(task.pageIndex);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<ui.Image> _extractAndDecodePage(int index, int maxWidth) async {
    final extractor = pageExtractor ??
        ((path, idx, maxW) => cbz_api.getCbzPage(
              path: path,
              index: idx,
              maxWidth: maxW,
            ));

    final data = await measureAsync(
      'get_cbz_page',
      () => extractor(archivePath, index, maxWidth),
      metadata: {'page': index, 'maxWidth': maxWidth},
    );

    if (data.width <= 0 || data.height <= 0 || data.rgbaBytes.isEmpty) {
      throw Exception('Extracted empty page bytes for page $index');
    }

    final ar = data.width / data.height;
    _aspectRatios[index] = ar;
    _averageAspectRatio = ar;

    // Extract noise-filtered corner and edge colors from raw RGBA buffer
    _cornerColors[index] = PageCornerColors.fromRgbaBytes(
      data.rgbaBytes,
      data.width,
      data.height,
    );

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data.rgbaBytes,
      data.width,
      data.height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );

    return await completer.future;
  }

  /// Preload adjacent pages with Priority 2 (background).
  void preloadAround(int index, int maxWidth) {
    if (_disposed) return;
    _currentPage = index;

    // Preload order: next page (N+1), previous page (N-1), +2, +3, -2
    final preloadTargets = <int>[
      index + 1,
      index - 1,
      index + 2,
      index + 3,
      index - 2,
    ];

    for (final p in preloadTargets) {
      if (p >= 0 && p < pageNames.length) {
        if (!_imageCache.containsKey(p) && !_inFlightRequests.containsKey(p)) {
          loadPage(p, maxWidth, isImmediate: false);
        }
      }
    }

    _pruneCacheAround(index);
  }

  void _pruneCacheAround(int currentIndex) {
    // Keep [currentIndex - 2 ... currentIndex + 3] safe in memory.
    // Only evict when (page - currentIndex).abs() > 5 or cache size exceeds maxCacheSize.
    final toEvict = <int>[];
    for (final p in _cacheOrder) {
      final dist = (p - currentIndex).abs();
      if (dist > 5 && (_imageCache.length - toEvict.length) > 6) {
        toEvict.add(p);
      }
    }

    for (final p in toEvict) {
      _cacheOrder.remove(p);
      _imageCache[p]?.dispose();
      _imageCache.remove(p);
    }

    // If cache size still exceeds maxCacheSize, evict oldest pages furthest from currentIndex
    while (_imageCache.length > maxCacheSize) {
      int? furthestPage;
      int maxDist = -1;
      for (final p in _cacheOrder) {
        if ((p - currentIndex).abs() <= 2) continue; // Don't evict immediate viewport window
        final d = (p - currentIndex).abs();
        if (d > maxDist) {
          maxDist = d;
          furthestPage = p;
        }
      }
      if (furthestPage != null) {
        _cacheOrder.remove(furthestPage);
        _imageCache[furthestPage]?.dispose();
        _imageCache.remove(furthestPage);
      } else {
        break;
      }
    }
  }

  void _addToCache(int index, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }

    // If already exists, replace with new decoded instance
    if (_imageCache.containsKey(index)) {
      _imageCache[index]?.dispose();
      _cacheOrder.remove(index);
    }

    _imageCache[index] = image;
    _cacheOrder.add(index);
    _pruneCacheAround(_currentPage);
  }

  void _touchCache(int index) {
    _cacheOrder.remove(index);
    _cacheOrder.add(index);
  }

  /// Clear all resources and pending tasks.
  void dispose() {
    _disposed = true;
    for (final task in _taskQueue) {
      if (!task.completer.isCompleted) {
        task.completer.complete(null);
      }
    }
    _taskQueue.clear();
    _inFlightRequests.clear();
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
    _cacheOrder.clear();
    _aspectRatios.clear();
    _cornerColors.clear();
  }
}
