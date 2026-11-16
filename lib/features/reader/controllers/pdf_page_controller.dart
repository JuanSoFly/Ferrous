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
  final int maxResident;
  final LinkedHashMap<int, ui.Image> _cache = LinkedHashMap();

  PdfGpuImageCache({this.maxResident = 6});

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
  }) : _pageIndex = book.currentPage,
       _readingMode = book.readingMode,
       _lastScrollPosition = book.scrollPosition {
    scrollController.addListener(_handleScrollUpdate);
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

  // LRU cache for rendered compressed bytes
  final LinkedHashMap<int, Uint8List> _pageRenderCache = LinkedHashMap();
  int get maxCachedPages => isContinuousMode ? 12 : 8;
  int get prefetchAhead => isContinuousMode ? 2 : 2;
  int get prefetchBehind => isContinuousMode ? 1 : 1;
  final Set<int> _prefetchInFlight = {};

  // Direct ImageProvider tracking for reliable GPU texture eviction
  final Map<int, ImageProvider> _activeProviders = {};

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
  final PdfGpuImageCache _gpuImageCache = PdfGpuImageCache(maxResident: 6);
  ui.Image? getPageUiImage(int index) => _gpuImageCache.get(index);
  int _renderEpoch = 0;
  int get renderEpoch => _renderEpoch;

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

    repository.updateReadingProgress(
      book.id,
      currentPage: _pageIndex,
      totalPages: _pageCount,
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

  Color _u32ToColor(int rgb) {
    return Color(0xFF000000 | (rgb & 0x00FFFFFF));
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

    // Save exact progress before switching
    if (isContinuousMode) {
      saveContinuousProgress();
    } else {
      repository.updateReadingProgress(
        book.id,
        currentPage: _pageIndex,
        totalPages: _pageCount,
        readingMode: mode,
      );
    }

    final wasContinuous = isContinuousMode;
    _readingMode = mode;
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
    } else if (_pageCount > 0) {
      repository.updateReadingProgress(
        book.id,
        currentPage: _pageIndex,
        totalPages: _pageCount,
      );
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

  void updateViewportSize(Size size) {
    if (_viewerSize == size) return;
    viewerSize = size;
  }

  set viewerSize(Size size) {
    if (_viewerSize == size) return;
    final wasEmpty = _viewerSize.isEmpty;
    final sizeChanged = !wasEmpty && !size.isEmpty;
    _viewerSize = size;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        if ((wasEmpty || sizeChanged) && _resolvedFile != null && !_isLoading) {
          renderPage(_pageIndex);
        } else {
          notifyListeners();
        }
      }
    });
  }

  Uint8List? getPageImage(int index) {
    if (index == _pageIndex) return _currentPageImage;
    return _pageRenderCache[index];
  }

  ImageProvider getPageImageProvider(int index) {
    final bytes = getPageImage(index);
    if (bytes == null) {
      return MemoryImage(Uint8List(0));
    }
    return getOrCreateImageProvider(index, bytes);
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

  ImageProvider getOrCreateImageProvider(int index, Uint8List bytes) {
    final existing = _activeProviders[index];
    if (existing != null) return existing;

    final provider = MemoryImage(bytes);
    _activeProviders[index] = provider;
    _pruneImageProviders();
    return provider;
  }

  void _pruneImageProviders() {
    // Evict GPU textures outside active reading window [pageIndex - 2, pageIndex + 2]
    _activeProviders.removeWhere((page, provider) {
      if ((page - _pageIndex).abs() > 2) {
        provider.evict();
        return true;
      }
      return false;
    });
  }

  set devicePixelRatio(double ratio) {
    _devicePixelRatio = ratio.clamp(2.0, 3.0);
  }

  void preloadPage(int index) {
    _prefetchPage(index);
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

  Future<void> renderPage(int index, {bool userInitiated = false}) async {
    if (_disposed) return;
    if (_pageCount <= 0 || index < 0 || index >= _pageCount) {
      _isLoading = false;
      _error = _pageCount <= 0 ? 'This PDF document is empty.' : 'Page index out of bounds.';
      notifyListeners();
      return;
    }

    await measureAsync('pdf_page_render', () async {
      _renderEpoch++;
      pdf_api.setRenderEpoch(epoch: _renderEpoch);
      final currentEpoch = _renderEpoch;

      if (_gpuImageCache.contains(index)) {
        _pageIndex = index;
        _isLoading = false;
        _error = null;
        _pruneImageProviders();
        notifyListeners();

        repository.updateReadingProgress(
          book.id,
          currentPage: index,
          totalPages: _pageCount,
        );

        unawaited(Future.wait([
          loadPageText(index),
          ensureCharacterBoundsLoaded(index),
        ]));

        _schedulePrefetch(index);
        return;
      }

      _isLoading = true;
      _error = null;
      _pageIndex = index;
      notifyListeners();

      repository.updateReadingProgress(
        book.id,
        currentPage: index,
        totalPages: _pageCount,
      );

      try {
        if (_resolvedFile == null) return;

        const double maxZoomQuality = 1.25;
        final targetWidth = (_viewerSize.width * _devicePixelRatio * maxZoomQuality).round().clamp(800, _maxTextureDimension);
        final targetHeight = (_viewerSize.height * _devicePixelRatio * maxZoomQuality).round().clamp(1000, _maxTextureDimension);

        final result = await measureAsync('render_pdf_page', () => pdf_api.renderPdfPage(
          path: _resolvedFile!.path,
          pageIndex: index,
          width: targetWidth,
          height: targetHeight,
        ), metadata: {'page': index, 'width': targetWidth, 'height': targetHeight});

        if (_disposed || currentEpoch != _renderEpoch) return;

        _currentPageImage = result.data;
        final widthClamped = result.width.toDouble().clamp(1.0, double.infinity);
        final heightClamped = result.height.toDouble().clamp(1.0, double.infinity);
        _renderedPageSize = Size(widthClamped, heightClamped);
        _renderedPageSizes[index] = Size(widthClamped, heightClamped);
        _defaultAspectRatio = widthClamped / heightClamped;
        _currentZoomScale = maxZoomQuality;

        final aspectRatio = widthClamped / heightClamped;
        final viewerAspect = _viewerSize.width / _viewerSize.height;
        if (aspectRatio > viewerAspect) {
          _logicalPageSize = Size(_viewerSize.width, _viewerSize.width / aspectRatio);
        } else {
          _logicalPageSize = Size(_viewerSize.height * aspectRatio, _viewerSize.height);
        }

        final uiImage = await _createUiImageFromRgba(result.data, result.width, result.height);
        if (_disposed || currentEpoch != _renderEpoch) {
          uiImage.dispose();
          return;
        }

        _gpuImageCache.put(index, uiImage);
        _addToCache(index, result.data);
        _pruneImageProviders();

        final tl = _u32ToColor(result.topLeftRgb);
        final tr = _u32ToColor(result.topRightRgb);
        final bl = _u32ToColor(result.bottomLeftRgb);
        final br = _u32ToColor(result.bottomRightRgb);
        _cornerColorsCache[index] = PageCornerColors(
          topLeft: tl,
          topRight: tr,
          bottomLeft: bl,
          bottomRight: br,
          topColor: tl,
          bottomColor: bl,
          leftColor: tl,
          rightColor: tr,
          topProfile: [tl, tr],
          bottomProfile: [bl, br],
          isMangaWhitePaper: false,
        );

        _isLoading = false;
        _error = null;

        unawaited(Future.wait([
          loadPageText(index),
          ensureCharacterBoundsLoaded(index),
        ]));

        notifyListeners();

        if (_disposed) return;
        _schedulePrefetch(index);
      } catch (e, stack) {
        if (_disposed) return;
        debugPrint('PDF render error: $e');
        DiagnosticLogger.instance.logError('PDF::Render', e, stack);
        _error = _formatPdfError(e, context: 'Render');
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'page_index': index, 'book_id': book.id});
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
    _pageCount = count;
    _pageIndex = count <= 0 ? 0 : book.currentPage.clamp(0, count - 1);
    _pageKeys = List.generate(count, (i) => GlobalKey(debugLabel: 'pdf-page-$i'));

    // Fast Bulk Dimension Loading:
    // Fetch all page dimensions in one call (<3ms for 1,000 pages)
    try {
      final dims = await pdf_api.getPdfPageDimensions(path: resolved.path);
      if (!_disposed) {
        for (int i = 0; i < dims.length; i++) {
          final d = dims[i];
          _renderedPageSizes[i] = Size(d.width, d.height);
        }
        if (dims.isNotEmpty) {
          _defaultAspectRatio = dims.first.aspectRatio;
        }
      }
    } catch (e) {
      debugPrint('Failed to load bulk page dimensions: $e');
    }

    // Extract table of contents bookmarks asynchronously
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

    await renderPage(_pageIndex);

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

  void _addToCache(int index, Uint8List bytes) {
    _pageRenderCache.remove(index);
    while (_pageRenderCache.length >= maxCachedPages) {
      final oldest = _pageRenderCache.keys.first;
      _pageRenderCache.remove(oldest);
    }
    _pageRenderCache[index] = bytes;
  }

  void _schedulePrefetch(int currentIndex) {
    if (_viewerSize.isEmpty) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (int i = 1; i <= prefetchAhead; i++) {
        _prefetchPage(currentIndex + i);
      }
      for (int i = 1; i <= prefetchBehind; i++) {
        _prefetchPage(currentIndex - i);
      }
    });
  }

  Future<void> _prefetchPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    if (_gpuImageCache.contains(index)) return;
    if (_prefetchInFlight.contains(index)) return;
    if (_resolvedFile == null || _disposed) return;

    _prefetchInFlight.add(index);
    final targetEpoch = _renderEpoch;
    try {
      final targetWidth = (_viewerSize.width * _devicePixelRatio * 1.25).round().clamp(800, _maxTextureDimension);
      final targetHeight = (_viewerSize.height * _devicePixelRatio * 1.25).round().clamp(1000, _maxTextureDimension);

      if (_disposed || _renderEpoch != targetEpoch) return;

      final result = await measureAsync('render_pdf_page_prefetch', () => pdf_api.renderPdfPage(
        path: _resolvedFile!.path,
        pageIndex: index,
        width: targetWidth,
        height: targetHeight,
      ), metadata: {'page': index, 'width': targetWidth, 'height': targetHeight});

      if (_disposed || _renderEpoch != targetEpoch) return;

      final widthClamped = result.width.toDouble().clamp(1.0, double.infinity);
      final heightClamped = result.height.toDouble().clamp(1.0, double.infinity);
      _renderedPageSizes[index] = Size(widthClamped, heightClamped);

      final uiImage = await _createUiImageFromRgba(result.data, result.width, result.height);
      if (_disposed || _renderEpoch != targetEpoch) {
        uiImage.dispose();
        return;
      }

      _gpuImageCache.put(index, uiImage);
      _addToCache(index, result.data);

      final tl = _u32ToColor(result.topLeftRgb);
      final tr = _u32ToColor(result.topRightRgb);
      final bl = _u32ToColor(result.bottomLeftRgb);
      final br = _u32ToColor(result.bottomRightRgb);
      _cornerColorsCache[index] = PageCornerColors(
        topLeft: tl,
        topRight: tr,
        bottomLeft: bl,
        bottomRight: br,
        topColor: tl,
        bottomColor: bl,
        leftColor: tl,
        rightColor: tr,
        topProfile: [tl, tr],
        bottomProfile: [bl, br],
        isMangaWhitePaper: false,
      );

      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      debugPrint('PDF: Prefetch error for page $index: $e');
    } finally {
      _prefetchInFlight.remove(index);
    }
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

        if (!_pageCharBoundsCache.containsKey(index)) {
          unawaited(precomputeCharacterBounds(index));
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
    for (final provider in _activeProviders.values) {
      provider.evict();
    }
    _activeProviders.clear();
    _gpuImageCache.clear();
    _pageRenderCache.clear();
    _renderedPageSizes.clear();
    _cornerColorsCache.clear();
    _pageTextCache.clear();
    _sanitizedTextCache.clear();
    _pageCharBoundsCache.clear();
    _pageTextInFlight.clear();
    _prefetchInFlight.clear();
  }
}
