import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/data/models/book.dart';
import '../controllers/cbz_page_controller.dart';
import '../controllers/reader_chrome_controller.dart';
import '../controllers/reader_mode_controller.dart';
import 'cbz_page_image.dart';

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
  Offset? _lastDoubleTapDown;

  void _handleTapUp(TapUpDetails details) {
    final screenSize = MediaQuery.of(context).size;
    if (widget.chromeController.isCenterTap(details.globalPosition, screenSize)) {
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

  bool _canSwipePages() {
    final scale = widget.transformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!widget.modeController.useHorizontalSwipe || !widget.modeController.isPagedMode) return;
    if (!_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    if (velocity > 0) {
      widget.pageController.swipeToPage(-1);
    } else {
      widget.pageController.swipeToPage(1);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!widget.modeController.useVerticalSwipe || !widget.modeController.isPagedMode) return;
    if (!_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    if (velocity > 0) {
      widget.pageController.swipeToPage(-1);
    } else {
      widget.pageController.swipeToPage(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pageController,
      builder: (context, _) {
        if (widget.pageController.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text("Error: ${widget.pageController.error}", textAlign: TextAlign.center),
                ],
              ),
            ),
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
          onHorizontalDragEnd: widget.modeController.isPagedMode && widget.modeController.useHorizontalSwipe 
              ? _handleHorizontalDragEnd : null,
          onVerticalDragEnd: widget.modeController.isPagedMode && widget.modeController.useVerticalSwipe 
              ? _handleVerticalDragEnd : null,
          child: _buildGallery(),
        );
      },
    );
  }

  Widget _buildGallery() {
    final mode = widget.pageController.readingMode;
    
    if (widget.modeController.isPagedMode) {
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
    
    final page = CbzPageImage(
      pageIndex: widget.pageController.pageIndex,
      pageName: widget.pageController.pageNames[widget.pageController.pageIndex],
      fit: BoxFit.contain,
      maxWidth: maxWidth,
      cacheController: widget.pageController.cacheController!,
    );

    return InteractiveViewer(
      transformationController: widget.transformController,
      maxScale: 5.0,
      child: KeyedSubtree(
        key: ValueKey(widget.pageController.pageIndex),
        child: Center(child: page),
      ),
    );
  }

  Widget _buildVerticalContinuousView() {
    final isWebtoon = widget.pageController.readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;
    final size = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final maxWidth = (size.width * devicePixelRatio).round();
    
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.pageController.flushContinuousProgressSave();
        }
        return false;
      },
      child: ListView.separated(
        controller: widget.pageController.scrollController,
        key: PageStorageKey('cbz-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: widget.pageController.pageCount,
        cacheExtent: size.height,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: CbzPageImage(
              pageIndex: index,
              pageName: widget.pageController.pageNames[index],
              fit: BoxFit.contain,
              maxWidth: maxWidth,
              cacheController: widget.pageController.cacheController!,
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
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.pageController.flushContinuousProgressSave();
        }
        return false;
      },
      child: ListView.separated(
        controller: widget.pageController.scrollController,
        key: PageStorageKey('cbz-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.pageController.pageCount,
        cacheExtent: size.width,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: CbzPageImage(
              pageIndex: index,
              pageName: widget.pageController.pageNames[index],
              fit: BoxFit.contain,
              maxWidth: maxWidth,
              cacheController: widget.pageController.cacheController!,
            ),
          );
        },
      ),
    );
  }
}
