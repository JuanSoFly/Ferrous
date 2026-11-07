import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;
import 'package:reader_app/core/utils/performance.dart';
import 'cbz_cache_controller.dart';

class CbzPageController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;
  
  int _pageCount = 0;
  int get pageCount => _pageCount;
  
  List<String> _pageNames = [];
  List<String> get pageNames => _pageNames;
  
  int _currentPage = 0;
  int get pageIndex => _currentPage;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  String? _error;
  String? get error => _error;
  
  String? _archivePath;
  String? get archivePath => _archivePath;
  
  ResolvedBookFile? _resolvedFile;
  ResolvedBookFile? get resolvedFile => _resolvedFile;
  
  late final ScrollController scrollController;
  Timer? _progressSaveTimer;
  bool isRestoringScroll = false;
  
  ReadingMode _readingMode;
  ReadingMode get readingMode => _readingMode;
  
  double _lastScrollPosition;
  double get scrollPosition => scrollController.hasClients ? scrollController.offset : _lastScrollPosition;
  
  double _inPageScrollOffset = 0.0;
  double get inPageScrollOffset => _inPageScrollOffset;

  double? _viewportWidth;
  double? _viewportHeight;

  void updateViewportDimensions(double width, double height) {
    _viewportWidth = width;
    _viewportHeight = height;
  }

  CbzCacheController? _cacheController;
  CbzCacheController? get cacheController => _cacheController;

  List<GlobalKey> _pageKeys = [];
  List<GlobalKey> get pageKeys => _pageKeys;

  final Map<int, double> _pageExtents = {};
  DateTime _lastScrollCheckTime = DateTime.now();

  CbzPageController({
    required this.book,
    required this.repository,
  }) : _currentPage = book.currentPage,
       _readingMode = book.readingMode,
       _lastScrollPosition = book.scrollPosition {
    _inPageScrollOffset = book.lastReadingSentenceStart >= 0
        ? book.lastReadingSentenceStart.toDouble()
        : 0.0;
    scrollController = ScrollController(initialScrollOffset: 0.0);
    scrollController.addListener(_handleScrollUpdate);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _saveProgressOnDispose();
    _cacheController?.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadDocument() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    await measureAsync('cbz_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;
        _archivePath = resolved.path;
        
        final names = await cbz_api.getCbzPageNames(path: resolved.path);
        
        _pageNames = names;
        _pageCount = names.length;
        _pageKeys = List.generate(names.length, (_) => GlobalKey());
        
        _cacheController = CbzCacheController(
          archivePath: resolved.path,
          pageNames: names,
        );

        if (_currentPage >= names.length) {
          _currentPage = 0;
          _inPageScrollOffset = 0.0;
        }

        // Pre-warm the target reading page before revealing content
        final targetIndex = (_currentPage >= 0 && _currentPage < names.length) ? _currentPage : 0;
        await _cacheController!.loadPage(targetIndex, 1080);

        _isLoading = false;
        notifyListeners();

        if (isContinuousMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            restoreContinuousScroll();
          });
        }
      } catch (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  void _handleScrollUpdate() {
    if (!isContinuousMode) return;
    if (isRestoringScroll) return;
    _scheduleContinuousProgressSave();
  }

  bool get isContinuousMode =>
      _readingMode == ReadingMode.verticalContinuous ||
      _readingMode == ReadingMode.webtoon ||
      _readingMode == ReadingMode.horizontalContinuous;

  void _scheduleContinuousProgressSave() {
    if (_progressSaveTimer?.isActive ?? false) return;
    _progressSaveTimer = Timer(const Duration(milliseconds: 350), () {
      saveContinuousProgress();
    });
  }

  void flushContinuousProgressSave() {
    _progressSaveTimer?.cancel();
    saveContinuousProgress();
  }

  void recordPageExtent(int index, double extent) {
    if (extent > 0) {
      _pageExtents[index] = extent;
    }
  }

  void updateCurrentPageFromScroll(BuildContext context, {bool force = false}) {
    if (isRestoringScroll) return;
    if (_pageKeys.isEmpty || !scrollController.hasClients) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastScrollCheckTime).inMilliseconds < 100) {
      return;
    }
    _lastScrollCheckTime = now;

    final viewportBox = context.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;

    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
    final viewportDimension = isHorizontal ? viewportBox.size.width : viewportBox.size.height;
    final focusPoint = viewportDimension * 0.35;

    int? bestIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < _pageKeys.length; i++) {
      final key = _pageKeys[i];
      final ctx = key.currentContext;
      if (ctx == null) continue;

      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;

      final itemExtent = isHorizontal ? renderBox.size.width : renderBox.size.height;
      if (itemExtent > 0) {
        _pageExtents[i] = itemExtent;
      }

      final itemStart = isHorizontal
          ? renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx
          : renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      final itemEnd = itemStart + itemExtent;

      // If the focus point is inside this page, this is the current page
      if (itemStart <= focusPoint && itemEnd > focusPoint) {
        bestIndex = i;
        break;
      }

      final distance = (itemStart - focusPoint).abs();
      if (distance < minDistance) {
        minDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex != null) {
      final key = _pageKeys[bestIndex];
      final ctx = key.currentContext;
      if (ctx != null) {
        final renderBox = ctx.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final itemStart = isHorizontal
              ? renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx
              : renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
          _inPageScrollOffset = itemStart < 0 ? -itemStart : 0.0;
        }
      }

      if (bestIndex != _currentPage) {
        _currentPage = bestIndex;
        book.currentPage = bestIndex;
        notifyListeners();
      }
    }
  }

  void saveContinuousProgress() {
    if (!scrollController.hasClients) return;
    if (_pageCount == 0) return;
    if (isRestoringScroll) return;

    final offset = scrollController.offset;
    _lastScrollPosition = offset;
    book.scrollPosition = offset;
    book.currentPage = _currentPage;
    book.readingMode = _readingMode;
    book.lastReadingSentenceStart = _inPageScrollOffset.round();

    repository.updateReadingProgress(
      book.id,
      currentPage: _currentPage,
      totalPages: _pageCount,
      scrollPosition: offset,
      readingMode: _readingMode,
      lastReadingSentenceStart: _inPageScrollOffset.round(),
    );
  }

  void _anchorToPage(int targetPage, double inPageOffset, {int attempt = 0}) {
    if (targetPage < 0 || targetPage >= _pageCount) {
      isRestoringScroll = false;
      return;
    }
    if (!scrollController.hasClients) {
      if (attempt < 12) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
        });
      } else {
        isRestoringScroll = false;
      }
      return;
    }

    isRestoringScroll = true;

    final key = targetPage < _pageKeys.length ? _pageKeys[targetPage] : null;
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      final renderBox = targetContext.findRenderObject() as RenderBox?;
      RenderBox? viewportBox;
      try {
        final scrollable = Scrollable.maybeOf(targetContext);
        viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
      } catch (_) {}

      if (viewportBox == null && scrollController.hasClients) {
        try {
          final scrollCtx = scrollController.position.context.notificationContext;
          viewportBox = scrollCtx?.findRenderObject() as RenderBox?;
        } catch (_) {}
      }

      if (renderBox != null && renderBox.hasSize && viewportBox != null && viewportBox.hasSize) {
        final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
        final currentItemStart = isHorizontal
            ? renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx
            : renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
        final delta = currentItemStart + inPageOffset;
        final targetOffset = (scrollController.offset + delta).clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        );

        if ((scrollController.offset - targetOffset).abs() > 0.5) {
          scrollController.jumpTo(targetOffset);
        }

        if (targetOffset == scrollController.position.maxScrollExtent && delta > 1.0 && attempt < 10) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
          });
          return;
        }

        _currentPage = targetPage;
        _inPageScrollOffset = inPageOffset;
        book.currentPage = targetPage;
        book.lastReadingSentenceStart = inPageOffset.round();
        isRestoringScroll = false;
        notifyListeners();
        return;
      }
    }

    // Target context is not yet mounted; jump toward estimated offset so Flutter builds it
    final position = scrollController.position;
    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
    final isWebtoon = _readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;

    // Cross-axis dimension: for vertical continuous, it's viewport width; for horizontal, viewport height.
    double crossAxis = 0.0;
    try {
      final scrollCtx = position.context.notificationContext;
      final box = scrollCtx?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        crossAxis = isHorizontal ? box.size.height : box.size.width;
      }
    } catch (_) {}

    if (crossAxis <= 0) {
      crossAxis = isHorizontal
          ? (_viewportHeight ?? 800.0)
          : (_viewportWidth ?? 500.0);
    }

    final defaultAr = _cacheController?.getEstimatedAspectRatio(targetPage) ?? 0.70;

    double estimatedOffset = 0.0;
    for (int i = 0; i < targetPage; i++) {
      if (_pageExtents.containsKey(i)) {
        estimatedOffset += _pageExtents[i]! + spacing;
      } else {
        final ar = _cacheController?.getEstimatedAspectRatio(i) ?? defaultAr;
        final extent = isHorizontal ? (crossAxis * ar) : (crossAxis / ar);
        estimatedOffset += extent + spacing;
      }
    }
    estimatedOffset += inPageOffset;

    final maxExtent = position.maxScrollExtent;
    final targetJump = (maxExtent > 0 && estimatedOffset > maxExtent)
        ? maxExtent
        : estimatedOffset;

    if ((position.pixels - targetJump).abs() > 1.0) {
      scrollController.jumpTo(targetJump);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        isRestoringScroll = false;
        return;
      }
      if (attempt < 15) {
        _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
      } else {
        isRestoringScroll = false;
      }
    });
  }

  void restoreContinuousScroll({int attempt = 0}) {
    if (!isContinuousMode) return;
    if (_pageCount == 0) return;
    if (isRestoringScroll && attempt == 0) return;
    _anchorToPage(_currentPage, _inPageScrollOffset, attempt: attempt);
  }

  void scrollToPage(int targetPage, {int attempt = 0}) {
    if (targetPage < 0 || targetPage >= _pageCount) return;
    _inPageScrollOffset = 0.0;
    _anchorToPage(targetPage, 0.0, attempt: attempt);
  }

  void jumpToPage(int page) {
    if (page < 0 || page >= _pageCount) return;
    _currentPage = page;
    book.currentPage = page;

    if (isContinuousMode) {
      scrollToPage(page);
    } else {
      notifyListeners();
    }

    repository.updateReadingProgress(
      book.id,
      currentPage: page,
      totalPages: _pageCount,
      readingMode: _readingMode,
    );
  }

  void swipeToPage(int delta) {
    jumpToPage(_currentPage + delta);
  }

  void updateReadingMode(ReadingMode mode, {BuildContext? context}) {
    if (_readingMode == mode) return;

    final wasContinuous = isContinuousMode;
    final wasVertical = _readingMode == ReadingMode.verticalContinuous ||
        _readingMode == ReadingMode.webtoon;

    // 1. Accurately save progress in current mode BEFORE switching
    if (wasContinuous) {
      if (context != null) {
        updateCurrentPageFromScroll(context, force: true);
      }
      saveContinuousProgress();
    } else {
      book.currentPage = _currentPage;
      repository.updateReadingProgress(
        book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
        readingMode: mode,
      );
    }

    _readingMode = mode;
    book.readingMode = mode;
    _pageExtents.clear(); // Reset measured extents as layout/direction/spacing changed
    repository.updateReadingProgress(book.id, readingMode: mode);

    final nowContinuous = isContinuousMode;
    final nowVertical = mode == ReadingMode.verticalContinuous ||
        mode == ReadingMode.webtoon;

    if (nowContinuous) {
      isRestoringScroll = true; // Lock scroll listener to prevent progress clobbering during rebuild
      final preserveInPageOffset = wasVertical && nowVertical;
      final targetInPageOffset = preserveInPageOffset ? _inPageScrollOffset : 0.0;
      _inPageScrollOffset = targetInPageOffset;
      _lastScrollPosition = 0.0;
      book.scrollPosition = 0.0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _anchorToPage(_currentPage, targetInPageOffset);
      });
    }

    notifyListeners();
  }

  void _saveProgressOnDispose() {
    if (isContinuousMode) {
      saveContinuousProgress();
    } else if (_pageCount > 0) {
      book.currentPage = _currentPage;
      book.readingMode = _readingMode;
      repository.updateReadingProgress(
        book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
        readingMode: _readingMode,
      );
    }
  }

  void cleanupTempFile() {
    if (_resolvedFile == null || !_resolvedFile!.isTemp) return;
    try {
      unawaited(File(_resolvedFile!.path).delete());
    } catch (_) {}
  }
}
