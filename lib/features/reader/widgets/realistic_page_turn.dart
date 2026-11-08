import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Callback when a page turn begins or finishes.
typedef PageTurnCallback = void Function(int newIndex);

/// An authentic, high-fidelity realistic book page turn animation widget.
///
/// Features:
/// - Smooth, silky, tactile page turning inspired by physical books.
/// - Uninterrupted reading: no opaque slabs, leftover rectangular blocks, or covered text.
/// - Physically modelled cylindrical curvature shading, soft specular apex highlight,
///   and ambient occlusion contact shadows.
/// - Full interactive swipe gestures with fluid drag tracking, inertia flings,
///   and organic cubic easing.
/// - Outer margin tap-to-turn (left/right 18%) and center tap for reader chrome.
/// - Zero-allocation custom painters and efficient `RepaintBoundary` caching.
class RealisticPageTurn extends StatefulWidget {
  final int pageCount;
  final int currentPage;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onToggleChrome;
  final void Function(TapUpDetails)? onTapUp;
  final bool enabled;
  final String textureId;
  final bool showSpine;

  const RealisticPageTurn({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.pageBuilder,
    required this.onPageChanged,
    this.onToggleChrome,
    this.onTapUp,
    this.enabled = true,
    this.textureId = 'natural',
    this.showSpine = true,
  });

  @override
  State<RealisticPageTurn> createState() => _RealisticPageTurnState();
}

/// Backwards compatibility alias
typedef AppleBooksPageCurl = RealisticPageTurn;

