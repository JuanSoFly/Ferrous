import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'book_background_texture.dart';

/// Callback when a page turn begins or finishes.
typedef PageTurnCallback = void Function(int newIndex);

/// An authentic Apple Books style interactive 3D page curl animation widget.
///
/// Supports interactive swiping gestures where the page curls realistically
/// under the user's finger with 3D perspective, dynamic highlights,
/// fold crease shadows, underpage drop shadow, and a physical paper back-face.
/// Also supports tap-to-turn on outer margins and center tap for chrome UI.
class AppleBooksPageCurl extends StatefulWidget {
  final int pageCount;
  final int currentPage;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onToggleChrome;
  final void Function(TapUpDetails)? onTapUp;
  final bool enabled;
  final String textureId;
  final bool showSpine;

  const AppleBooksPageCurl({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.pageBuilder,
    required this.onPageChanged,
    this.onToggleChrome,
    this.onTapUp,
    this.enabled = true,
    this.textureId = BookTextures.natural,
    this.showSpine = true,
  });

  @override
  State<AppleBooksPageCurl> createState() => _AppleBooksPageCurlState();
}

class _AppleBooksPageCurlState extends State<AppleBooksPageCurl>
    with SingleTickerProviderStateMixin {
  late int _activePage;
  late AnimationController _curlController;
  late Animation<double> _curlAnimation;

  // Turn direction: 1 for forward (next page), -1 for backward (previous page)
  int _turnDirection = 1;
  double _dragProgress = 0.0;
  bool _isDragging = false;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _activePage = widget.currentPage;
    _curlController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _curlAnimation = CurvedAnimation(
      parent: _curlController,
      curve: Curves.easeOutCubic,
    )..addListener(() {
        setState(() {});
      })..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(AppleBooksPageCurl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPage != oldWidget.currentPage && !_isDragging && !_isAnimating) {
      _activePage = widget.currentPage;
    }
  }

  @override
  void dispose() {
    _curlController.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final newIndex = _turnDirection == 1 ? _activePage + 1 : _activePage - 1;
      _activePage = newIndex.clamp(0, widget.pageCount - 1);
      _dragProgress = 0.0;
      _isAnimating = false;
      _isDragging = false;
      _curlController.reset();
      widget.onPageChanged(_activePage);
      if (mounted) setState(() {});
    } else if (status == AnimationStatus.dismissed) {
      _dragProgress = 0.0;
      _isAnimating = false;
      _isDragging = false;
      _curlController.reset();
      if (mounted) setState(() {});
    }
  }

  double get _currentProgress {
    if (_isAnimating) {
      return _curlAnimation.value;
    }
    return _dragProgress;
  }

  bool _canTurnForward() => _activePage < widget.pageCount - 1;
  bool _canTurnBackward() => _activePage > 0;

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) return;
    _isDragging = true;
    _dragProgress = 0.0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (!widget.enabled || !_isDragging || _isAnimating || screenWidth <= 0) return;

    final delta = details.primaryDelta ?? 0.0;

    if (_dragProgress == 0.0) {
      // Determine direction on first significant movement
      if (delta < -1.0) {
        if (!_canTurnForward()) return;
        _turnDirection = 1;
      } else if (delta > 1.0) {
        if (!_canTurnBackward()) return;
        _turnDirection = -1;
      } else {
        return;
      }
    }

    final rawChange = _turnDirection == 1
        ? -delta / screenWidth
        : delta / screenWidth;

    setState(() {
      _dragProgress = (_dragProgress + rawChange).clamp(0.0, 1.0);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details, double screenWidth) {
    if (!widget.enabled || !_isDragging || _isAnimating) return;
    _isDragging = false;

    final velocity = details.primaryVelocity ?? 0.0;
    final bool isFling = _turnDirection == 1
        ? velocity < -250.0
        : velocity > 250.0;
    final bool isCancelFling = _turnDirection == 1
        ? velocity > 250.0
        : velocity < -250.0;

    final shouldComplete = !isCancelFling && (isFling || _dragProgress >= 0.38);

    _isAnimating = true;

    final remaining = shouldComplete ? (1.0 - _dragProgress) : _dragProgress;
    final durationMs = (240 + (remaining * 160)).round().clamp(180, 420);
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
      if (mounted) setState(() {});
      return;
    }

    _turnDirection = direction;
    _dragProgress = 0.0;
    _isAnimating = true;
    _curlController.duration = const Duration(milliseconds: 340);
    _curlController.forward(from: 0.0);
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    // Forward tap details to optional listener (e.g. TTS tap detection)
    widget.onTapUp?.call(details);

    final tapX = details.globalPosition.dx;
    final width = size.width;

    // Outer margins: 18% left and right turn pages like in Apple Books
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

        final progress = _currentProgress;
        final isTurning = progress > 0.0;

        Widget content;

        if (!isTurning || !widget.enabled) {
          // Static page view
          content = KeyedSubtree(
            key: ValueKey('page-$_activePage'),
            child: widget.pageBuilder(context, _activePage),
          );
        } else {
          // Active 3D page curl animation
          content = _buildPageCurlLayers(context, size, progress);
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

  Widget _buildPageCurlLayers(BuildContext context, Size size, double progress) {
    final width = size.width;
    final height = size.height;

    final isForward = _turnDirection == 1;
    final underPageIndex = isForward ? _activePage + 1 : _activePage;
    final turningPageIndex = isForward ? _activePage : _activePage - 1;

    // Curl fold line position across the screen
    final curlX = isForward
        ? width * (1.0 - progress)
        : width * progress;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Under-page (revealed beneath the curling leaf)
        Positioned.fill(
          child: ClipRect(
            clipper: _CurlRectClipper(
              isForward
                  ? Rect.fromLTRB(curlX.clamp(0.0, width), 0, width, height)
                  : Rect.fromLTRB(0, 0, curlX.clamp(0.0, width), height),
            ),
            child: RepaintBoundary(
              key: ValueKey('under-page-$underPageIndex'),
              child: widget.pageBuilder(context, underPageIndex),
            ),
          ),
        ),

        // 2. Drop-shadow cast by the lifted curling page onto the under-page
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _UnderpageShadowPainter(
                curlX: curlX,
                isForward: isForward,
                progress: progress,
              ),
            ),
          ),
        ),

        // 3. Flat base of the turning page (portion before the curl fold)
        Positioned.fill(
          child: ClipRect(
            clipper: _CurlRectClipper(
              isForward
                  ? Rect.fromLTRB(0, 0, curlX.clamp(0.0, width), height)
                  : Rect.fromLTRB(curlX.clamp(0.0, width), 0, width, height),
            ),
            child: RepaintBoundary(
              key: ValueKey('turning-page-$turningPageIndex'),
              child: widget.pageBuilder(context, turningPageIndex),
            ),
          ),
        ),

        // 4. Curled paper flap (peeling and curling in 3D perspective)
        Positioned.fill(
          child: _buildCurledFlap(
            context,
            size,
            curlX,
            progress,
            isForward,
            turningPageIndex,
          ),
        ),

        // 5. Cylindrical lighting, apex specular highlight and fold crease shadow
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CurlCylinderLightingPainter(
                curlX: curlX,
                isForward: isForward,
                progress: progress,
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurledFlap(
    BuildContext context,
    Size size,
    double curlX,
    double progress,
    bool isForward,
    int pageIndex,
  ) {
    final width = size.width;
    final height = size.height;

    // Curl flap width naturally expands and contracts during bend
    final flapWidth = math.min(
      (isForward ? (width - curlX) : curlX) * 0.72,
      width * 0.48,
    );

    if (flapWidth <= 1.0) return const SizedBox.shrink();

    final flapLeft = isForward ? curlX - flapWidth : curlX;

    // 3D rotation angle along the curl axis
    final curlAngle = (progress * math.pi * 0.85).clamp(0.0, math.pi * 0.85);

    // Flap container with 3D transform and back-face simulation
    return Positioned(
      left: flapLeft.clamp(0.0, width),
      top: 0,
      width: flapWidth.clamp(0.0, width),
      height: height,
      child: Transform(
        alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(isForward ? -curlAngle : curlAngle),
        child: Container(
          decoration: BoxDecoration(
            color: BookTextures.getById(widget.textureId).baseColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18 * (1.0 - progress * 0.5)),
                blurRadius: 10,
                spreadRadius: 1,
                offset: Offset(isForward ? -3 : 3, 0),
              ),
            ],
          ),
          child: RealBookBackground(
            textureId: widget.textureId,
            showSpine: false,
            child: Container(
              color: Colors.black.withValues(alpha: 0.04),
            ),
          ),
        ),
      ),
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

