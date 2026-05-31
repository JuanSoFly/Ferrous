import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/core/models/book.dart';
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
  late final PageController _viewPageController;
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

  void _onTransformChanged() {
    // Force rebuild to update scroll physics based on zoom scale
    setState(() {});
  }

  bool _canSwipePages() {
    final scale = widget.transformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  void _onPageViewChanged(int index) {
    if (_syncing) return;
    _syncing = true;
    widget.pageController.jumpToPage(index);
    widget.transformController.value = Matrix4.identity();
    _syncing = false;
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
                  Text("Error: ${widget.pageController.error}",
                      textAlign: TextAlign.center),
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

    return PageView.builder(
      controller: _viewPageController,
      scrollDirection: widget.modeController.useVerticalSwipe
          ? Axis.vertical
          : Axis.horizontal,
      physics: _canSwipePages()
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: widget.pageController.pageCount,
      onPageChanged: _onPageViewChanged,
      itemBuilder: (context, index) {
        return InteractiveViewer(
          transformationController: widget.transformController,
          maxScale: 5.0,
          child: _buildPageImage(index, maxWidth),
        );
      },
    );
  }

  Widget _buildPageImage(int index, int maxWidth) {
    final pageName = widget.pageController.pageNames[index];

    return CbzPageImage(
      pageIndex: index,
      pageName: pageName,
      fit: BoxFit.contain,
      maxWidth: maxWidth,
      cacheController: widget.pageController.cacheController!,
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
        cacheExtent: size.height, controller: widget.pageController.scrollController,
        key: PageStorageKey(
            'cbz-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: widget.pageController.pageCount,
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
        cacheExtent: size.width, controller: widget.pageController.scrollController,
        key: PageStorageKey(
            'cbz-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.pageController.pageCount,
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