class _RealisticPageTurnState extends State<RealisticPageTurn>
    with SingleTickerProviderStateMixin {
  late int _activePage;
  late AnimationController _curlController;
  late Animation<double> _curlAnimation;
  late final ValueNotifier<double> _progressNotifier;

  // Page widget cache and global keys for instant zero-rebuild GPU compositing
  final Map<int, Widget> _pageCache = {};
  final Map<int, GlobalKey> _pageKeys = {};

  // Turn direction: 1 for forward (next page), -1 for backward (previous page)
  int _turnDirection = 1;
  double _dragProgress = 0.0;
  bool _isDragging = false;
  bool _isAnimating = false;
  bool _directionDetermined = false;

  GlobalKey _getPageKey(int index) {
    return _pageKeys.putIfAbsent(
      index,
      () => GlobalKey(debugLabel: 'realistic-page-$index'),
    );
  }

  Widget _getPage(BuildContext context, int index) {
    return _pageCache.putIfAbsent(index, () {
      return RepaintBoundary(
        key: _getPageKey(index),
        child: widget.pageBuilder(context, index),
      );
    });
  }

  void _pruneCache() {
    // Keep active page and adjacent pages (+/- 2) in cache; evict others to strictly bound memory
    _pageCache.removeWhere((index, _) => (index - _activePage).abs() > 2);
    _pageKeys.removeWhere((index, _) => (index - _activePage).abs() > 2);
  }

  @override
  void initState() {
    super.initState();
    _activePage = widget.currentPage;
    _progressNotifier = ValueNotifier<double>(0.0);
    // Premium, relaxed animation duration: ~480ms for silky, smooth motion
    _curlController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _curlAnimation = CurvedAnimation(
      parent: _curlController,
      curve: Curves.easeOutCubic,
    )..addListener(() {
        _progressNotifier.value = _curlAnimation.value;
      })..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(RealisticPageTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textureId != oldWidget.textureId ||
        widget.showSpine != oldWidget.showSpine ||
        widget.pageCount != oldWidget.pageCount ||
        widget.enabled != oldWidget.enabled ||
        widget.pageBuilder != oldWidget.pageBuilder) {
      _pageCache.clear();
      _pageKeys.clear();
    }
    if (widget.currentPage != oldWidget.currentPage) {
      if (_isAnimating || _isDragging) {
        _curlController.reset();
        _isAnimating = false;
        _isDragging = false;
        _dragProgress = 0.0;
        _progressNotifier.value = 0.0;
        _directionDetermined = false;
      }
      _activePage = widget.currentPage.clamp(0, widget.pageCount - 1);
      _pruneCache();
    }
  }

  @override
  void dispose() {
    _curlController.dispose();
    _progressNotifier.dispose();
    _pageCache.clear();
    _pageKeys.clear();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final newIndex = _turnDirection == 1 ? _activePage + 1 : _activePage - 1;
      _activePage = newIndex.clamp(0, widget.pageCount - 1);
      _dragProgress = 0.0;
      _progressNotifier.value = 0.0;
      _directionDetermined = false;
      _isAnimating = false;
      _isDragging = false;
      _curlController.reset();
      widget.onPageChanged(_activePage);
      _pruneCache();
      if (mounted) setState(() {});
    } else if (status == AnimationStatus.dismissed) {
      _dragProgress = 0.0;
      _progressNotifier.value = 0.0;
      _directionDetermined = false;
      _isAnimating = false;
      _isDragging = false;
      _curlController.reset();
      if (mounted) setState(() {});
    }
  }

  bool _canTurnForward() => _activePage < widget.pageCount - 1;
  bool _canTurnBackward() => _activePage > 0;

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) return;
    _isDragging = true;
    _dragProgress = 0.0;
    _progressNotifier.value = 0.0;
    _directionDetermined = false;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!widget.enabled || !_isDragging || _isAnimating || screenWidth <= 0) return;

    final delta = details.primaryDelta ?? 0.0;

    if (!_directionDetermined) {
      if (delta < -1.5) {
        if (!_canTurnForward()) return;
        _turnDirection = 1;
        _directionDetermined = true;
        setState(() {});
      } else if (delta > 1.5) {
        if (!_canTurnBackward()) return;
        _turnDirection = -1;
        _directionDetermined = true;
        setState(() {});
      } else {
        return;
      }
    }

    final rawChange = _turnDirection == 1
        ? -delta / screenWidth
        : delta / screenWidth;

    final newProgress = _dragProgress + rawChange;

    if (newProgress <= 0.0) {
      // Reached zero: allow reversing direction naturally
      _dragProgress = 0.0;
      _progressNotifier.value = 0.0;
      _directionDetermined = false;
      setState(() {});
    } else {
      _dragProgress = newProgress.clamp(0.0, 1.0);
      _progressNotifier.value = _dragProgress;
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details, double screenWidth) {
    if (!widget.enabled || !_isDragging || _isAnimating) return;
    _isDragging = false;

    if (!_directionDetermined || _dragProgress <= 0.01) {
      _dragProgress = 0.0;
      _progressNotifier.value = 0.0;
      _directionDetermined = false;
      setState(() {});
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;
    final bool isFling = _turnDirection == 1
        ? velocity < -200.0
        : velocity > 200.0;
    final bool isCancelFling = _turnDirection == 1
        ? velocity > 200.0
        : velocity < -200.0;

    final shouldComplete = !isCancelFling && (isFling || _dragProgress >= 0.32);

    _isAnimating = true;

    // Smooth, relaxed duration scaling: ~380ms to ~520ms so it never snaps or rushes
    final remaining = shouldComplete ? (1.0 - _dragProgress) : _dragProgress;
    final durationMs = (380 + (remaining * 180)).round().clamp(360, 520);
    _curlController.duration = Duration(milliseconds: durationMs);

    if (shouldComplete) {
      _curlController.forward(from: _dragProgress);
    } else {
      _curlController.reverse(from: _dragProgress);
    }
  }

  void _turnPageAnimated(int direction) {
    if (_isAnimating || _isDragging) return;
    if (direction == 1 && !_canTurnForward()) return;
    if (direction == -1 && !_canTurnBackward()) return;

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion || !widget.enabled) {
      final newIndex = direction == 1 ? _activePage + 1 : _activePage - 1;
      _activePage = newIndex.clamp(0, widget.pageCount - 1);
      widget.onPageChanged(_activePage);
      _pruneCache();
      if (mounted) setState(() {});
      return;
    }

    _turnDirection = direction;
    _dragProgress = 0.0;
    _progressNotifier.value = 0.0;
    _directionDetermined = true;
    _isAnimating = true;
    _curlController.duration = const Duration(milliseconds: 480);
    setState(() {});
    _curlController.forward(from: 0.0);
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    widget.onTapUp?.call(details);

    final tapX = details.globalPosition.dx;
    final width = size.width;

    // Outer margins: 18% left and right turn pages gracefully
    const marginRatio = 0.18;
    if (tapX > width * (1.0 - marginRatio)) {
      _turnPageAnimated(1);
    } else if (tapX < width * marginRatio) {
      _turnPageAnimated(-1);
    } else {
      // Center 64%: toggle reader chrome
      widget.onToggleChrome?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageCount <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final size = Size(width, height);

        final isTurning = _isAnimating || (_isDragging && _directionDetermined);

        Widget content;

        if (!isTurning || !widget.enabled) {
          // Static page view using cached page
          content = _getPage(context, _activePage);
        } else {
          // Active realistic page turn animation
          content = _buildPageCurlLayers(context, size);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTapUp(details, size),
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: (details) =>
              _handleHorizontalDragUpdate(details, width),
          onHorizontalDragEnd: (details) =>
              _handleHorizontalDragEnd(details, width),
          child: content,
        );
      },
    );
  }

  Widget _buildPageCurlLayers(BuildContext context, Size size) {
    final width = size.width;
    final height = size.height;

    final isForward = _turnDirection == 1;

    // Clean boundary split between pages:
    // Left page spans [0, curlX]
    // Right page spans [curlX, width]
    final int leftPageIndex = isForward ? _activePage : _activePage - 1;
    final int rightPageIndex = isForward ? _activePage + 1 : _activePage;

    // Retrieve or instantiate the two page subtrees ONCE outside the per-frame animation/drag builder
    final Widget leftPage = _getPage(context, leftPageIndex);
    final Widget rightPage = _getPage(context, rightPageIndex);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<double>(
      valueListenable: _progressNotifier,
      builder: (context, progress, _) {
        final double curlX = isForward
            ? (width * (1.0 - progress)).clamp(0.0, width)
            : (width * progress).clamp(0.0, width);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Right page (revealed on the right of curl fold)
            Positioned.fill(
              child: ClipRect(
                clipper: _CurlRectClipper(
                  Rect.fromLTRB(curlX, 0, width, height),
                ),
                child: rightPage,
              ),
            ),

            // 2. Realistic drop shadow cast onto the right page by the lifted sheet
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RealisticDropShadowPainter(
                    curlX: curlX,
                    progress: progress,
                  ),
                ),
              ),
            ),

            // 3. Left page (intact page on the left of curl fold)
            Positioned.fill(
              child: ClipRect(
                clipper: _CurlRectClipper(
                  Rect.fromLTRB(0, 0, curlX, height),
                ),
                child: leftPage,
              ),
            ),

            // 4. Physical cylindrical curvature shading & specular crest highlight on the curl edge
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RealisticCurlLightingPainter(
                    curlX: curlX,
                    progress: progress,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Zero-allocation custom clipper for page reveal regions.
class _CurlRectClipper extends CustomClipper<Rect> {
  final Rect clipRect;
  const _CurlRectClipper(this.clipRect);

  @override
  Rect getClip(Size size) => clipRect;

  @override
  bool shouldReclip(covariant _CurlRectClipper oldClipper) =>
      oldClipper.clipRect != clipRect;
}

/// Zero-allocation painter for the soft drop shadow cast onto the revealed page.
class _RealisticDropShadowPainter extends CustomPainter {
  final double curlX;
  final double progress;

  static final Paint _shadowPaint = Paint()..style = PaintingStyle.fill;

  _RealisticDropShadowPainter({
    required this.curlX,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (curlX <= 0 || curlX >= size.width) return;

    final sinProg = math.sin(progress * math.pi);
    // Dynamic shadow spread that expands naturally when the page is lifted highest
    final shadowSpread = (22.0 + 38.0 * sinProg).clamp(16.0, 56.0);
    final availableWidth = size.width - curlX;
    final actualSpread = math.min(shadowSpread, availableWidth);
    if (actualSpread <= 0.5) return;

    // Contact occlusion alpha tapering gently to zero
    final shadowAlpha = (0.24 * sinProg + 0.06).clamp(0.04, 0.30);

    final rect = Rect.fromLTWH(curlX, 0, actualSpread, size.height);
    _shadowPaint.shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.black.withValues(alpha: shadowAlpha),
        Colors.black.withValues(alpha: shadowAlpha * 0.55),
        Colors.black.withValues(alpha: shadowAlpha * 0.18),
        Colors.transparent,
      ],
      stops: const [0.0, 0.25, 0.65, 1.0],
    ).createShader(rect);

    canvas.drawRect(rect, _shadowPaint);
  }

  @override
  bool shouldRepaint(covariant _RealisticDropShadowPainter oldDelegate) =>
      oldDelegate.curlX != curlX || oldDelegate.progress != progress;
}

