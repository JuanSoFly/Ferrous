import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/src/rust/api/crop.dart';
import '../controllers/pdf_page_controller.dart';
import '../controllers/pdf_tts_controller.dart';
import '../controllers/reader_chrome_controller.dart';
import '../controllers/reader_mode_controller.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';

class PdfPageViewer extends StatefulWidget {
  final PdfPageController pageController;
  final PdfTtsController ttsController;
  final ReaderChromeController chromeController;
  final ReaderModeController modeController;
  final TransformationController transformController;
  final GlobalKey pageImageKey;

  const PdfPageViewer({
    super.key,
    required this.pageController,
    required this.ttsController,
    required this.chromeController,
    required this.modeController,
    required this.transformController,
    required this.pageImageKey,
  });

  @override
  State<PdfPageViewer> createState() => _PdfPageViewerState();
}

class _PdfPageViewerState extends State<PdfPageViewer> {
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
  void didUpdateWidget(PdfPageViewer oldWidget) {
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
    if (_viewPageController.hasClients) {
      final target = widget.pageController.pageIndex;
      if (_viewPageController.page?.round() != target) {
        _syncing = true;
        _viewPageController.jumpToPage(target);
        _syncing = false;
      }
    } else {
      final target = widget.pageController.pageIndex;
      if (_viewPageController.initialPage != target) {
        _viewPageController.dispose();
        _viewPageController = PageController(initialPage: target);
      }
    }
    // Trigger rebuild for loading/image state changes
    setState(() {});
  }

  void _onTransformChanged() {
    setState(() {});
  }

  void _onPageViewChanged(int index) {
    if (_syncing) return;
    _syncing = true;
    widget.pageController.renderPage(index, userInitiated: true);
    widget.transformController.value = Matrix4.identity();
    _syncing = false;
  }