/// Zero-allocation painter for the drop shadow cast by the curl onto the under-page.
class _UnderpageShadowPainter extends CustomPainter {
  final double curlX;
  final bool isForward;
  final double progress;

  static final Paint _shadowPaint = Paint()..style = PaintingStyle.fill;

  _UnderpageShadowPainter({
    required this.curlX,
    required this.isForward,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (curlX <= 0 || curlX >= size.width) return;

    final shadowSpread = math.min(
      88.0,
      (isForward ? (size.width - curlX) : curlX) * 0.75,
    );

    final shadowAlpha = (0.32 * (1.0 - progress * 0.4)).clamp(0.04, 0.35);

    if (isForward) {
      final rect = Rect.fromLTWH(curlX, 0, shadowSpread, size.height);
      _shadowPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: shadowAlpha),
          Colors.black.withValues(alpha: shadowAlpha * 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
      canvas.drawRect(rect, _shadowPaint);
    } else {
      final rect = Rect.fromLTWH(curlX - shadowSpread, 0, shadowSpread, size.height);
      _shadowPaint.shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          Colors.black.withValues(alpha: shadowAlpha),
          Colors.black.withValues(alpha: shadowAlpha * 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
      canvas.drawRect(rect, _shadowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UnderpageShadowPainter oldDelegate) =>
      oldDelegate.curlX != curlX ||
      oldDelegate.isForward != isForward ||
      oldDelegate.progress != progress;
}

/// Zero-allocation painter for curl cylinder lighting, highlight crest and fold creases.
class _CurlCylinderLightingPainter extends CustomPainter {
  final double curlX;
  final bool isForward;
  final double progress;
  final bool isDark;

  static final Paint _lightingPaint = Paint()..style = PaintingStyle.fill;

  _CurlCylinderLightingPainter({
    required this.curlX,
    required this.isForward,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (curlX <= 0 || curlX >= size.width) return;

    // 1. Fold crease shadow (on the flat side of the turn)
    const creaseWidth = 26.0;
    if (isForward) {
      final creaseRect = Rect.fromLTWH(curlX - creaseWidth, 0, creaseWidth, size.height);
      _lightingPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
        ],
      ).createShader(creaseRect);
      canvas.drawRect(creaseRect, _lightingPaint);
    } else {
      final creaseRect = Rect.fromLTWH(curlX, 0, creaseWidth, size.height);
      _lightingPaint.shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
        ],
      ).createShader(creaseRect);
      canvas.drawRect(creaseRect, _lightingPaint);
    }

    // 2. Curled cylinder specular highlight (apex crest catching light)
    final crestWidth = math.min(38.0, size.width * 0.10);
    final highlightRect = isForward
        ? Rect.fromLTWH(curlX - crestWidth * 0.75, 0, crestWidth, size.height)
        : Rect.fromLTWH(curlX - crestWidth * 0.25, 0, crestWidth, size.height);

    final highlightAlpha = isDark ? 0.08 : 0.28;
    _lightingPaint.shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: highlightAlpha),
        Colors.black.withValues(alpha: 0.12),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 0.75, 1.0],
    ).createShader(highlightRect);
    canvas.drawRect(highlightRect, _lightingPaint);
  }

  @override
  bool shouldRepaint(covariant _CurlCylinderLightingPainter oldDelegate) =>
      oldDelegate.curlX != curlX ||
      oldDelegate.isForward != isForward ||
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark;
}
