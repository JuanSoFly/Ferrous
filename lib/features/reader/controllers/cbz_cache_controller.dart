import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;
import 'package:reader_app/core/utils/performance.dart';

/// Controller for CBZ page image caching and preloading.
/// This replaces the static cache in _CbzPageImageState.
class CbzCacheController {
  final String archivePath;
  final List<String> pageNames;
  final int maxCacheSize;

  // LRU cache of decoded images
  final Map<String, ui.Image> _imageCache = {};
  final List<String> _cacheOrder = []; 
  final Set<String> _loadingPages = {}; 

  CbzCacheController({
    required this.archivePath,
    required this.pageNames,
    this.maxCacheSize = 8,
  });

  String _getCacheKey(int index, int maxWidth) {
    if (index < 0 || index >= pageNames.length) return '';
    return '$archivePath:${pageNames[index]}:$maxWidth';
  }

  /// Get an image for a specific page. Returns null if loading or not in cache.
  ui.Image? getCachedImage(int index, int maxWidth) {
    final key = _getCacheKey(index, maxWidth);
    if (_imageCache.containsKey(key)) {
      _touchCache(key);
      return _imageCache[key];
    }
    return null;
  }

  /// Load a page and add it to cache.
  Future<ui.Image?> loadPage(int index, int maxWidth) async {
    if (index < 0 || index >= pageNames.length) return null;
    
    final key = _getCacheKey(index, maxWidth);
    
    // Return cached if available
    if (_imageCache.containsKey(key)) {
      _touchCache(key);
      return _imageCache[key]!.clone();
    }
    
    // Prevent duplicate loading
    if (_loadingPages.contains(key)) return null;
    _loadingPages.add(key);
    
    try {
      final data = await measureAsync('get_cbz_page', () => cbz_api.getCbzPage(
        path: archivePath,
        index: index,
        maxWidth: maxWidth,
      ), metadata: {'page': index, 'maxWidth': maxWidth});
      
      // Decode RGBA bytes to Flutter Image
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        data.rgbaBytes,
        data.width,
        data.height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );
      
      final decodedImage = await completer.future;
      
      // Add to cache
      _addToCache(key, decodedImage.clone());
      
      // Preload around this page
      preloadAround(index, maxWidth);
      
      return decodedImage;
    } catch (e) {
      debugPrint('Error loading CBZ page $index: $e');
      rethrow;
    } finally {
      _loadingPages.remove(key);
    }
  }

  /// Preload next 3 pages and 1 page behind.
  void preloadAround(int index, int maxWidth) {
    // Next 3 pages
    for (var i = 1; i <= 3; i++) {
      final nextIdx = index + i;
      if (nextIdx >= pageNames.length) break;
      _preloadOne(nextIdx, maxWidth);
    }
    // Previous page
    if (index > 0) {
      _preloadOne(index - 1, maxWidth);
    }
  }

  void _preloadOne(int index, int maxWidth) {
    final key = _getCacheKey(index, maxWidth);
    if (!_imageCache.containsKey(key) && !_loadingPages.contains(key)) {
      _loadAndCacheSilently(index, maxWidth);
    }
  }

  Future<void> _loadAndCacheSilently(int index, int maxWidth) async {
    try {
      final key = _getCacheKey(index, maxWidth);
      _loadingPages.add(key);
      
      final data = await cbz_api.getCbzPage(
        path: archivePath,
        index: index,
        maxWidth: maxWidth,
      );

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        data.rgbaBytes,
        data.width,
        data.height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );

      final image = await completer.future;
      _addToCache(key, image);
    } catch (e) {
      // Ignore background errors
    } finally {
      final key = _getCacheKey(index, maxWidth);
      _loadingPages.remove(key);
    }
  }

  void _addToCache(String key, ui.Image image) {
    if (key.isEmpty) return;
    
    // Evict oldest if full
    while (_cacheOrder.length >= maxCacheSize) {
      final oldest = _cacheOrder.removeAt(0);
      _imageCache[oldest]?.dispose();
      _imageCache.remove(oldest);
    }
    
    _imageCache[key] = image;
    _cacheOrder.add(key);
  }

  void _touchCache(String key) {
    if (key.isEmpty) return;
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
  }

  /// Clear all resources
  void dispose() {
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
    _cacheOrder.clear();
    _loadingPages.clear();
  }
}
