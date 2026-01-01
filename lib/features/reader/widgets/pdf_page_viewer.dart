import 'package:flutter/material.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/src/rust/api/crop.dart';
import '../controllers/pdf_page_controller.dart';
import '../controllers/pdf_tts_controller.dart';
import '../controllers/reader_chrome_controller.dart';
import '../controllers/reader_mode_controller.dart';

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
  Offset? _lastDoubleTapDown;

  @override
  Widget build(BuildContext context) {
    final pageController = widget.pageController;
    return ListenableBuilder(
      listenable: pageController,
      builder: (context, _) {
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
          onDoubleTapDown: (details) => _lastDoubleTapDown = details.globalPosition,
          onDoubleTap: _handleDoubleTap,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              pageController.viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
              return InteractiveViewer(
                transformationController: widget.transformController,
                maxScale: 5.0,
                constrained: false,
                panEnabled: true,
                scaleEnabled: true,
                child: Center(
                  child: _buildPageLayer(context),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPageLayer(BuildContext context) {
    final pageController = widget.pageController;
    final ttsController = widget.ttsController;

    Widget imageWidget = Image.memory(
      pageController.currentPageImage!,
      fit: BoxFit.contain,
    );

    Widget layer;
    // Use logicalPageSize for stable UI layout (doesn't change with zoom resolution)
    final layoutSize = pageController.logicalPageSize.isEmpty 
        ? pageController.renderedPageSize 
        : pageController.logicalPageSize;
    if (layoutSize.isEmpty) {
      layer = imageWidget;
    } else {
      layer = SizedBox(
        width: layoutSize.width,
        height: layoutSize.height,
        child: Stack(
          children: [
            Positioned.fill(child: imageWidget),
            ListenableBuilder(
              listenable: ttsController,
              builder: (context, _) {
                if (!ttsController.showTtsControls || ttsController.ttsHighlightRects.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PdfHighlightPainter(
                        rects: ttsController.ttsHighlightRects,
                        fillColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.65),
                        borderColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
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

    if (pageController.autoCrop && pageController.currentMargins != null) {
      layer = FittedBox(
        fit: BoxFit.contain,
        child: ClipRect(
          clipper: MarginClipper(pageController.currentMargins!),
          child: layer,
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey(pageController.pageIndex),
      child: RepaintBoundary(
        key: widget.pageImageKey,
        child: layer,
      ),
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
    
    final pos = _lastDoubleTapDown;
    final screenSize = MediaQuery.of(context).size;
    
    if (pos != null && chromeController.isCenterTap(pos, screenSize)) {
       chromeController.toggleLockMode();
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final chromeController = widget.chromeController;
    final modeController = widget.modeController;
    final pageController = widget.pageController;
    
    if (chromeController.isLocked || !modeController.useHorizontalSwipe || !_canSwipe()) return;
    final delta = modeController.getHorizontalSwipeDelta(details.primaryVelocity ?? 0);
    if (delta != 0) pageController.renderPage(pageController.pageIndex + delta, userInitiated: true);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final chromeController = widget.chromeController;
    final modeController = widget.modeController;
    final pageController = widget.pageController;

    if (chromeController.isLocked || !modeController.useVerticalSwipe || !_canSwipe()) return;
    final delta = modeController.getVerticalSwipeDelta(details.primaryVelocity ?? 0);
    if (delta != 0) pageController.renderPage(pageController.pageIndex + delta, userInitiated: true);
  }

  bool _canSwipe() => (widget.transformController.value.getMaxScaleOnAxis() - 1.0).abs() < 0.01;
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
  bool shouldReclip(covariant MarginClipper oldClipper) => margins != oldClipper.margins;
}

class PdfHighlightPainter extends CustomPainter {
  final List<PdfTextRect> rects;
  final Color fillColor;
  final Color borderColor;

  PdfHighlightPainter({required this.rects, required this.fillColor, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || size.isEmpty) return;
    final fillPaint = Paint()..color = fillColor..style = PaintingStyle.fill;
    final borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 2.0;

    for (final rect in rects) {
      final r = Rect.fromLTRB(
        (rect.left * size.width).clamp(0.0, size.width),
        (rect.top * size.height).clamp(0.0, size.height),
        (rect.right * size.width).clamp(0.0, size.width),
        (rect.bottom * size.height).clamp(0.0, size.height),
      );
      if (r.width <= 0 || r.height <= 0) continue;
      
      final inflated = r.inflate(2.0);
      final rr = RRect.fromRectAndRadius(inflated, const Radius.circular(3));
      canvas.drawRRect(rr, fillPaint);
      canvas.drawRRect(rr, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PdfHighlightPainter oldDelegate) => oldDelegate.rects != rects;
}
