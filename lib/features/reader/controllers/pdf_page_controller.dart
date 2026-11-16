import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ferrous/src/rust/api/pdf.dart' as pdf_api;
import 'package:ferrous/src/rust/api/pdf.dart' show PdfTextRect;
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/services/book_file_resolver.dart';
import 'package:ferrous/core/utils/performance.dart';
import 'package:ferrous/core/services/diagnostic_logger.dart';
import '../models/pdf_chapter.dart';
import '../models/page_corner_colors.dart';
import '../services/pdf_outline_service.dart';

/// LRU resident cache for decoded GPU ui.Image handles with post-frame deferred disposal.
class PdfGpuImageCache {
  int maxResident;
  final LinkedHashMap<int, ui.Image> _cache = LinkedHashMap();

  PdfGpuImageCache({this.maxResident = 8});

  ui.Image? get(int pageIndex) {
    if (!_cache.containsKey(pageIndex)) return null;
    final img = _cache.remove(pageIndex)!;
    _cache[pageIndex] = img;
    return img;
  }

  void put(int pageIndex, ui.Image image) {
    if (_cache.containsKey(pageIndex)) {
      final old = _cache.remove(pageIndex);
      if (old != image) {
        _safeDispose(old);
      }
    }
    while (_cache.length >= maxResident) {
      final oldestKey = _cache.keys.first;
      final evicted = _cache.remove(oldestKey);
      _safeDispose(evicted);
    }
    _cache[pageIndex] = image;
  }

  bool contains(int pageIndex) => _cache.containsKey(pageIndex);

  void clear() {
    for (final img in _cache.values) {
      _safeDispose(img);
    }
    _cache.clear();
  }

