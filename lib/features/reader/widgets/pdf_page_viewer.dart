import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/src/rust/api/pdf.dart';
import '../controllers/pdf_page_controller.dart';
import '../controllers/pdf_tts_controller.dart';
import '../controllers/reader_chrome_controller.dart';
import '../controllers/reader_mode_controller.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/data/models/tts_highlight_style.dart';
import 'realistic_page_turn.dart';
import 'pdf_page_view_item.dart';
import 'package:ferrous/features/reader/widgets/reader_error_view.dart';
import 'package:ferrous/features/settings/app_themes.dart';

class PdfPageViewer extends StatefulWidget {
  final PdfPageController pageController;
  final PdfTtsController ttsController;
  final ReaderChromeController chromeController;
  final ReaderModeController modeController;
  final TransformationController transformController;
  final GlobalKey pageImageKey;
  final VoidCallback? onLockedTap;

  const PdfPageViewer({
    super.key,
    required this.pageController,
    required this.ttsController,
    required this.chromeController,
    required this.modeController,
    required this.transformController,
    required this.pageImageKey,
    this.onLockedTap,
  });

  @override
  State<PdfPageViewer> createState() => _PdfPageViewerState();
}

class _PdfPageViewerState extends State<PdfPageViewer> {
  late PageController _viewPageController;
  bool _syncing = false;

  // Active pointer tracking for multi-touch gestures & pinch zoom
  int _activePointers = 0;
  Offset? _pointerDownPos;
  bool _isMultiTouchZooming = false;