  bool _canSwipe() {
    final scale = widget.transformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  @override
  Widget build(BuildContext context) {
    final pageController = widget.pageController;

    if (pageController.error != null) {
      return _buildErrorState(pageController.error!);
    }

    if (pageController.isLoading && pageController.currentPageImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pageController.currentPageImage == null) {
      return const Center(child: Text("Initializing..."));
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) => _handleTapUp(context, details),
      onDoubleTapDown: (details) {},
      onDoubleTap: _handleDoubleTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          widget.pageController.viewerSize =
              Size(constraints.maxWidth, constraints.maxHeight);

          return _buildGallery();
        },
      ),
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
    return PageView.builder(
      controller: _viewPageController,
      scrollDirection: widget.modeController.useVerticalSwipe
          ? Axis.vertical
          : Axis.horizontal,
      physics: _canSwipe()
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: widget.pageController.pageCount,
      onPageChanged: _onPageViewChanged,
      itemBuilder: (context, index) {
        return InteractiveViewer(
          transformationController: widget.transformController,
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: true,
          scaleEnabled: true,
          child: Center(
            child: _buildPageLayer(context, index),
          ),
        );
      },
    );
  }

  Widget _buildVerticalContinuousView() {
    final isWebtoon = widget.pageController.readingMode == ReadingMode.webtoon;
    final spacing = isWebtoon ? 1.0 : 12.0;
    final size = MediaQuery.of(context).size;

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
        scrollCacheExtent: ScrollCacheExtent.pixels(size.height),
        controller: widget.pageController.scrollController,
        key: PageStorageKey(
            'pdf-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: Center(
              child: _buildPageLayer(context, index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalContinuousView() {
    final size = MediaQuery.of(context).size;

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
        scrollCacheExtent: ScrollCacheExtent.pixels(size.width),
        controller: widget.pageController.scrollController,
        key: PageStorageKey(
            'pdf-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: Center(
              child: _buildPageLayer(context, index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageLayer(BuildContext context, int index) {
    final pageController = widget.pageController;
    final ttsController = widget.ttsController;
    final pageImage = pageController.getPageImage(index);

    if (pageImage == null) {
      // Page not yet rendered — safely trigger background prefetch and show placeholder.
      // Using preloadPage() avoids mutating the active page index or loading state,
      // which would cause re-entrant notifyListeners() during the build phase.
      pageController.preloadPage(index);

      double? placeholderHeight;
      double? placeholderWidth;

      if (!pageController.viewerSize.isEmpty) {
        if (widget.modeController.isHorizontal) {
          placeholderHeight = pageController.viewerSize.height;
          placeholderWidth = pageController.viewerSize.width * 0.75;
        } else {
          placeholderWidth = pageController.viewerSize.width;
          placeholderHeight = pageController.viewerSize.width * 1.41;
          if (placeholderHeight > pageController.viewerSize.height) {
            placeholderHeight = pageController.viewerSize.height;
          }
        }
      } else {
        placeholderHeight = 400.0;
      }

      return Container(
        width: placeholderWidth,
        height: placeholderHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      );
    }

    final isActive = index == pageController.pageIndex;
    final isHighlightPage = index == ttsController.highlightPageIndex;
    final margins = pageController.getPageMargins(index);

    Widget imageWidget = Image.memory(pageImage, fit: BoxFit.contain);

    Widget layer;
    // Use logicalPageSize for stable UI layout
    final layoutSize = pageController.getLogicalPageSize(index).isEmpty
        ? (pageController.logicalPageSize.isEmpty
            ? pageController.renderedPageSize
            : pageController.logicalPageSize)
        : pageController.getLogicalPageSize(index);

    final themeRepo = context.watch<ReaderThemeRepository>();
    final highlightStyle = themeRepo.highlightStyle;

    if (layoutSize.isEmpty) {
      layer = imageWidget;
    } else {
      layer = SizedBox(
        width: layoutSize.width,
        height: layoutSize.height,
        child: Stack(
          children: [
            Positioned.fill(child: imageWidget),
            if (isActive || isHighlightPage)
              ListenableBuilder(
                listenable: ttsController,
                builder: (context, _) {
                  if (!ttsController.showTtsControls ||
                      ttsController.ttsHighlightRects.isEmpty ||
                      ttsController.highlightPageIndex != index) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: PdfHighlightPainter(
                          rects: ttsController.ttsHighlightRects,
                          style: highlightStyle,
                          primaryColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    }

    if (pageController.autoCrop && margins != null) {
      layer = FittedBox(
        fit: BoxFit.contain,
        child: ClipRect(
          clipper: MarginClipper(margins),
          child: layer,
        ),
      );
    }

    // Only attach pageImageKey to the active page for TTS tap detection
    if (isActive) {
      return KeyedSubtree(
        key: ValueKey(index),
        child: RepaintBoundary(
          key: widget.pageImageKey,
          child: layer,
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey(index),
      child: RepaintBoundary(child: layer),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text("Error: $error", textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _handleTapUp(BuildContext context, TapUpDetails details) {
    final chromeController = widget.chromeController;
    final screenSize = MediaQuery.of(context).size;

    if (chromeController.isCenterTap(details.globalPosition, screenSize)) {
      chromeController.toggleChrome();
      return;
    }

    if (chromeController.isLocked) return;

    // Start TTS from tap
    final imageContext = widget.pageImageKey.currentContext;
    if (imageContext == null) return;

    final imageBox = imageContext.findRenderObject() as RenderBox?;
    if (imageBox == null) return;

    final local = imageBox.globalToLocal(details.globalPosition);
    widget.ttsController.startTtsFromTap(local, imageBox.size);
  }

  void _handleDoubleTap() {
    final chromeController = widget.chromeController;
    if (!chromeController.isLocked) return;

    // Double-tap lock toggle is handled by the parent GestureDetector
  }
}

class MarginClipper extends CustomClipper<Rect> {
  final CropMargins margins;
  MarginClipper(this.margins);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(
        size.width * margins.left,
        size.height * margins.top,
        size.width * (1.0 - margins.left - margins.right),
        size.height * (1.0 - margins.top - margins.bottom),
      );
  @override
  bool shouldReclip(covariant MarginClipper oldClipper) =>
      margins != oldClipper.margins;
}

class PdfHighlightPainter extends CustomPainter {
  final List<PdfTextRect> rects;
  final TtsHighlightStyle style;
  final Color primaryColor;

  PdfHighlightPainter({
    required this.rects,
    required this.style,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || size.isEmpty) return;

    for (final rect in rects) {
      final r = Rect.fromLTRB(
        (rect.left * size.width).clamp(0.0, size.width),
        (rect.top * size.height).clamp(0.0, size.height),
        (rect.right * size.width).clamp(0.0, size.width),
        (rect.bottom * size.height).clamp(0.0, size.height),
      );
      if (r.width <= 0 || r.height <= 0) continue;

      final inflated = r.inflate(2.0);

      switch (style) {
        case TtsHighlightStyle.softPill:
          final fillPaint = Paint()
            ..color = primaryColor.withValues(alpha: 0.20)
            ..style = PaintingStyle.fill;
          final rr = RRect.fromRectAndRadius(inflated, const Radius.circular(4));
          canvas.drawRRect(rr, fillPaint);
          break;

        case TtsHighlightStyle.underline:
          final linePaint = Paint()
            ..color = primaryColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5;
          // Draw a line at the bottom of the word/rect
          canvas.drawLine(
            Offset(r.left, r.bottom + 1),
            Offset(r.right, r.bottom + 1),
            linePaint,
          );
          break;

        case TtsHighlightStyle.classicClean:
          final fillPaint = Paint()
            ..color = primaryColor.withValues(alpha: 0.12)
            ..style = PaintingStyle.fill;
          final borderPaint = Paint()
            ..color = primaryColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          final rr = RRect.fromRectAndRadius(inflated, const Radius.circular(4));
          canvas.drawRRect(rr, fillPaint);
          canvas.drawRRect(rr, borderPaint);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant PdfHighlightPainter oldDelegate) =>
      oldDelegate.rects != rects ||
      oldDelegate.style != style ||
      oldDelegate.primaryColor != primaryColor;
}
