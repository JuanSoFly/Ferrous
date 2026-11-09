import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;
import 'package:reader_app/core/utils/performance.dart';
import '../models/page_corner_colors.dart';
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

  /// Current visible page's detected corner and edge colors.
  PageCornerColors? get currentCornerColors =>
      _cacheController?.getCornerColors(_currentPage);

  /// Get detected corner colors for an arbitrary page index.
  PageCornerColors? getCornerColorsForPage(int pageIndex) =>
      _cacheController?.getCornerColors(pageIndex);

  /// Called when a page's corner colors become available to update background if it is current.
  void notifyCornerColorsAvailable(int pageIndex) {
    if (pageIndex == _currentPage) {
      notifyListeners();
    }
  }

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

        // Pre-warm the target reading page and immediate neighbors before revealing content
        final targetIndex = (_currentPage >= 0 && _currentPage < names.length) ? _currentPage : 0;
        final futures = <Future<dynamic>>[
          _cacheController!.loadPage(targetIndex, 1080),
        ];
        if (targetIndex > 0) {
          futures.add(_cacheController!.loadPage(targetIndex - 1, 1080));
        }
        if (targetIndex + 1 < names.length) {
          futures.add(_cacheController!.loadPage(targetIndex + 1, 1080));
        }
        await Future.wait(futures);

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

  double _getDefaultAspectRatioForMode() {
    switch (_readingMode) {
      case ReadingMode.webtoon:
        return 0.30;
      case ReadingMode.horizontalContinuous:
        return 1.40;
      case ReadingMode.verticalContinuous:
      case ReadingMode.vertical:
      case ReadingMode.leftToRight:
        return 0.70;
    }
  }

  void _syncCurrentPageFromScrollSynchronous() {
    if (_pageKeys.isEmpty || !scrollController.hasClients) return;
    RenderBox? viewportBox;
    try {
      final scrollCtx = scrollController.position.context.notificationContext;
      viewportBox = scrollCtx?.findRenderObject() as RenderBox?;
    } catch (_) {}
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

      _currentPage = bestIndex;
      book.currentPage = bestIndex;
    }
  }

  void saveProgressImmediately() {
    _progressSaveTimer?.cancel();
    if (!scrollController.hasClients) return;
    if (_pageCount == 0) return;
    if (isRestoringScroll) return;

    _syncCurrentPageFromScrollSynchronous();

    final offset = scrollController.offset;
    _lastScrollPosition = offset;
    book.scrollPosition = offset;
    book.currentPage = _currentPage;
    book.readingMode = _readingMode;
    book.lastReadingSentenceStart = _inPageScrollOffset.round();

    if (_viewportWidth != null && _viewportHeight != null) {
      final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
      final crossAxis = isHorizontal ? _viewportHeight! : _viewportWidth!;
      if (crossAxis > 0) {
        book.lastReadingSentenceEnd = crossAxis.round();
      }
    }

    repository.updateReadingProgress(
      book.id,
      currentPage: _currentPage,
      totalPages: _pageCount,
      scrollPosition: offset,
      readingMode: _readingMode,
      lastReadingSentenceStart: _inPageScrollOffset.round(),
      lastReadingSentenceEnd: book.lastReadingSentenceEnd,
    );
  }

  void saveContinuousProgress() {
    saveProgressImmediately();
  }

  double _calculateEstimatedOffsetForPage(int targetPage, double inPageOffset, double crossAxis) {
    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;
    final isWebtoon = _readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;
    const padding = 16.0;
    final defaultAr = _getDefaultAspectRatioForMode();

    double estimatedOffset = padding;
    for (int i = 0; i < targetPage; i++) {
      if (_pageExtents.containsKey(i)) {
        estimatedOffset += _pageExtents[i]! + spacing;
      } else {
        final ar = _cacheController?.getEstimatedAspectRatio(i, fallback: defaultAr) ?? defaultAr;
        final extent = isHorizontal ? (crossAxis * ar) : (crossAxis / ar);
        estimatedOffset += extent + spacing;
      }
    }
    estimatedOffset += inPageOffset;
    return estimatedOffset;
  }

  void _anchorToPage(int targetPage, double inPageOffset, {int attempt = 0}) {
    if (targetPage < 0 || targetPage >= _pageCount) {
      isRestoringScroll = false;
      return;
    }
    if (!scrollController.hasClients) {
      if (attempt < 25) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
        });
      } else {
        isRestoringScroll = false;
      }
      return;
    }

    isRestoringScroll = true;

    final position = scrollController.position;
    final isHorizontal = _readingMode == ReadingMode.horizontalContinuous;

    double crossAxis = 0.0;
    RenderBox? viewportBox;
    try {
      final scrollCtx = position.context.notificationContext;
      viewportBox = scrollCtx?.findRenderObject() as RenderBox?;
      if (viewportBox != null && viewportBox.hasSize) {
        crossAxis = isHorizontal ? viewportBox.size.height : viewportBox.size.width;
      }
    } catch (_) {}

    if (crossAxis <= 0) {
      crossAxis = isHorizontal
          ? (_viewportHeight ?? 800.0)
          : (_viewportWidth ?? 500.0);
    }

    final savedCrossAxis = book.lastReadingSentenceEnd > 0
        ? book.lastReadingSentenceEnd.toDouble()
        : 0.0;
    final sameOrientation = savedCrossAxis > 0 && (crossAxis - savedCrossAxis).abs() < 5.0;

    final key = targetPage < _pageKeys.length ? _pageKeys[targetPage] : null;
    final targetContext = key?.currentContext;

    if (targetContext != null) {
      final renderBox = targetContext.findRenderObject() as RenderBox?;
      if (viewportBox == null) {
        try {
          final scrollable = Scrollable.maybeOf(targetContext);
          viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
        } catch (_) {}
      }

      if (renderBox != null && renderBox.hasSize && viewportBox != null && viewportBox.hasSize) {
        final renderBoxExtent = isHorizontal ? renderBox.size.width : renderBox.size.height;
        if (renderBoxExtent > 0) {
          _pageExtents[targetPage] = renderBoxExtent;
        }

        // Check if image is ready and layout bounds reflect the real image (not placeholder)
        final isDecoded = _cacheController?.isPageDecoded(targetPage) ?? false;
        final knownAr = _cacheController?.getKnownAspectRatio(targetPage);
        bool isBoundsConfirmed = false;
        if (knownAr != null && knownAr > 0 && crossAxis > 0) {
          final expectedExtent = isHorizontal ? (crossAxis * knownAr) : (crossAxis / knownAr);
          isBoundsConfirmed = (renderBoxExtent - expectedExtent).abs() < 3.0;
        } else if (isDecoded) {
          isBoundsConfirmed = true;
        }

        // If target image is still decoding or transitioning layout, wait for next frame
        if (!isBoundsConfirmed && attempt < 25) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
          });
          return;
        }

        // Calculate accurate target offset
        final currentItemStart = isHorizontal
            ? renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx
            : renderBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;

        double targetOffset;
        if (sameOrientation && _lastScrollPosition > 0) {
          targetOffset = _lastScrollPosition;
        } else {
          final delta = currentItemStart + inPageOffset;
          targetOffset = scrollController.offset + delta;
        }
        targetOffset = targetOffset.clamp(0.0, position.maxScrollExtent);

        if ((scrollController.offset - targetOffset).abs() > 0.5) {
          scrollController.jumpTo(targetOffset);
        }

        // Allow one post-frame callback for sliver geometry to settle before releasing lock
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) {
            isRestoringScroll = false;
            return;
          }
          final currentDiff = (scrollController.offset - targetOffset).abs();
          if (currentDiff > 1.0 && attempt < 25) {
            _anchorToPage(targetPage, inPageOffset, attempt: attempt + 1);
          } else {
            _currentPage = targetPage;
            _inPageScrollOffset = inPageOffset;
            _lastScrollPosition = scrollController.offset;
            book.currentPage = targetPage;
            book.scrollPosition = scrollController.offset;
            book.lastReadingSentenceStart = inPageOffset.round();
            isRestoringScroll = false;
            notifyListeners();
          }
        });
        return;
      }
    }

    // Target context is not yet mounted in the viewport; perform coarse jump toward estimated position
    double targetOffset;
    if (sameOrientation && _lastScrollPosition > 0) {
      targetOffset = _lastScrollPosition;
    } else {
      targetOffset = _calculateEstimatedOffsetForPage(targetPage, inPageOffset, crossAxis);
    }

    final maxExtent = position.maxScrollExtent;
    final targetJump = (maxExtent > 0 && targetOffset > maxExtent)
        ? maxExtent
        : targetOffset;

    if ((position.pixels - targetJump).abs() > 1.0) {
      scrollController.jumpTo(targetJump);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        isRestoringScroll = false;
        return;
      }
      if (attempt < 25) {
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

    _cacheController?.preloadAround(page, 1080);

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