/// Zero-allocation painter for curvature shading, apex specular highlight, and the physical fold edge.
class _RealisticCurlLightingPainter extends CustomPainter {
  final double curlX;
  final double progress;
  final bool isDark;

  static final Paint _lightingPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _edgePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;

  _RealisticCurlLightingPainter({
    required this.curlX,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (curlX <= 0 || curlX >= size.width) return;

    final sinProg = math.sin(progress * math.pi);

    // 1. Curvature shading on the left page as it rolls into the curl
    final curveWidth = (20.0 + 26.0 * sinProg).clamp(16.0, 44.0);
    final actualCurveWidth = math.min(curveWidth, curlX);
    if (actualCurveWidth > 0.5) {
      final curveRect = Rect.fromLTWH(curlX - actualCurveWidth, 0, actualCurveWidth, size.height);
      final curveShadowAlpha = (0.16 * sinProg + 0.04).clamp(0.02, 0.18);

      _lightingPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: curveShadowAlpha * 0.35),
          Colors.black.withValues(alpha: curveShadowAlpha),
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(curveRect);

      canvas.drawRect(curveRect, _lightingPaint);

      // 2. Apex specular highlight along the roll crest
      final crestWidth = math.min(18.0, actualCurveWidth * 0.6);
      final crestRect = Rect.fromLTWH(curlX - crestWidth, 0, crestWidth, size.height);
      final highlightAlpha = isDark
          ? (0.06 * sinProg + 0.02)
          : (0.22 * sinProg + 0.06);

      _lightingPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: highlightAlpha),
          Colors.white.withValues(alpha: highlightAlpha * 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.85, 1.0],
      ).createShader(crestRect);

      canvas.drawRect(crestRect, _lightingPaint);
    }

    // 3. Delicate hairline edge defining the physical paper boundary
    final edgeAlpha = (isDark ? 0.08 : 0.12) * sinProg + 0.03;
    _edgePaint.color = (isDark ? Colors.white : Colors.black).withValues(alpha: edgeAlpha);
    canvas.drawLine(Offset(curlX, 0), Offset(curlX, size.height), _edgePaint);
  }

  @override
  bool shouldRepaint(covariant _RealisticCurlLightingPainter oldDelegate) =>
      oldDelegate.curlX != curlX ||
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark;
}