  void _safeDispose(ui.Image? image) {
    if (image == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      image.dispose();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

class PdfPageController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  final ScrollController scrollController = ScrollController();
  Timer? _progressSaveTimer;
  double _lastScrollPosition;
  ReadingMode _readingMode;

  PdfPageController({
    required this.book,
    required this.repository,
    Size? initialViewportSize,
  }) : _pageIndex = book.currentPage,
       _readingMode = book.readingMode,
       _lastScrollPosition = book.scrollPosition,
       _viewerSize = initialViewportSize ?? Size.zero {
    scrollController.addListener(_handleScrollUpdate);
  }

  bool hasPageImage(int index) => getPageUiImage(index) != null;

  PageCornerColors? getPageCornerColors(int index) => _cornerColorsCache[index];

  double? getPageAspectRatio(int index) {
    final size = _renderedPageSizes[index];
    if (size != null && size.height > 0) {
      return (size.width / size.height).clamp(0.2, 5.0);
    }
    return _defaultAspectRatio > 0 ? _defaultAspectRatio : 0.70;
  }

  ResolvedBookFile? _resolvedFile;
  Uint8List? _currentPageImage;
  bool _isLoading = true;
  String? _error;
  int _pageIndex = 0;
  int _pageCount = 0;
  Size _renderedPageSize = Size.zero;
  Size _logicalPageSize = Size.zero;
  Size _viewerSize = Size.zero;
  double _devicePixelRatio = 2.0;
  double _currentZoomScale = 1.0;
  bool _disposed = false;

  final Map<int, Size> _renderedPageSizes = {};
  double _defaultAspectRatio = 0.70;

  // Maximum safe texture dimension (2048) to guarantee retina sharpness without memory bloat
  static const int _maxTextureDimension = 2048;

  int get prefetchAhead => isContinuousMode ? 3 : 2;
  int get prefetchBehind => isContinuousMode ? 2 : 1;

  final Set<int> _pendingRenderQueue = {};
  bool _isRustWorkerBusy = false;
  int? _currentlyRenderingIndex;

  // GlobalKeys per page for layout anchoring
  List<GlobalKey> _pageKeys = [];
  List<GlobalKey> get pageKeys => _pageKeys;

  // Adaptive background corner & edge colors
  final Map<int, PageCornerColors> _cornerColorsCache = {};
  PageCornerColors? get currentCornerColors => _cornerColorsCache[_pageIndex];
  PageCornerColors? getCornerColorsForPage(int pageIndex) => _cornerColorsCache[pageIndex];

  // Chapters & Table of Contents
  List<PdfChapter> _chapters = const [];
  List<PdfChapter> get chapters => _chapters;
  bool _isLoadingChapters = true;
  bool get isLoadingChapters => _isLoadingChapters;

  bool _isRestoringScroll = false;
  bool get isRestoringScroll => _isRestoringScroll;

  PdfChapter? get currentChapter {
    if (_chapters.isEmpty) return null;
    for (int i = _chapters.length - 1; i >= 0; i--) {
      if (_chapters[i].pageIndex <= _pageIndex) {
        return _chapters[i];
      }
    }
    return _chapters.first;
  }

  // Text loading state
  final Map<int, String> _pageTextCache = {};
  final Map<int, Future<String>> _pageTextInFlight = {};
  final Map<int, List<PdfTextRect>> _pageCharBoundsCache = {};
  String _currentPageText = '';
  bool _isTextLoading = false;
  String? _textError;
  int _textRequestId = 0;

  // GPU texture cache & render generation tracking
  late final PdfGpuImageCache _gpuImageCache = PdfGpuImageCache(
    maxResident: isContinuousMode ? 8 : 4,
  );
  ui.Image? getPageUiImage(int index) => _gpuImageCache.get(index);
  int _renderEpoch = 0;
  int get renderEpoch => _renderEpoch;
  final Map<int, List<Completer<void>>> _pageRenderCompleters = {};

  final Map<int, pdf_api.SanitizedPdfText> _sanitizedTextCache = {};
  Map<int, pdf_api.SanitizedPdfText> get sanitizedTextCache => _sanitizedTextCache;

  // Getters
  ResolvedBookFile? get resolvedFile => _resolvedFile;
  Uint8List? get currentPageImage => _currentPageImage;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pageIndex => _pageIndex;
  int get pageCount => _pageCount;
  Size get renderedPageSize => _renderedPageSize;
  Size get logicalPageSize => _logicalPageSize;
  Size get viewerSize => _viewerSize;
  double get currentZoomScale => _currentZoomScale;

  String get currentPageText => _currentPageText;
  bool get isTextLoading => _isTextLoading;
  String? get textError => _textError;
  Map<int, String> get pageTextCache => _pageTextCache;
  Map<int, List<PdfTextRect>> get pageCharBoundsCache => _pageCharBoundsCache;

  ReadingMode get readingMode => _readingMode;
  bool get isContinuousMode =>
      _readingMode == ReadingMode.verticalContinuous ||
      _readingMode == ReadingMode.webtoon ||
      _readingMode == ReadingMode.horizontalContinuous;

  void _handleScrollUpdate() {
    if (!isContinuousMode) return;
    if (_isRestoringScroll) return;
    _syncCurrentPageFromScroll();
    _scheduleContinuousProgressSave();
  }

  void _scheduleContinuousProgressSave() {
    if (_progressSaveTimer?.isActive ?? false) return;
    _progressSaveTimer = Timer(const Duration(milliseconds: 300), () {
      saveContinuousProgress();
    });
  }

  void flushContinuousProgressSave() {
    _progressSaveTimer?.cancel();
    saveContinuousProgress();
  }

  void _syncCurrentPageFromScroll() {
    if (_isRestoringScroll) return;
    if (!scrollController.hasClients || _pageCount == 0 || _pageKeys.isEmpty) return;

    RenderBox? viewportBox;
    try {
      final scrollCtx = scrollController.position.context.notificationContext;
      viewportBox = scrollCtx?.findRenderObject() as RenderBox?;
    } catch (_) {}

    if (viewportBox == null || !viewportBox.hasSize) return;

    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
    final focusPoint = isHorizontal
        ? viewportBox.size.width * 0.35
        : viewportBox.size.height * 0.35;

    int? bestIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < _pageCount; i++) {
      if (i >= _pageKeys.length) break;
      final ctx = _pageKeys[i].currentContext;
      if (ctx == null) continue;

      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;

      final itemStart = isHorizontal
          ? renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx
          : renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      final itemExtent = isHorizontal ? renderBox.size.width : renderBox.size.height;
      final itemEnd = itemStart + itemExtent;

      if (itemStart <= focusPoint && itemEnd > focusPoint) {
        bestIndex = i;
        break;
      }

      final dist = (itemStart - focusPoint).abs();
      if (dist < minDistance) {
        minDistance = dist;
        bestIndex = i;
      }
    }

    if (bestIndex != null && bestIndex != _pageIndex) {
      _pageIndex = bestIndex;
      notifyListeners();
    }
  }

  void saveContinuousProgress() {
    if (!scrollController.hasClients || _pageCount == 0 || _isRestoringScroll) return;

    _syncCurrentPageFromScroll();

    final offset = scrollController.offset;
    _lastScrollPosition = offset;

    final effectiveTotalPages = _pageCount > 0 ? _pageCount : (book.totalPages > 0 ? book.totalPages : 0);
    if (effectiveTotalPages <= 0) return;

    repository.updateReadingProgress(
      book.id,
      currentPage: _pageIndex,
      totalPages: effectiveTotalPages,
      scrollPosition: offset,
      readingMode: _readingMode,
    );
  }

  double calculateEstimatedOffsetForPage(int targetPage, double spacing) {
    if (targetPage <= 0) return 0.0;
    final defaultAr = _defaultAspectRatio > 0 ? _defaultAspectRatio : 0.70;
    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
    final isWebtoon = _readingMode == ReadingMode.webtoon;

    double offset = isWebtoon ? 0.0 : 16.0;

    for (int i = 0; i < targetPage; i++) {
      final size = _renderedPageSizes[i];
      final ar = (size != null && size.height > 0)
          ? (size.width / size.height).clamp(0.2, 5.0)
          : defaultAr;

      double extent;
      if (isHorizontal) {
        final effH = _viewerSize.height > 0 ? _viewerSize.height : 800.0;
        extent = effH * ar;
      } else {
        final effW = _viewerSize.width > 0 ? _viewerSize.width : 600.0;
        extent = effW / ar;
      }

      offset += extent + spacing;
    }
    return offset;
  }

  void restoreContinuousScroll() {
    if (!scrollController.hasClients || _pageCount == 0) return;
    if (_lastScrollPosition <= 0 && _pageIndex <= 0) {
      _isRestoringScroll = false;
      return;
    }

    _isRestoringScroll = true;
    final isWebtoon = _readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;
    final targetOffset = _lastScrollPosition > 0
        ? _lastScrollPosition
        : calculateEstimatedOffsetForPage(_pageIndex, spacing);

    void tryRestore() {
      if (!scrollController.hasClients || _disposed) {
        _isRestoringScroll = false;
        return;
      }
      final position = scrollController.position;
      if (!position.hasContentDimensions) {
        SchedulerBinding.instance.addPostFrameCallback((_) => tryRestore());
        return;
      }

      final clamped = targetOffset.clamp(0.0, position.maxScrollExtent);
      if ((position.pixels - clamped).abs() > 1.0) {
        scrollController.jumpTo(clamped);
      }
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _isRestoringScroll = false;
      });
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => tryRestore());
  }

  Future<ui.Image> _createUiImageFromRgba(Uint8List rgbaBytes, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgbaBytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    descriptor.dispose();
    buffer.dispose();
    codec.dispose();
    return frameInfo.image;
  }

  void updateReadingMode(ReadingMode mode) {
    if (_readingMode == mode) return;

    final effectiveTotalPages = _pageCount > 0 ? _pageCount : (book.totalPages > 0 ? book.totalPages : 0);

    // Save exact progress before switching
    if (isContinuousMode) {
      saveContinuousProgress();
    } else if (effectiveTotalPages > 0) {
      repository.updateReadingProgress(
        book.id,
        currentPage: _pageIndex,
        totalPages: effectiveTotalPages,
        readingMode: mode,
      );
    }

    final wasContinuous = isContinuousMode;
    _readingMode = mode;
    _gpuImageCache.maxResident = isContinuousMode ? 8 : 4;
    repository.updateReadingProgress(book.id, readingMode: mode);

    if (isContinuousMode) {
      _isRestoringScroll = true;
      final isWebtoon = _readingMode == ReadingMode.webtoon;
      final spacing = isWebtoon ? 1.0 : 12.0;
      final targetScroll = calculateEstimatedOffsetForPage(_pageIndex, spacing);

      void tryJump() {
        if (!scrollController.hasClients || _disposed) {
          _isRestoringScroll = false;
          return;
        }
        final position = scrollController.position;
        if (!position.hasContentDimensions) {
          SchedulerBinding.instance.addPostFrameCallback((_) => tryJump());
          return;
        }
        scrollController.jumpTo(targetScroll.clamp(0.0, position.maxScrollExtent));

        // Stage 2: Micro-anchor to the exact render box if already laid out
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_disposed || !scrollController.hasClients) {
            _isRestoringScroll = false;
            return;
          }
          if (_pageIndex < _pageKeys.length) {
            final ctx = _pageKeys[_pageIndex].currentContext;
            if (ctx != null) {
              final box = ctx.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
                final viewport = scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
                if (viewport != null && viewport.hasSize) {
                  final offset = isHorizontal
                      ? box.localToGlobal(Offset.zero, ancestor: viewport).dx
                      : box.localToGlobal(Offset.zero, ancestor: viewport).dy;
                  if (offset.abs() > 2.0) {
                    final corrected = (scrollController.offset + offset).clamp(0.0, scrollController.position.maxScrollExtent);
                    scrollController.jumpTo(corrected);
                  }
                }
              }
            }
          }
          _isRestoringScroll = false;
        });
      }

      SchedulerBinding.instance.addPostFrameCallback((_) => tryJump());
    } else {
      _isRestoringScroll = false;
      if (wasContinuous) {
        // Switching from continuous to paged: ensure target page is fully rendered immediately
        renderPage(_pageIndex, userInitiated: true);
      }
    }

    notifyListeners();
  }

  void jumpToPage(int targetPage) {
    if (targetPage < 0 || targetPage >= _pageCount) return;
    if (isContinuousMode) {
      final isWebtoon = _readingMode == ReadingMode.webtoon;
      final spacing = isWebtoon ? 1.0 : 12.0;
      final offset = calculateEstimatedOffsetForPage(targetPage, spacing);
      if (scrollController.hasClients) {
        final clamped = offset.clamp(0.0, scrollController.position.maxScrollExtent);
        scrollController.jumpTo(clamped);
      }
      _pageIndex = targetPage;
      notifyListeners();
    } else {
      renderPage(targetPage, userInitiated: true);
    }
  }

  void _saveProgressOnDispose() {
    if (isContinuousMode) {
      saveContinuousProgress();
    } else {
      final effectiveTotalPages = _pageCount > 0 ? _pageCount : (book.totalPages > 0 ? book.totalPages : 0);
      if (effectiveTotalPages > 0) {
        repository.updateReadingProgress(
          book.id,
          currentPage: _pageIndex,
          totalPages: effectiveTotalPages,
        );
      }
    }
  }

  Size getLogicalPageSize(int index) {
    final renderedSize = _renderedPageSizes[index];
    if (renderedSize == null || renderedSize.isEmpty || _viewerSize.isEmpty) {
      return Size.zero;
    }
    final widthClamped = renderedSize.width.clamp(1.0, double.infinity);
    final heightClamped = renderedSize.height.clamp(1.0, double.infinity);
    final aspectRatio = widthClamped / heightClamped;

    if (_readingMode == ReadingMode.verticalContinuous || _readingMode == ReadingMode.webtoon) {
      final w = _viewerSize.width;
      return Size(w, w / aspectRatio);
    } else if (_readingMode == ReadingMode.horizontalContinuous) {
      final h = _viewerSize.height;
      return Size(h * aspectRatio, h);
    }

    final viewerAspect = _viewerSize.width / _viewerSize.height;
    if (aspectRatio > viewerAspect) {
      return Size(_viewerSize.width, _viewerSize.width / aspectRatio);
    } else {
      return Size(_viewerSize.height * aspectRatio, _viewerSize.height);
    }
  }

  void updateViewportSize(Size newSize, [double? dpr]) {
    final effectiveDpr = (dpr ?? _devicePixelRatio).clamp(2.0, 3.0);
    if (_viewerSize.isEmpty) {
      _viewerSize = newSize;
      _devicePixelRatio = effectiveDpr;
      return;
    }

    final dw = (newSize.width - _viewerSize.width).abs();
    final dh = (newSize.height - _viewerSize.height).abs();
    if (dw < _viewerSize.width * 0.10 && dh < _viewerSize.height * 0.10) {
      _viewerSize = newSize;
      _devicePixelRatio = effectiveDpr;
      return;
    }

    _viewerSize = newSize;
    _devicePixelRatio = effectiveDpr;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (hasListeners && _resolvedFile != null && !_isLoading) {
        renderPage(_pageIndex);
      }
    });
  }

  void nextPage() {
    if (_pageIndex < _pageCount - 1) {
      renderPage(_pageIndex + 1, userInitiated: true);
    }
  }

  void previousPage() {
    if (_pageIndex > 0) {
      renderPage(_pageIndex - 1, userInitiated: true);
    }
  }

  set devicePixelRatio(double ratio) {
    _devicePixelRatio = ratio.clamp(2.0, 3.0);
  }

  void preloadPage(int index) {
    requestPageRender(index, isActivePage: false);
  }

  Future<void> loadDocument() async {
    await measureAsync('pdf_load_document', () async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      Object? failure;
      try {
        await _loadDocumentInternal();
        if (_disposed) return;
        return;
      } catch (e) {
        if (_disposed) return;
        failure = e;
      }

      if (_shouldRetryPdfOpen(failure)) {
        try {
          await _loadDocumentInternal(forceRefresh: true);
          if (_disposed) return;
          return;
        } catch (e) {
          if (_disposed) return;
          failure = e;
        }
      }

      debugPrint('PDF load error: $failure');
      DiagnosticLogger.instance.logError('PDF::Load', failure);
      _error = _formatPdfError(failure);
      _isLoading = false;
      notifyListeners();
    }, metadata: {'book_id': book.id});
  }

  /// Request a page render with prioritization and distance-based scheduling.
  void requestPageRender(int index, {bool isActivePage = false}) {
    if (_disposed || _resolvedFile == null) return;
    if (index < 0 || (_pageCount > 0 && index >= _pageCount)) return;
    if (hasPageImage(index)) return;

    if (isActivePage) {
      // Only cancel Rust if Rust is currently rendering a distant page (> 1 page away)
      if (_currentlyRenderingIndex != null &&
          (_currentlyRenderingIndex! - index).abs() > 1) {
        _renderEpoch++;
        unawaited(pdf_api.setRenderEpoch(epoch: _renderEpoch));
      }
    }

    _pendingRenderQueue.add(index);
    _drainRenderQueue();
  }

  Future<void> _drainRenderQueue() async {
    if (_isRustWorkerBusy || _pendingRenderQueue.isEmpty || _disposed || _resolvedFile == null) {
      return;
    }
    _isRustWorkerBusy = true;

    try {
      while (_pendingRenderQueue.isNotEmpty && !_disposed && _resolvedFile != null) {
        // Always pick the page closest to the current _pageIndex first!
        final sorted = _pendingRenderQueue.toList()
          ..sort((a, b) => (a - _pageIndex).abs().compareTo((b - _pageIndex).abs()));
        final nextIndex = sorted.first;
        _pendingRenderQueue.remove(nextIndex);

        final maxRadius = isContinuousMode ? 4 : 2;
        // Drop stale queue items that are now far from the viewport
        if ((nextIndex - _pageIndex).abs() > maxRadius || hasPageImage(nextIndex)) {
          continue;
        }

        _currentlyRenderingIndex = nextIndex;
        final int myEpoch = _renderEpoch;

        try {
          final effW = _viewerSize.width > 0 ? _viewerSize.width : 600.0;
          final effH = _viewerSize.height > 0 ? _viewerSize.height : 800.0;
          final dpr = _devicePixelRatio.clamp(1.0, 2.0);
          final targetW = (effW * dpr).round().clamp(400, _maxTextureDimension);
          final targetH = (effH * dpr).round().clamp(600, _maxTextureDimension);

          final result = await measureAsync('render_pdf_page', () => pdf_api.renderPdfPage(
            path: _resolvedFile!.path,
            pageIndex: nextIndex,
            width: targetW,
            height: targetH,
            expectedEpoch: myEpoch,
          ), metadata: {'page': nextIndex, 'width': targetW, 'height': targetH});

          if (_disposed) return;

          // ALWAYS keep the rendered image if it is within maxRadius of _pageIndex,
          // even if _renderEpoch changed while it was finishing!
          if ((nextIndex - _pageIndex).abs() <= maxRadius) {
            _renderedPageSizes[nextIndex] = Size(result.pageWidthPt, result.pageHeightPt);
            if (nextIndex == 0 || _defaultAspectRatio == 0.70) {
              _defaultAspectRatio = result.aspectRatio;
            }

            _cornerColorsCache[nextIndex] = PageCornerColors.fromRgbaBytes(
              result.data,
              result.width,
              result.height,
              fallbackColor: const Color(0xFFFFFFFF),
            );

            final uiImage = await _createUiImageFromRgba(result.data, result.width, result.height);
            if (!_disposed) {
              _gpuImageCache.put(nextIndex, uiImage);

              if (nextIndex == _pageIndex) {
                _currentPageImage = null;
                final widthClamped = result.width.toDouble().clamp(1.0, double.infinity);
                final heightClamped = result.height.toDouble().clamp(1.0, double.infinity);
                _renderedPageSize = Size(widthClamped, heightClamped);
                _currentZoomScale = 1.0;

                final aspectRatio = widthClamped / heightClamped;
                final viewerAspect = _viewerSize.height > 0
                    ? _viewerSize.width / _viewerSize.height
                    : 0.70;
                if (aspectRatio > viewerAspect) {
                  _logicalPageSize = Size(_viewerSize.width, _viewerSize.width / aspectRatio);
                } else {
                  _logicalPageSize = Size(_viewerSize.height * aspectRatio, _viewerSize.height);
                }

                _isLoading = false;
                _error = null;
                unawaited(loadPageText(nextIndex));
              }
            } else {
              SchedulerBinding.instance.addPostFrameCallback((_) {
                uiImage.dispose();
              });
              SchedulerBinding.instance.ensureVisualUpdate();
            }
          }
        } catch (e, stack) {
          if (e.toString().contains('RENDER_CANCELLED')) {
            // If it's still near the active page, put it back in the queue!
            final maxRadius = isContinuousMode ? 4 : 2;
            if ((nextIndex - _pageIndex).abs() <= maxRadius && !hasPageImage(nextIndex)) {
              _pendingRenderQueue.add(nextIndex);
            }
            continue;
          }
          debugPrint('PDF render error for page $nextIndex: $e');
          DiagnosticLogger.instance.logError('PDF::Render', e, stack);
          if (nextIndex == _pageIndex && !_disposed) {
            _error = _formatPdfError(e, context: 'Render');
          }
        } finally {
          _currentlyRenderingIndex = null;
          final completers = _pageRenderCompleters.remove(nextIndex);
          if (completers != null) {
            for (final c in completers) {
              if (!c.isCompleted) c.complete();
            }
          }
          if (!_disposed) {
            if (nextIndex == _pageIndex) {
              _isLoading = false;
            }
            notifyListeners();
          }
        }

        // Automatically enqueue immediate neighbors once the active page finishes
        if (nextIndex == _pageIndex) {
          final aheadCount = isContinuousMode ? 3 : 1;
          final behindCount = isContinuousMode ? 2 : 1;
          for (int i = 1; i <= aheadCount; i++) {
            if (_pageIndex + i < _pageCount && !hasPageImage(_pageIndex + i)) {
              _pendingRenderQueue.add(_pageIndex + i);
            }
          }
          for (int i = 1; i <= behindCount; i++) {
            if (_pageIndex - i >= 0 && !hasPageImage(_pageIndex - i)) {
              _pendingRenderQueue.add(_pageIndex - i);
            }
          }
        }
      }
    } finally {
      _isRustWorkerBusy = false;
    }
  }

  Future<void> renderPage(int index, {bool userInitiated = false}) async {
    if (_disposed) return;
    if (_pageCount <= 0 || index < 0 || index >= _pageCount) {
      _isLoading = false;
      _error = _pageCount <= 0 ? 'This PDF document is empty.' : 'Page index out of bounds.';
      notifyListeners();
      return;
    }

    _pageIndex = index;
    final effectiveTotalPages = _pageCount > 0 ? _pageCount : (book.totalPages > 0 ? book.totalPages : 0);

    if (hasPageImage(index)) {
      _isLoading = false;
      _error = null;
      notifyListeners();

      if (effectiveTotalPages > 0) {
        repository.updateReadingProgress(
          book.id,
          currentPage: index,
          totalPages: effectiveTotalPages,
        );
      }

      unawaited(loadPageText(index));
      _schedulePrefetch(index);
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    if (effectiveTotalPages > 0) {
      repository.updateReadingProgress(
        book.id,
        currentPage: index,
        totalPages: effectiveTotalPages,
      );
    }

    final completer = Completer<void>();
    _pageRenderCompleters.putIfAbsent(index, () => []).add(completer);
    requestPageRender(index, isActivePage: true);

    await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  Future<void> _loadDocumentInternal({bool forceRefresh = false}) async {
    final resolver = BookFileResolver();
    final resolved = await resolver.resolve(book, forceRefresh: forceRefresh);
    if (_disposed) return;
    _resolvedFile = resolved;

    _isLoadingChapters = true;
    _isRestoringScroll = isContinuousMode;

    final count = await pdf_api.getPdfPageCount(path: resolved.path);
    if (_disposed) return;
    if (count <= 0) {
      throw StateError('PDF returned $count pages (PDF_OPEN_ERROR::EMPTY)');
    }
    _pageCount = count;
    _pageIndex = book.currentPage.clamp(0, count - 1);
    _pageKeys = List.generate(count, (i) => GlobalKey(debugLabel: 'pdf-page-$i'));
    notifyListeners();

    // Render Saved Page IMMEDIATELY! (Intrinsic dimensions returned in PdfPageRenderResult)
    await renderPage(_pageIndex);

    // Extract table of contents bookmarks asynchronously after the first frame
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      unawaited(PdfOutlineService.extractBookmarks(resolved.path).then((extracted) {
        if (_disposed) return;
        _chapters = extracted;
      }).catchError((e) {
        debugPrint('Failed to extract bookmarks: $e');
      }).whenComplete(() {
        if (_disposed) return;
        _isLoadingChapters = false;
        notifyListeners();
      }));
    });

    if (isContinuousMode) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          restoreContinuousScroll();
        }
      });
    } else {
      _isRestoringScroll = false;
    }
  }

  bool _shouldRetryPdfOpen(Object error) {
    if (book.sourceType != BookSourceType.linked || book.sourceUri == null) {
      return false;
    }
    final message = error.toString();
    return message.contains('PDF_OPEN_ERROR::FORMAT') ||
        message.contains('PDF_OPEN_ERROR::HEADER') ||
        message.contains('PDF_OPEN_ERROR::EMPTY') ||
        message.contains('PDF_OPEN_ERROR::FILE') ||
        message.contains('FormatError');
  }

  String _formatPdfError(Object error, {String? context}) {
    final message = error.toString();
    if (message.contains('PDF_OPEN_ERROR::HEADER')) {
      return 'This file does not appear to be a valid PDF.';
    }
    if (message.contains('PDF_OPEN_ERROR::EMPTY')) {
      return 'This PDF appears to be empty or still syncing.';
    }
    if (message.contains('PDF_OPEN_ERROR::FORMAT') || message.contains('FormatError')) {
      return 'This PDF appears to be corrupted or invalid.';
    }
    if (message.contains('PDF_OPEN_ERROR::PASSWORD')) {
      return 'This PDF is password-protected and cannot be opened.';
    }
    if (message.contains('PDF_OPEN_ERROR::SECURITY')) {
      return 'This PDF cannot be opened due to its security settings.';
    }
    if (message.contains('PDF_OPEN_ERROR::FILE')) {
      return 'Unable to access the PDF file. Try re-linking the folder.';
    }
    if (context != null) {
      return '$context Error: $message';
    }
    return message;
  }

  void _schedulePrefetch(int currentIndex) {
    if (_viewerSize.isEmpty) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (int i = 1; i <= prefetchAhead; i++) {
        requestPageRender(currentIndex + i, isActivePage: false);
      }
      for (int i = 1; i <= prefetchBehind; i++) {
        requestPageRender(currentIndex - i, isActivePage: false);
      }
    });
  }

  Future<pdf_api.SanitizedPdfText?> loadSanitizedPageText(int index) async {
    if (_disposed || _pageCount <= 0 || index < 0 || index >= _pageCount) return null;

    final cached = _sanitizedTextCache[index];
    if (cached != null) return cached;

    try {
      if (_resolvedFile == null) return null;
      final sanitized = await pdf_api.extractSanitizedPageText(
        path: _resolvedFile!.path,
        pageIndex: index,
      );
      if (_disposed) return null;
      _sanitizedTextCache[index] = sanitized;
      _pageTextCache[index] = sanitized.cleanText;
      return sanitized;
    } catch (e) {
      debugPrint('PDF: Failed to extract sanitized text for page $index: $e');
      return null;
    }
  }

  Future<void> loadPageText(int index) async {
    if (_disposed || _pageCount <= 0 || index < 0 || index >= _pageCount) return;

    await measureAsync('pdf_load_text', () async {
      final cached = _pageTextCache[index];
      if (cached != null) {
        _currentPageText = cached;
        _isTextLoading = false;
        _textError = null;
        notifyListeners();
        return;
      }

      final requestId = ++_textRequestId;
      _isTextLoading = true;
      _textError = null;
      _currentPageText = '';
      notifyListeners();

      try {
        final sanitized = await loadSanitizedPageText(index);
        if (_disposed || requestId != _textRequestId) return;

        if (sanitized != null) {
          _currentPageText = sanitized.cleanText;
          _isTextLoading = false;
          _textError = null;
          notifyListeners();
        }
      } catch (e) {
        if (_disposed || requestId != _textRequestId) return;
        _isTextLoading = false;
        _textError = e.toString();
        _currentPageText = '';
        notifyListeners();
      }
    }, metadata: {'page_index': index, 'book_id': book.id});
  }

  Future<void> precomputeCharacterBounds(int pageIndex) async {
    if (_resolvedFile == null || _pageCharBoundsCache.containsKey(pageIndex) || _disposed) return;

    try {
      final bounds = await measureAsync('extract_all_page_character_bounds', () => pdf_api.extractAllPageCharacterBounds(
        path: _resolvedFile!.path,
        pageIndex: pageIndex,
      ), metadata: {'page': pageIndex});
      if (_disposed) return;
      _pageCharBoundsCache[pageIndex] = bounds;
    } catch (e) {
      if (_disposed) return;
      debugPrint('TTS: Failed to precompute bounds for page $pageIndex: $e');
    }
  }

  Future<void> ensureCharacterBoundsLoaded(int pageIndex) async {
    if (_pageCharBoundsCache.containsKey(pageIndex)) return;
    await precomputeCharacterBounds(pageIndex);
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSaveTimer?.cancel();
    _saveProgressOnDispose();
    for (final list in _pageRenderCompleters.values) {
      for (final c in list) {
        if (!c.isCompleted) c.complete();
      }
    }
    _pageRenderCompleters.clear();
    scrollController.dispose();
    cleanup();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void cleanup() {
    _currentPageImage = null;
    _gpuImageCache.clear();
    _renderedPageSizes.clear();
    _cornerColorsCache.clear();
    _pageTextCache.clear();
    _sanitizedTextCache.clear();
    _pageCharBoundsCache.clear();
    _pageTextInFlight.clear();
    _pendingRenderQueue.clear();
    _currentlyRenderingIndex = null;
    _isRustWorkerBusy = false;
  }
}
