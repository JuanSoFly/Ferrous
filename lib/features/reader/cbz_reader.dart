import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/src/rust/api/cbz.dart';

class CbzReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const CbzReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<CbzReaderScreen> createState() => _CbzReaderScreenState();
}

class _CbzReaderScreenState extends State<CbzReaderScreen>
    with WidgetsBindingObserver {
  /// Total number of pages (from Rust)
  int _pageCount = 0;
  /// Resolved file path for Rust API calls
  String? _archivePath;
  int _currentPage = 0;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final TransformationController _imageTransformController =
      TransformationController();
  Timer? _progressSaveTimer;
  bool _isRestoringScroll = false;
  ResolvedBookFile? _resolvedFile;
  bool _showChrome = false;
  bool _lockMode = false;
  Offset? _lastDoubleTapDown;
  late ReadingMode _readingMode;
  late double _lastScrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPage = widget.book.currentPage;
    _readingMode = widget.book.readingMode;
    _lastScrollPosition = widget.book.scrollPosition;
    
    // CRITICAL: Limit image cache size to prevent OOM crashes in continuous scroll mode
    // Default cache is 100 images / 100MB which is way too high for large comic images
    PaintingBinding.instance.imageCache.maximumSize = 10; // Only keep 10 decoded images
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB max
    
    _loadCbz();
    _scrollController.addListener(_handleScrollUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSystemUiMode();
    });
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    if (_isVerticalContinuous || _isHorizontalContinuous) {
      _saveContinuousProgress();
    } else if (_pageCount > 0) {
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
      );
    }
    
    // Clear preloading cache to free memory
    _CbzPageImageState.clearCache();
    
    _cleanupTempFile();
    _scrollController.dispose();
    _imageTransformController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_isVerticalContinuous || _isHorizontalContinuous) {
        _saveContinuousProgress();
      } else {
        widget.repository.updateReadingProgress(
          widget.book.id,
          currentPage: _currentPage,
          totalPages: _pageCount,
        );
      }
    }
  }

  /// Load CBZ using Rust streaming API (no temp file extraction!)
  Future<void> _loadCbz() async {
    try {
      final resolver = BookFileResolver();
      final resolved = await resolver.resolve(widget.book);
      _resolvedFile = resolved;
      _archivePath = resolved.path;
      
      // Use Rust to get page count (no temp file extraction needed!)
      final count = await getCbzPageCount(path: resolved.path);
      
      setState(() {
        _pageCount = count;
        _isLoading = false;
      });
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isVerticalContinuous || _isHorizontalContinuous) {
          _restoreContinuousScroll();
        }
      });
      
      // Validation of page index
      if (_currentPage >= count) {
        setState(() {
          _currentPage = 0;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _cleanupTempFile() {
    final resolved = _resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      File(resolved.path).deleteSync();
    } catch (_) {
      // Ignore cleanup failures
    }
  }

  void _updateSystemUiMode() {
    if (_showChrome && !_lockMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _toggleChrome() {
    if (_lockMode) return;
    setState(() => _showChrome = !_showChrome);
    _updateSystemUiMode();
  }

  void _toggleLockMode() {
    setState(() {
      _lockMode = !_lockMode;
      if (_lockMode) {
        _showChrome = false;
      } else {
        _showChrome = true;
      }
    });
    _updateSystemUiMode();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _lockMode
                ? 'Lock mode on. Double-tap center to unlock.'
                : 'Lock mode off.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isCenterTap(Offset globalPosition) {
    final size = MediaQuery.of(context).size;
    if (size.isEmpty) return false;
    final centerWidth = size.width * 0.45;
    final centerHeight = size.height * 0.35;
    final left = (size.width - centerWidth) / 2;
    final top = (size.height - centerHeight) / 2;
    final rect = Rect.fromLTWH(left, top, centerWidth, centerHeight);
    return rect.contains(globalPosition);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isCenterTap(details.globalPosition)) {
      _toggleChrome();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!_lockMode) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    if (_isCenterTap(position)) {
      _toggleLockMode();
    }
  }

  bool get _isPagedMode =>
      _readingMode == ReadingMode.leftToRight ||
      _readingMode == ReadingMode.vertical;

  bool get _useHorizontalSwipe => _readingMode == ReadingMode.leftToRight;

  bool get _useVerticalSwipe => _readingMode == ReadingMode.vertical;

  bool get _isVerticalContinuous =>
      _readingMode == ReadingMode.verticalContinuous ||
      _readingMode == ReadingMode.webtoon;

  bool get _isHorizontalContinuous =>
      _readingMode == ReadingMode.horizontalContinuous;

  bool _canSwipePages() {
    final scale = _imageTransformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  void _handleScrollUpdate() {
    if (!_isVerticalContinuous && !_isHorizontalContinuous) return;
    if (_isRestoringScroll) return;
    _scheduleContinuousProgressSave();
  }

  void _scheduleContinuousProgressSave() {
    if (_progressSaveTimer?.isActive ?? false) return;
    _progressSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveContinuousProgress();
    });
  }

  void _flushContinuousProgressSave() {
    _progressSaveTimer?.cancel();
    _saveContinuousProgress();
  }

  void _saveContinuousProgress() {
    if (!_scrollController.hasClients) return;
    if (_pageCount == 0) return;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    final approxIndex = viewport <= 0
        ? 0
        : (offset / viewport).round().clamp(0, _pageCount - 1);
    _lastScrollPosition = offset;
    // Update page index without setState to avoid scroll position jumps during fast scroll
    _currentPage = approxIndex;
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: approxIndex,
      totalPages: _pageCount,
      scrollPosition: offset,
    );
  }

  void _restoreContinuousScroll() {
    if (!_scrollController.hasClients) return;
    if (_lastScrollPosition <= 0 && _currentPage <= 0) return;

    _isRestoringScroll = true;
    var attempts = 0;

    void tryRestore() {
      if (!mounted || !_scrollController.hasClients) {
        _isRestoringScroll = false;
        return;
      }

      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        attempts++;
        if (attempts < 5) {
          WidgetsBinding.instance.addPostFrameCallback((_) => tryRestore());
        } else {
          _isRestoringScroll = false;
        }
        return;
      }

      final baseOffset = _lastScrollPosition > 0
          ? _lastScrollPosition
          : position.viewportDimension * _currentPage;
      final clamped = baseOffset.clamp(0.0, position.maxScrollExtent);
      if ((position.pixels - clamped).abs() > 1.0) {
        _scrollController.jumpTo(clamped);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRestoringScroll = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryRestore());
  }

  void _swipeToPage(int delta) {
    final next = _currentPage + delta;
    _jumpToPage(next);
  }

  void _jumpToPage(int page) {
    if (page < 0 || page >= _pageCount) return;
    _imageTransformController.value = Matrix4.identity();
    setState(() {
      _currentPage = page;
    });
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: page,
      totalPages: _pageCount,
    );
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_useHorizontalSwipe || !_isPagedMode) return;
    if (!_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    // Positive velocity = swipe right = go to previous page
    // Negative velocity = swipe left = go to next page
    if (velocity > 0) {
      _swipeToPage(-1);
    } else {
      _swipeToPage(1);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_useVerticalSwipe || !_isPagedMode) return;
    if (!_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    // Positive velocity = swipe down = go to previous page
    // Negative velocity = swipe up = go to next page
    if (velocity > 0) {
      _swipeToPage(-1);
    } else {
      _swipeToPage(1);
    }
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.image,
    );
    if (selected == null || selected == _readingMode) return;
    
    // Save current progress BEFORE switching modes
    final wasContinuousMode = _isVerticalContinuous || _isHorizontalContinuous;
    
    if (wasContinuousMode) {
      _saveContinuousProgress();
    } else {
      // Save paged mode progress
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
      );
    }
    
    setState(() => _readingMode = selected);
    widget.repository.updateReadingProgress(
      widget.book.id,
      readingMode: selected,
    );
    
    // Calculate scroll position for new mode
    final willBeContinuous = selected == ReadingMode.verticalContinuous ||
        selected == ReadingMode.webtoon ||
        selected == ReadingMode.horizontalContinuous;
    
    if (willBeContinuous) {
      // Switching TO continuous: calculate scroll position from page index
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final viewport = _scrollController.position.viewportDimension;
        // Jump to approximately the same page position
        final targetScroll = _currentPage * viewport;
        _scrollController.jumpTo(targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent));
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final showChrome = _showChrome && !_lockMode;
    final showBottomControls = showChrome && _isPagedMode;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _handleTapUp,
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              onHorizontalDragEnd:
                  _isPagedMode && _useHorizontalSwipe ? _handleHorizontalDragEnd : null,
              onVerticalDragEnd:
                  _isPagedMode && _useVerticalSwipe ? _handleVerticalDragEnd : null,
              child: _buildBody(),
            ),
          ),
          if (showChrome) _buildTopBar(),
          if (showBottomControls && _buildControls() != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildControls()!,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Error: $_error", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pageCount == 0) {
      return const Center(child: Text("No images found in archive"));
    }

    if (_isPagedMode) {
      return _buildPagedView();
    }

    if (_isVerticalContinuous) {
      return _buildVerticalContinuousView();
    }

    if (_isHorizontalContinuous) {
      return _buildHorizontalContinuousView();
    }

    return _buildPagedView();
  }

  Widget _buildPagedView() {
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // Use full screen width * pixel ratio for crisp images on high-DPI displays
    final maxWidth = (size.width * devicePixelRatio).round();
    final page = _CbzPageImage(
      archivePath: _archivePath!,
      pageIndex: _currentPage,
      fit: BoxFit.contain,
      maxWidth: maxWidth,
    );

    final animatedPage = KeyedSubtree(
      key: ValueKey(_currentPage),
      child: Center(child: page),
    );

    return InteractiveViewer(
      transformationController: _imageTransformController,
      maxScale: 5.0,
      child: animatedPage,
    );
  }

  Widget _buildVerticalContinuousView() {
    // Webtoon mode
    final spacing = _readingMode == ReadingMode.webtoon ? 1.0 : 12.0;
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // Use device pixel ratio for crisp images on high-DPI displays
    final maxWidth = (size.width * devicePixelRatio).round();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _scheduleContinuousProgressSave();
        }
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          _flushContinuousProgressSave();
        }
        return false;
      },
      child: ListView.separated(
        controller: _scrollController,
        key: PageStorageKey('cbz-${widget.book.id}-${_readingMode.name}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: _pageCount,
        // Limit how far ahead we pre-load (1 screen worth)
        cacheExtent: size.height,
        // Don't keep all pages alive in memory - critical for large CBZ files
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: _CbzPageImage(
              archivePath: _archivePath!,
              pageIndex: index,
              fit: BoxFit.contain,
              maxWidth: maxWidth,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalContinuousView() {
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // Use device pixel ratio for crisp images on high-DPI displays
    final maxWidth = (size.width * devicePixelRatio).round();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _scheduleContinuousProgressSave();
        }
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          _flushContinuousProgressSave();
        }
        return false;
      },
      child: ListView.separated(
        controller: _scrollController,
        key: PageStorageKey('cbz-${widget.book.id}-${_readingMode.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _pageCount,
        // Limit how far ahead we pre-load
        cacheExtent: size.width,
        // Don't keep all pages alive in memory
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: _CbzPageImage(
              archivePath: _archivePath!,
              pageIndex: index,
              fit: BoxFit.contain,
              maxWidth: maxWidth,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_pageCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text("${_currentPage + 1} / ${_pageCount}"),
                  ),
                IconButton(
                  icon: Icon(_lockMode ? Icons.lock : Icons.lock_open),
                  tooltip: _lockMode ? 'Unlock' : 'Lock',
                  onPressed: _toggleLockMode,
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: _showReadingModePicker,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildControls() {
    if (_pageCount <= 1) return null;

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 ? () => _jumpToPage(0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    _currentPage > 0 ? () => _jumpToPage(_currentPage - 1) : null,
              ),
              Text("${_currentPage + 1} / ${_pageCount}"),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _pageCount - 1
                    ? () => _jumpToPage(_currentPage + 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < _pageCount - 1
                    ? () => _jumpToPage(_pageCount - 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CBZ page image widget that loads from Rust API on-demand (no temp files!)
class _CbzPageImage extends StatefulWidget {
  final String archivePath;
  final int pageIndex;
  final BoxFit fit;
  final int maxWidth;

  const _CbzPageImage({
    required this.archivePath,
    required this.pageIndex,
    required this.fit,
    required this.maxWidth,
  });

  @override
  State<_CbzPageImage> createState() => _CbzPageImageState();
}

class _CbzPageImageState extends State<_CbzPageImage> {
  ui.Image? _image;
  bool _isLoading = true;
  String? _error;
  
  // Static cache for preloaded images (shared across all instances)
  static final Map<String, ui.Image> _imageCache = {};
  static final List<String> _cacheOrder = []; // LRU tracking
  static const int _maxCacheSize = 8; // Keep up to 8 pages in memory
  static final Set<String> _loadingPages = {}; // Track pages being loaded

  String get _cacheKey => '${widget.archivePath}:${widget.pageIndex}:${widget.maxWidth}';

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(_CbzPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.archivePath != widget.archivePath) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    
    final key = _cacheKey;
    
    // Check cache first (instant load!)
    if (_imageCache.containsKey(key)) {
      final cached = _imageCache[key]!;
      _touchCache(key);
      setState(() {
        _image = cached.clone();
        _isLoading = false;
        _error = null;
      });
      // Preload next pages in background
      _preloadAhead();
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final image = await _loadAndCachePage(widget.archivePath, widget.pageIndex, widget.maxWidth);
      if (!mounted) return;

      setState(() {
        _image = image?.clone();
        _isLoading = false;
      });
      
      // Preload next pages in background
      _preloadAhead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }
  
  /// Load a page and add to cache
  static Future<ui.Image?> _loadAndCachePage(String path, int index, int maxWidth) async {
    final key = '$path:$index:$maxWidth';
    
    // Already in cache
    if (_imageCache.containsKey(key)) {
      _touchCache(key);
      return _imageCache[key];
    }
    
    // Already loading
    if (_loadingPages.contains(key)) return null;
    _loadingPages.add(key);
    
    try {
      // Call Rust API to extract and resize this single page
      final data = await getCbzPage(
        path: path,
        index: index,
        maxWidth: maxWidth,
      );

      // Decode RGBA bytes to Flutter Image
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        data.rgbaBytes,
        data.width,
        data.height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );

      final image = await completer.future;
      
      // Add to cache
      _addToCache(key, image);
      
      return image;
    } finally {
      _loadingPages.remove(key);
    }
  }
  
  static void _addToCache(String key, ui.Image image) {
    // Evict oldest if cache is full
    while (_cacheOrder.length >= _maxCacheSize) {
      final oldest = _cacheOrder.removeAt(0);
      _imageCache[oldest]?.dispose();
      _imageCache.remove(oldest);
    }
    
    _imageCache[key] = image;
    _cacheOrder.add(key);
  }
  
  static void _touchCache(String key) {
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
  }
  
  /// Clear all cached images (call when leaving reader)
  static void clearCache() {
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
    _cacheOrder.clear();
    _loadingPages.clear();
  }
  
  /// Preload next 3 pages in background
  void _preloadAhead() {
    if (!mounted) return;
    final path = widget.archivePath;
    final maxWidth = widget.maxWidth;
    final current = widget.pageIndex;
    
    // Preload pages ahead (in background, don't await)
    for (var i = 1; i <= 3; i++) {
      final nextPage = current + i;
      final key = '$path:$nextPage:$maxWidth';
      if (!_imageCache.containsKey(key) && !_loadingPages.contains(key)) {
        _loadAndCachePage(path, nextPage, maxWidth);
      }
    }
    // Also preload 1 page behind
    if (current > 0) {
      final prevPage = current - 1;
      final key = '$path:$prevPage:$maxWidth';
      if (!_imageCache.containsKey(key) && !_loadingPages.contains(key)) {
        _loadAndCachePage(path, prevPage, maxWidth);
      }
    }
  }

  @override
  void dispose() {
    // Don't dispose cached images here - let them stay in cache
    // Only dispose if image was cloned
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, size: 48),
              const SizedBox(height: 8),
              Text('Page ${widget.pageIndex + 1}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    if (_image == null) {
      return const SizedBox(height: 200);
    }

    return RawImage(
      image: _image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
