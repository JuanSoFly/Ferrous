import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import '../controllers/cbz_page_controller.dart';
import '../controllers/reader_chrome_controller.dart';
import '../controllers/reader_mode_controller.dart';
import 'cbz_adaptive_background.dart';
import 'cbz_page_image.dart';
import 'realistic_page_turn.dart';
import 'package:reader_app/features/reader/widgets/reader_error_view.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class CbzPageViewer extends StatefulWidget {
  final CbzPageController pageController;
  final ReaderChromeController chromeController;
  final ReaderModeController modeController;
  final TransformationController transformController;

  const CbzPageViewer({
    super.key,
    required this.pageController,
    required this.chromeController,
    required this.modeController,
    required this.transformController,
  });

  @override
  State<CbzPageViewer> createState() => _CbzPageViewerState();
}

class _CbzPageViewerState extends State<CbzPageViewer> {
  late PageController _viewPageController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _viewPageController = PageController(
      initialPage: widget.pageController.pageIndex,
    );
    widget.pageController.addListener(_onPageControllerChanged);
    widget.transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(CbzPageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.removeListener(_onPageControllerChanged);
      widget.pageController.addListener(_onPageControllerChanged);
    }
    if (oldWidget.transformController != widget.transformController) {
      oldWidget.transformController.removeListener(_onTransformChanged);
      widget.transformController.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onPageControllerChanged);
    widget.transformController.removeListener(_onTransformChanged);
    _viewPageController.dispose();
    super.dispose();
  }

  void _onPageControllerChanged() {
    if (_syncing) return;
    if (!_viewPageController.hasClients) return;
    final target = widget.pageController.pageIndex;
    if (_viewPageController.page?.round() != target) {
      _syncing = true;
      _viewPageController.jumpToPage(target);
      _syncing = false;
    }
  }

  PageController _getOrUpdatePageController() {
    final target = widget.pageController.pageIndex;
    if (!_viewPageController.hasClients) {
      if (_viewPageController.initialPage != target) {
        _viewPageController.dispose();
        _viewPageController = PageController(initialPage: target);
      }
    }
    return _viewPageController;
  }

  void _onTransformChanged() {
    // Force rebuild to update scroll physics based on zoom scale
    setState(() {});
  }

  bool _canSwipePages() {
    final scale = widget.transformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  void _onPageViewSettled(int index) {
    if (_syncing) return;
    if (widget.pageController.pageIndex == index) return;
    _syncing = true;
    widget.pageController.jumpToPage(index);
    widget.transformController.value = Matrix4.identity();
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    widget.pageController.updateViewportDimensions(size.width, size.height);

    return ListenableBuilder(
      listenable: widget.pageController,
      builder: (context, _) {
        if (widget.pageController.error != null) {
          final currentTheme = context.watch<AppTheme?>();
          final isEInk = currentTheme == AppTheme.eInk;
          return ReaderErrorView(
            formatTitle: 'Comic (CBZ/CBR)',
            error: widget.pageController.error!,
            isEInk: isEInk,
          );
        }

        if (widget.pageController.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (widget.pageController.pageCount == 0) {
          return const Center(child: Text("No images found in archive"));
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: _handleTapUp,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: _buildGallery(),
        );
      },
    );
  }

  Widget _buildGallery() {
    final mode = widget.pageController.readingMode;

    if (mode == ReadingMode.vertical || mode == ReadingMode.leftToRight) {
      return _buildPagedView();
    }

    if (mode == ReadingMode.verticalContinuous || mode == ReadingMode.webtoon) {
      return _buildVerticalContinuousView();
    }

    if (mode == ReadingMode.horizontalContinuous) {
      return _buildHorizontalContinuousView();
    }

    return _buildPagedView();
  }

  Widget _buildPagedView() {
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final maxWidth = (size.width * devicePixelRatio).round();

    final themeRepo = context.watch<ReaderThemeRepository>();
    final isVertical = widget.pageController.readingMode == ReadingMode.vertical;
    final useRealisticCurl =
        !isVertical &&
        themeRepo.config.pageFlip &&
        _canSwipePages();

    if (useRealisticCurl) {
      return RealisticPageTurn(
        key: const ValueKey('cbz-page-turn'),
        pageCount: widget.pageController.pageCount,
        currentPage: widget.pageController.pageIndex,
        textureId: BookTextures.none,
        showSpine: false,
        onPageChanged: _onPageViewSettled,
        onToggleChrome: () => widget.chromeController.toggleChrome(),
        pageBuilder: (context, index) {
          final colors = widget.pageController.getCornerColorsForPage(index);
          final ar = widget.pageController.cacheController?.getEstimatedAspectRatio(index);
          return CbzPageLetterboxContainer(
            colors: colors,
            readingMode: widget.pageController.readingMode,
            aspectRatio: ar,
            child: InteractiveViewer(
              key: ValueKey('cbz-interactive-$index'),
              transformationController: widget.transformController,
              maxScale: 5.0,
              child: _buildPageImage(index, maxWidth),
            ),
          );
        },
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final page = _viewPageController.page?.round();
          if (page != null &&
              page >= 0 &&
              page < widget.pageController.pageCount &&
              page != widget.pageController.pageIndex) {
            _onPageViewSettled(page);
          }
        }
        return false;
      },
      child: PageView.builder(
        key: ValueKey('cbz-paged-$isVertical'),
        controller: _getOrUpdatePageController(),
        scrollDirection: isVertical
            ? Axis.vertical
            : Axis.horizontal,
        physics: _canSwipePages()
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: widget.pageController.pageCount,
        onPageChanged: (candidateIndex) {
          // Preload hint only: do NOT jumpToPage here to prevent transient out-of-sync jumps
          widget.pageController.cacheController?.preloadAround(candidateIndex, maxWidth);
        },
        itemBuilder: (context, index) {
          final colors = widget.pageController.getCornerColorsForPage(index);
          final ar = widget.pageController.cacheController?.getEstimatedAspectRatio(index);
          return CbzPageLetterboxContainer(
            colors: colors,
            readingMode: widget.pageController.readingMode,
            aspectRatio: ar,
            child: InteractiveViewer(
              key: ValueKey('cbz-interactive-$index'),
              transformationController: widget.transformController,
              maxScale: 5.0,
              child: _buildPageImage(index, maxWidth),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageImage(int index, int maxWidth, {double fallbackAspectRatio = 0.70}) {
    final pageName = widget.pageController.pageNames[index];

    return CbzPageImage(
      key: ValueKey('cbz-page-$index'),
      pageIndex: index,
      pageName: pageName,
      fit: BoxFit.contain,
      maxWidth: maxWidth,
      cacheController: widget.pageController.cacheController!,
      fallbackAspectRatio: fallbackAspectRatio,
      onPageLoaded: () => widget.pageController.notifyCornerColorsAvailable(index),
    );
  }

  Widget _buildVerticalContinuousView() {
    final isWebtoon = widget.pageController.readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final maxWidth = (size.width * devicePixelRatio).round();
    final fallbackAr = isWebtoon ? 0.30 : 0.70;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (widget.pageController.isRestoringScroll) return false;
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.pageController.updateCurrentPageFromScroll(context, force: true);
          widget.pageController.flushContinuousProgressSave();
        } else if (notification is ScrollUpdateNotification) {
          widget.pageController.updateCurrentPageFromScroll(context);
        }
        return false;
      },
      child: ListView.separated(
        key: ValueKey('cbz-vertical-continuous-${widget.pageController.readingMode.name}'),
        scrollCacheExtent: ScrollCacheExtent.pixels(size.height * 2),
        controller: widget.pageController.scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (context, index) {
          final key = index < widget.pageController.pageKeys.length
              ? widget.pageController.pageKeys[index]
              : null;
          final colors = widget.pageController.getCornerColorsForPage(index);
          final ar = widget.pageController.cacheController?.getEstimatedAspectRatio(index, fallback: fallbackAr);
          return RepaintBoundary(
            key: key,
            child: CbzPageLetterboxContainer(
              colors: colors,
              readingMode: widget.pageController.readingMode,
              aspectRatio: ar,
              child: CbzPageImage(
                key: ValueKey('cbz-page-$index'),
                pageIndex: index,
                pageName: widget.pageController.pageNames[index],
                fit: BoxFit.contain,
                maxWidth: maxWidth,
                cacheController: widget.pageController.cacheController!,
                fallbackAspectRatio: fallbackAr,
                onPageLoaded: () => widget.pageController.notifyCornerColorsAvailable(index),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalContinuousView() {
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final maxWidth = (size.width * devicePixelRatio).round();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (widget.pageController.isRestoringScroll) return false;
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.pageController.updateCurrentPageFromScroll(context, force: true);
          widget.pageController.flushContinuousProgressSave();
        } else if (notification is ScrollUpdateNotification) {
          widget.pageController.updateCurrentPageFromScroll(context);
        }
        return false;
      },
      child: ListView.separated(
        key: const ValueKey('cbz-horizontal-continuous'),
        scrollCacheExtent: ScrollCacheExtent.pixels(size.width * 2),
        controller: widget.pageController.scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final key = index < widget.pageController.pageKeys.length
              ? widget.pageController.pageKeys[index]
              : null;
          final colors = widget.pageController.getCornerColorsForPage(index);
          final ar = widget.pageController.cacheController?.getEstimatedAspectRatio(index, fallback: 1.40);
          return RepaintBoundary(
            key: key,
            child: CbzPageLetterboxContainer(
              colors: colors,
              readingMode: widget.pageController.readingMode,
              aspectRatio: ar,
              child: CbzPageImage(
                key: ValueKey('cbz-page-$index'),
                pageIndex: index,
                pageName: widget.pageController.pageNames[index],
                fit: BoxFit.contain,
                maxWidth: maxWidth,
                cacheController: widget.pageController.cacheController!,
                fallbackAspectRatio: 1.40,
                onPageLoaded: () => widget.pageController.notifyCornerColorsAvailable(index),
              ),
            ),
          );
        },
      ),
    );
  }

  // Tap handlers

  Offset? _lastDoubleTapDown;

  void _handleTapUp(TapUpDetails details) {
    final screenSize = MediaQuery.of(context).size;
    if (widget.chromeController
        .isCenterTap(details.globalPosition, screenSize)) {
      widget.chromeController.toggleChrome();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!widget.chromeController.isLocked) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    final screenSize = MediaQuery.of(context).size;
    if (widget.chromeController.isCenterTap(position, screenSize)) {
      _toggleLockModeWithFeedback();
    }
  }

  void _toggleLockModeWithFeedback() {
    final isLocked = widget.chromeController.toggleLockMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isLocked
              ? 'Lock mode on. Double-tap center to unlock.'
              : 'Lock mode off.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
