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
        separatorBuilder: _buildSeparator,
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
        separatorBuilder: _buildSeparator,
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

  bool _isNearBlack(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return r <= 24 && g <= 24 && b <= 24;
  }

  bool _areColorsSimilar(Color c1, Color c2, {double tolerance = 16.0}) {
    final dr = ((c1.r * 255) - (c2.r * 255)).abs();
    final dg = ((c1.g * 255) - (c2.g * 255)).abs();
    final db = ((c1.b * 255) - (c2.b * 255)).abs();
    return dr <= tolerance && dg <= tolerance && db <= tolerance;
  }

  Widget _buildSeparator(BuildContext context, int index) {
    final mode = widget.pageController.readingMode;
    final isWebtoon = mode == ReadingMode.webtoon;
    final isHorizontal = mode == ReadingMode.horizontalContinuous;
    final spacing = isWebtoon ? 1.0 : 12.0;

    final prevColors = widget.pageController.getCornerColorsForPage(index);
    final nextColors = widget.pageController.getCornerColorsForPage(index + 1);
    final theme = Theme.of(context);
    final defaultBg = theme.scaffoldBackgroundColor;

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final rawExit = isHorizontal
        ? (isRtl ? prevColors?.leftColor : prevColors?.rightColor)
        : prevColors?.bottomColor;
    final rawEntry = isHorizontal
        ? (isRtl ? nextColors?.rightColor : nextColors?.leftColor)
        : nextColors?.topColor;

    // Cascade fallbacks so unextracted adjacent page never flashes black
    final exitColor = rawExit ?? rawEntry ?? defaultBg;
    final entryColor = rawEntry ?? rawExit ?? defaultBg;

    final bool sameCanvas = (prevColors?.isMangaWhitePaper == true && nextColors?.isMangaWhitePaper == true) ||
        _areColorsSimilar(exitColor, entryColor, tolerance: 16);

    final Color separatorColor;
    if (sameCanvas) {
      separatorColor = exitColor; // Solid white canvas bridge in manga
    } else if (_isNearBlack(exitColor) || _isNearBlack(entryColor)) {
      separatorColor = const Color(0xFF000000); // Clean black gutter in contrasting color pages
    } else {
      separatorColor = defaultBg;
    }

    final size = MediaQuery.of(context).size;

    if (isHorizontal) {
      return SizedBox(
        width: spacing,
        height: size.height,
        child: ColoredBox(color: separatorColor),
      );
    }

    // Vertical continuous & Webtoon
    // User Guard 3: In Webtoon mode, do NOT shrink fittedWidth via size.height * ar,
    // keep full size.width because tall webtoon strips take full screen width.
    double separatorWidth = size.width;
    if (!isWebtoon) {
      final ar = widget.pageController.cacheController?.getEstimatedAspectRatio(index) ??
                 widget.pageController.cacheController?.getEstimatedAspectRatio(index + 1);
      if (ar != null && ar > 0) {
        final fittedW = (size.height * ar).clamp(0.0, size.width);
        if (fittedW > 0) {
          separatorWidth = fittedW;
        }
      }
    }

    return SizedBox(
      height: spacing,
      width: size.width,
      child: Center(
        child: SizedBox(
          width: separatorWidth,
          height: spacing,
          child: ColoredBox(color: separatorColor),
        ),
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