  // Double-tap and tap arbitration
  Timer? _singleTapTimer;
  Offset? _lastTapGlobalPos;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _viewPageController = PageController(
      initialPage: widget.pageController.pageIndex,
    );
    widget.pageController.addListener(_onPageControllerChanged);
    widget.transformController.addListener(_onTransformChanged);
    widget.ttsController.pdfTransformController = widget.transformController;
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
      widget.ttsController.pdfTransformController = widget.transformController;
    }
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
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

  // ---------------------------------------------------------------------------
  // Gesture Arena & Tap Handling
  // ---------------------------------------------------------------------------

  void _cancelSingleTapTimer() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers++;
    _pointerDownPos = event.position;

    // If second finger touches down, user is starting a pinch zoom
    if (_activePointers >= 2) {
      _cancelSingleTapTimer();
      if (!_isMultiTouchZooming) {
        _isMultiTouchZooming = true;
        setState(() {});
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    // If finger moves more than touch slop (18px), user is panning/scrolling
    if (_pointerDownPos != null &&
        (event.position - _pointerDownPos!).distance > kTouchSlop) {
      _cancelSingleTapTimer();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_activePointers < 2 && _isMultiTouchZooming) {
      _isMultiTouchZooming = false;
      setState(() {});
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers = 0;
    _cancelSingleTapTimer();
    if (_isMultiTouchZooming) {
      _isMultiTouchZooming = false;
      setState(() {});
    }
  }

  /// Resolves the tapped page index and page-local normalized coordinates (0.0 to 1.0)
  /// using RenderBox.globalToLocal to automatically invert zoom, pan, and scroll offsets.
  (int pageIndex, Offset normalizedOffset)? _resolvePageTapCoordinates(Offset globalPos) {
    final activePage = widget.pageController.pageIndex;
    final pageKeys = widget.pageController.pageKeys;

    // Check active page first
    if (activePage >= 0 && activePage < pageKeys.length) {
      final activeKey = pageKeys[activePage];
      final activeContext = activeKey.currentContext;
      if (activeContext != null) {
        final box = activeContext.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
          final local = box.globalToLocal(globalPos);
          final rect = Offset.zero & box.size;
          if (rect.contains(local)) {
            final xNorm = (local.dx / box.size.width).clamp(0.0, 1.0);
            final yNorm = (local.dy / box.size.height).clamp(0.0, 1.0);
            return (activePage, Offset(xNorm, yNorm));
          }
        }
      }
    }

    // In continuous mode, check other mounted pages
    for (int i = 0; i < pageKeys.length; i++) {
      if (i == activePage) continue;
      final ctx = pageKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || box.size.width <= 0 || box.size.height <= 0) continue;
      final local = box.globalToLocal(globalPos);
      final rect = Offset.zero & box.size;
      if (rect.contains(local)) {
        final xNorm = (local.dx / box.size.width).clamp(0.0, 1.0);
        final yNorm = (local.dy / box.size.height).clamp(0.0, 1.0);
        return (i, Offset(xNorm, yNorm));
      }
    }

    // Fallback: active page with clamp
    if (activePage >= 0 && activePage < pageKeys.length) {
      final activeContext = pageKeys[activePage].currentContext;
      if (activeContext != null) {
        final box = activeContext.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
          final local = box.globalToLocal(globalPos);
          final xNorm = (local.dx / box.size.width).clamp(0.0, 1.0);
          final yNorm = (local.dy / box.size.height).clamp(0.0, 1.0);
          return (activePage, Offset(xNorm, yNorm));
        }
      }
    }

    return null;
  }

  void _handleTapUp(BuildContext context, TapUpDetails details) async {
    final chromeController = widget.chromeController;
    final screenSize = MediaQuery.of(context).size;
    final now = DateTime.now();

    // Check if this tap constitutes a double-tap
    final isDoubleTap = _lastTapTime != null &&
        _lastTapGlobalPos != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
        (details.globalPosition - _lastTapGlobalPos!).distance < 48.0;

    if (isDoubleTap) {
      _cancelSingleTapTimer();
      _lastTapTime = null;
      _lastTapGlobalPos = null;

      // Handle Double-Tap to Speak
      final resolved = _resolvePageTapCoordinates(details.globalPosition);
      if (resolved != null) {
        final (pageIdx, normOffset) = resolved;
        await widget.ttsController.startTtsFromPoint(pageIdx, normOffset);
      }
      return;
    }

    _lastTapTime = now;
    _lastTapGlobalPos = details.globalPosition;

    final isCenter = chromeController.isCenterTap(details.globalPosition, screenSize);

    if (isCenter) {
      if (chromeController.isLocked) {
        widget.onLockedTap?.call();
        return;
      }

      // Fast-path rule 1: if toolbars are already visible, dismiss immediately (0ms)
      if (chromeController.showChrome) {
        _cancelSingleTapTimer();
        _handleToggleChrome();
        return;
      }

      // Fast-path rule 2: if TTS is NOT playing / controls not visible, toggle toolbars immediately (0ms)
      if (!widget.ttsController.showTtsControls && !widget.ttsController.isPlaying) {
        _cancelSingleTapTimer();
        _handleToggleChrome();
        return;
      }

      // Check if tap lands over a sentence
      final resolved = _resolvePageTapCoordinates(details.globalPosition);
      PdfSentence? hitSentence;
      if (resolved != null) {
        final (pageIdx, normOffset) = resolved;
        hitSentence = await widget.ttsController.hitTestSentence(pageIdx, normOffset);
      }

      if (hitSentence == null) {
        // Fast-path rule: tap on whitespace or margin with no sentence -> toggle toolbars instantly (0ms)
        _cancelSingleTapTimer();
        _handleToggleChrome();
      } else {
        // Text-zone fallback: tap landed over text. Wait 250ms for potential double tap.
        // If no second tap arrives, toggle chrome on!
        _cancelSingleTapTimer();
        _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          _handleToggleChrome();
        });
      }
      return;
    }

    if (chromeController.isLocked) {
      widget.onLockedTap?.call();
      return;
    }

    // Outer margin taps for page turning in paged mode
    if (widget.modeController.isPagedMode) {
      final tapX = details.globalPosition.dx;
      if (tapX < screenSize.width * 0.22) {
        // Previous page
        if (widget.pageController.pageIndex > 0) {
          widget.pageController.previousPage();
        }
      } else if (tapX > screenSize.width * 0.78) {
        // Next page
        if (widget.pageController.pageIndex < widget.pageController.pageCount - 1) {
          widget.pageController.nextPage();
        }
      }
    }
  }

  void _handleToggleChrome() {
    widget.chromeController.toggleChrome();
    if (!widget.chromeController.showChrome) {
      widget.ttsController.setTtsControlsVisible(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pageController = widget.pageController;

    Widget body;
    if (pageController.error != null) {
      body = _buildErrorState(pageController.error!);
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          widget.pageController.updateViewportSize(
            Size(constraints.maxWidth, constraints.maxHeight),
          );

          return _buildGallery();
        },
      );
    }

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) => _handleTapUp(context, details),
        child: body,
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
    final themeRepo = context.watch<ReaderThemeRepository>();
    final useRealisticCurl =
        !widget.modeController.useVerticalSwipe &&
        themeRepo.config.pageFlip &&
        _canSwipe();

    if (useRealisticCurl) {
      return RealisticPageTurn(
        key: ValueKey('pdf-realistic-curl-${widget.pageController.book.id}'),
        pageCount: widget.pageController.pageCount,
        currentPage: widget.pageController.pageIndex,
        textureId: themeRepo.config.paperTexture,
        showSpine: themeRepo.config.showBookSpine,
        canSwipe: _canSwipe,
        onPageChanged: _onPageViewChanged,
        onToggleChrome: _handleToggleChrome,
        onTapUp: (details) => _handleTapUp(context, details),
        pageBuilder: (context, index) {
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
        physics: _isMultiTouchZooming
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        key: PageStorageKey(
            'pdf-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: (context, index) {
          return Center(
            child: _buildPageLayer(context, index),
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
        physics: _isMultiTouchZooming
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        key: PageStorageKey(
            'pdf-${widget.pageController.book.id}-${widget.pageController.readingMode.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.pageController.pageCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final ar = widget.pageController.getPageAspectRatio(index) ?? 0.70;
          return Center(
            child: AspectRatio(
              aspectRatio: ar > 0 ? ar : 0.70,
              child: _buildPageLayer(context, index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageLayer(BuildContext context, int index) {
    return PdfPageViewItem(
      pageIndex: index,
      pageController: widget.pageController,
      ttsController: widget.ttsController,
      isHorizontal: widget.modeController.isHorizontal,
      pageImageKey: widget.pageImageKey,
    );
  }

  Widget _buildErrorState(String error) {
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;
    return ReaderErrorView(
      formatTitle: 'PDF',
      error: error,
      isEInk: isEInk,
    );
  }
}

/// Zero-allocation, high-contrast vector highlighter for PDF.
/// Fully supports both standard and E-Ink paper styles across softPill, underline, and classicClean.
class PdfHighlightPainter extends CustomPainter {
  final List<PdfTextRect> rects;
  final TtsHighlightStyle style;
  final Color primaryColor;
  final bool isEInk;
  final bool isDarkMode;

  PdfHighlightPainter({
    required this.rects,
    required this.style,
    required this.primaryColor,
    this.isEInk = false,
    this.isDarkMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || size.isEmpty) return;

    // 1. Handle Underline style separately (stroke bottom line with no fill)
    if (style == TtsHighlightStyle.underline) {
      final linePaint = Paint()
        ..color = isEInk
            ? const Color(0xFF000000)
            : (isDarkMode ? primaryColor.withValues(alpha: 0.85) : primaryColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      for (final rect in rects) {
        final r = Rect.fromLTRB(
          (rect.left * size.width).clamp(0.0, size.width),
          (rect.top * size.height).clamp(0.0, size.height),
          (rect.right * size.width).clamp(0.0, size.width),
          (rect.bottom * size.height).clamp(0.0, size.height),
        );
        if (r.width <= 0 || r.height <= 0) continue;
        canvas.drawLine(
          Offset(r.left, r.bottom + 1.5),
          Offset(r.right, r.bottom + 1.5),
          linePaint,
        );
      }
      return;
    }

    // 2. Select compositing blend mode and alpha based on display type
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;

    if (isEInk) {
      // E-Ink: Darken mode with 15% opacity dark gray tint (never hides text glyphs)
      fillPaint
        ..blendMode = BlendMode.darken
        ..color = const Color(0xFF202020).withValues(alpha: 0.15);
    } else if (isDarkMode) {
      // Dark Mode: Screen mode with luminous primary accent (lifts text against dark background)
      fillPaint
        ..blendMode = BlendMode.screen
        ..color = primaryColor.withValues(alpha: 0.35);
    } else {
      // Normal LCD/OLED: Multiply mode blends yellow/primary tint directly into paper pixels
      fillPaint
        ..blendMode = BlendMode.multiply
        ..color = primaryColor.withValues(alpha: 0.28);
    }

    // 3. Construct a unified silhouette path using PathOperation.union
    // to prevent double-multiplying overlapping line rects and eliminate internal border seams
    Path? combinedPath;
    for (final rect in rects) {
      final r = Rect.fromLTRB(
        (rect.left * size.width).clamp(0.0, size.width),
        (rect.top * size.height).clamp(0.0, size.height),
        (rect.right * size.width).clamp(0.0, size.width),
        (rect.bottom * size.height).clamp(0.0, size.height),
      );
      if (r.width <= 0 || r.height <= 0) continue;

      final inflated = r.inflate(2.0);
      final rr = RRect.fromRectAndRadius(
        inflated,
        Radius.circular(style == TtsHighlightStyle.softPill ? 4.0 : 2.0),
      );

      final linePath = Path()..addRRect(rr);
      if (combinedPath == null) {
        combinedPath = linePath;
      } else {
        combinedPath = Path.combine(PathOperation.union, combinedPath, linePath);
      }
    }

    if (combinedPath == null) return;

    // 4. Fill the union silhouette
    canvas.drawPath(combinedPath, fillPaint);

    // 5. If classicClean, stroke ONLY the exterior perimeter of the union silhouette
    if (style == TtsHighlightStyle.classicClean) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isEInk ? 1.5 : 1.0
        ..color = isEInk
            ? const Color(0xFF000000)
            : (isDarkMode
                ? primaryColor.withValues(alpha: 0.70)
                : primaryColor.withValues(alpha: 0.55));
      canvas.drawPath(combinedPath, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PdfHighlightPainter oldDelegate) =>
      oldDelegate.rects != rects ||
      oldDelegate.style != style ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.isEInk != isEInk ||
      oldDelegate.isDarkMode != isDarkMode;
}
