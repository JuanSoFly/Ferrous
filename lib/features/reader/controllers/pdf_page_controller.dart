import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_app/src/rust/api/pdf.dart' as pdf_api;
import 'package:reader_app/src/rust/api/pdf.dart' show PdfTextRect;
import 'package:reader_app/src/rust/api/crop.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/core/utils/performance.dart';

class PdfPageController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  PdfPageController({
    required this.book,
    required this.repository,
  });

  ResolvedBookFile? _resolvedFile;
  Uint8List? _currentPageImage;
  bool _isLoading = true;
  String? _error;
  int _pageIndex = 0;
  int _pageCount = 0;
  bool _autoCrop = false;
  final Map<int, CropMargins> _marginsCache = {};
  Size _renderedPageSize = Size.zero;
  Size _logicalPageSize = Size.zero;
  Size _viewerSize = Size.zero;
  double _devicePixelRatio = 2.0; // Default 2x, can be updated from widget
  double _currentZoomScale = 1.0;
  
  // Maximum texture dimension to prevent OOM crashes
  static const int _maxTextureDimension = 4096;

  // LRU cache for rendered pages (R5)
  final LinkedHashMap<int, Uint8List> _pageRenderCache = LinkedHashMap();
  static const int _maxCachedPages = 5;
  static const int _prefetchAhead = 2;
  static const int _prefetchBehind = 1;
  final Set<int> _prefetchInFlight = {};

  // Text loading state
  final Map<int, String> _pageTextCache = {};
  final Map<int, Future<String>> _pageTextInFlight = {};
  final Map<int, List<PdfTextRect>> _pageCharBoundsCache = {};
  String _currentPageText = '';
  bool _isTextLoading = false;
  String? _textError;
  int _textRequestId = 0;

  // Concurrency control (F2)
  static final Semaphore _renderSemaphore = Semaphore(2);

  // Getters
  ResolvedBookFile? get resolvedFile => _resolvedFile;
  Uint8List? get currentPageImage => _currentPageImage;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pageIndex => _pageIndex;
  int get pageCount => _pageCount;
  bool get autoCrop => _autoCrop;
  CropMargins? get currentMargins => _marginsCache[_pageIndex];
  Size get renderedPageSize => _renderedPageSize;
  Size get logicalPageSize => _logicalPageSize;
  Size get viewerSize => _viewerSize;
  double get currentZoomScale => _currentZoomScale;
  
  String get currentPageText => _currentPageText;
  bool get isTextLoading => _isTextLoading;
  String? get textError => _textError;
  Map<int, String> get pageTextCache => _pageTextCache;
  Map<int, List<PdfTextRect>> get pageCharBoundsCache => _pageCharBoundsCache;

  set viewerSize(Size size) {
    if (_viewerSize == size) return;
    _viewerSize = size;
    // When viewer size changes (e.g. rotation), we might need to invalidate cache
    // but for now let's just keep it to avoid excessive re-renders.
    notifyListeners();
  }

  set devicePixelRatio(double ratio) {
    _devicePixelRatio = ratio.clamp(2.0, 3.0); // Clamp between 2x and 3x for quality/memory balance
  }

  void setAutoCrop(bool value) {
    if (_autoCrop == value) return;
    _autoCrop = value;
    if (_autoCrop && !_marginsCache.containsKey(_pageIndex)) {
      renderPage(_pageIndex);
    } else {
      notifyListeners();
    }
  }

  Future<void> loadDocument() async {
    await measureAsync('pdf_load_document', () async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      Object? failure;
      try {
        await _loadDocumentInternal();
        return;
      } catch (e) {
        failure = e;
      }

      if (_shouldRetryPdfOpen(failure)) {
        try {
          await _loadDocumentInternal(forceRefresh: true);
          return;
        } catch (e) {
          failure = e;
        }
      }

      debugPrint('PDF load error: $failure');
      _error = _formatPdfError(failure);
      _isLoading = false;
      notifyListeners();
    }, metadata: {'book_id': book.id});
  }

  Future<void> renderPage(int index, {bool userInitiated = false}) async {
    await measureAsync('pdf_page_render', () async {
      // Check cache first (R5)
      if (_pageRenderCache.containsKey(index)) {
        _currentPageImage = _pageRenderCache[index];
        _pageIndex = index;
        _isLoading = false;
        _error = null;
        notifyListeners();
        
        
        // Save progress anyway
        repository.updateReadingProgress(
          book.id,
          currentPage: index,
          totalPages: _pageCount,
        );
        
        // Trigger prefetch in background
        _schedulePrefetch(index);
        return;
      }

      _isLoading = true;
      _error = null;
      _pageIndex = index;
      notifyListeners();

      // Save progress
      repository.updateReadingProgress(
        book.id,
        currentPage: index,
        totalPages: _pageCount,
      );

      try {
        if (_resolvedFile == null) return;

        // Start margin detection in parallel if auto-crop is on
        if (_autoCrop && !_marginsCache.containsKey(index)) {
          detectPdfWhitespace(path: _resolvedFile!.path, pageIndex: index).then((margins) {
            _marginsCache[index] = margins;
            if (_pageIndex == index) notifyListeners();
          }).catchError((e) {
            debugPrint("Crop error: $e");
          });
        }

        // Always render at max zoom quality (5x) from the start
        // This ensures crystal clear quality at any zoom level without "popping"
        const double maxZoomQuality = 5.0;
        final baseWidth = _viewerSize.width * _devicePixelRatio;
        final baseHeight = _viewerSize.height * _devicePixelRatio;
        final scaledWidth = (baseWidth * maxZoomQuality).toInt();
        final scaledHeight = (baseHeight * maxZoomQuality).toInt();
        
        // Clamp to safe maximum to prevent OOM
        final width = scaledWidth.clamp(800, _maxTextureDimension);
        final height = scaledHeight.clamp(800, _maxTextureDimension);

        await _renderSemaphore.acquire();
        try {
          final result = await measureAsync('render_pdf_page', () => pdf_api.renderPdfPage(
            path: _resolvedFile!.path,
            pageIndex: index,
            width: width,
            height: height,
          ), metadata: {'page': index, 'width': width, 'height': height, 'zoom': maxZoomQuality});

          // Use ACTUAL dimensions from the rendered result, not requested dimensions
          _currentPageImage = result.data;
          _renderedPageSize = Size(result.width.toDouble(), result.height.toDouble());
          _currentZoomScale = maxZoomQuality;
          
          // Calculate logical size to fit within viewer while preserving aspect ratio
          // This is the size the page will occupy in the UI (high-res texture, proper layout)
          final aspectRatio = result.width / result.height;
          final viewerAspect = _viewerSize.width / _viewerSize.height;
          if (aspectRatio > viewerAspect) {
            // Page is wider than viewer - fit to width
            _logicalPageSize = Size(_viewerSize.width, _viewerSize.width / aspectRatio);
          } else {
            // Page is taller than viewer - fit to height
            _logicalPageSize = Size(_viewerSize.height * aspectRatio, _viewerSize.height);
          }
          
          _isLoading = false;
          _error = null;
          notifyListeners();
          
          // Always cache since we're rendering at constant max quality
          _addToCache(index, result.data);
        } finally {
          _renderSemaphore.release();
        }
        
        _schedulePrefetch(index);
        
      } catch (e) {
        debugPrint('PDF render error: $e');
        _error = _formatPdfError(e, context: 'Render');
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'page_index': index, 'book_id': book.id});
  }

  Future<void> _loadDocumentInternal({bool forceRefresh = false}) async {
    final resolver = BookFileResolver();
    final resolved = await resolver.resolve(book, forceRefresh: forceRefresh);
    _resolvedFile = resolved;
    final count = await pdf_api.getPdfPageCount(path: resolved.path);
    _pageCount = count;
    _pageIndex = count <= 0 ? 0 : book.currentPage.clamp(0, count - 1);

    await renderPage(_pageIndex);
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
    // LinkedHashMap behavior: remove and re-add to put at end (most recent)
    _pageRenderCache.remove(index);
    
    // Evict oldest if full
    if (_pageRenderCache.length >= _maxCachedPages) {
      _pageRenderCache.remove(_pageRenderCache.keys.first);
    }
    
    _pageRenderCache[index] = bytes;
  }

  void _schedulePrefetch(int currentIndex) {
    if (_viewerSize.isEmpty) return;
    
    // Use post frame to avoid interfering with current frame
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (int i = 1; i <= _prefetchAhead; i++) {
        _prefetchPage(currentIndex + i);
      }
      for (int i = 1; i <= _prefetchBehind; i++) {
        _prefetchPage(currentIndex - i);
      }
    });
  }

  Future<void> _prefetchPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    if (_pageRenderCache.containsKey(index)) return;
    if (_prefetchInFlight.contains(index)) return;
    if (_resolvedFile == null) return;

    _prefetchInFlight.add(index);
    try {
      final width = (_viewerSize.width * _devicePixelRatio).toInt().clamp(800, 6000);
      final height = (_viewerSize.height * _devicePixelRatio).toInt().clamp(800, 6000);

      await _renderSemaphore.acquire();
      try {
        final result = await measureAsync('render_pdf_page_prefetch', () => pdf_api.renderPdfPage(
          path: _resolvedFile!.path,
          pageIndex: index,
          width: width,
          height: height,
        ), metadata: {'page': index, 'width': width, 'height': height});
        
        _addToCache(index, result.data);
        debugPrint("PDF: Prefetched page $index");
      } finally {
        _renderSemaphore.release();
      }
    } catch (e) {
      debugPrint("PDF: Prefetch error for page $index: $e");
    } finally {
      if (_prefetchInFlight.contains(index)) {
        _prefetchInFlight.remove(index);
      }
    }
  }

  Future<void> loadPageText(int index) async {
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
        if (_resolvedFile == null) return;

        final future = _pageTextInFlight[index] ??= measureAsync('extract_pdf_page_text', () => pdf_api.extractPdfPageText(
          path: _resolvedFile!.path,
          pageIndex: index,
        ), metadata: {'page': index});
        final text = await future;
        _pageTextInFlight.remove(index);

        if (requestId != _textRequestId) return;

        _pageTextCache[index] = text;
        _currentPageText = text;
        _isTextLoading = false;
        _textError = null;
        notifyListeners();

        // Pre-compute character bounds for TTS (non-blocking)
        if (!_pageCharBoundsCache.containsKey(index)) {
          unawaited(precomputeCharacterBounds(index));
        }
      } catch (e) {
        _pageTextInFlight.remove(index);
        if (requestId != _textRequestId) return;
        _isTextLoading = false;
        _textError = e.toString();
        _currentPageText = '';
        notifyListeners();
      }
    }, metadata: {'page_index': index, 'book_id': book.id});
  }

  Future<void> precomputeCharacterBounds(int pageIndex) async {
    if (_resolvedFile == null) return;
    if (_pageCharBoundsCache.containsKey(pageIndex)) return;
    
    try {
      final bounds = await measureAsync('extract_all_page_character_bounds', () => pdf_api.extractAllPageCharacterBounds(
        path: _resolvedFile!.path,
        pageIndex: pageIndex,
      ), metadata: {'page': pageIndex});
      _pageCharBoundsCache[pageIndex] = bounds;
    } catch (e) {
      debugPrint('TTS: Failed to precompute bounds for page $pageIndex: $e');
    }
  }

  /// Ensures character bounds are loaded for the current page.
  /// Call this before starting TTS to guarantee highlight data is available.
  Future<void> ensureCharacterBoundsLoaded(int pageIndex) async {
    if (_pageCharBoundsCache.containsKey(pageIndex)) return;
    await precomputeCharacterBounds(pageIndex);
  }

  void cleanup() {
    _pageRenderCache.clear();
    _marginsCache.clear();
    _pageTextCache.clear();
    _pageCharBoundsCache.clear();
    _pageTextInFlight.clear();
    _prefetchInFlight.clear();
  }
}
