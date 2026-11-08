import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/features/settings/app_themes.dart';

/// Renders authentic physical book page background textures, lighting,
/// book spine gutter shadow, and stacked page edge depth.
class RealBookBackground extends StatelessWidget {
  final Widget child;
  final String textureId;
  final bool showSpine;
  final bool isLeftPage;

  const RealBookBackground({
    super.key,
    required this.child,
    this.textureId = BookTextures.natural,
    this.showSpine = true,
    this.isLeftPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;
    final textureInfo = BookTextures.getById(textureId);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}

    // If 'none', use theme scaffold background color
    final effectiveColor = textureId == BookTextures.none
        ? theme.scaffoldBackgroundColor
        : textureInfo.baseColor;

    final isEInk = currentTheme == AppTheme.eInk || effectiveColor.toARGB32() == 0xFFEAE6DF;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BookPaperPainter(
              textureId: textureId,
              baseColor: effectiveColor,
              showSpine: showSpine,
              isLeftPage: isLeftPage,
              isDarkTheme: isDarkTheme,
              isEInk: isEInk,
            ),
          ),
        ),
        RepaintBoundary(
          child: child,
        ),
      ],
    );
  }
}

/// Zero-allocation custom painter that renders book textures, fiber grain,
/// book spine shadows, and stacked page edge leaves.
class _BookPaperPainter extends CustomPainter {
  final String textureId;
  final Color baseColor;
  final bool showSpine;
  final bool isLeftPage;
  final bool isDarkTheme;
  final bool isEInk;

  // Pre-allocated static paints to enforce 60fps/120fps zero-allocation discipline
  static final Paint _basePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _spinePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _edgeLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _laidLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final Paint _speckPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _vignettePaint = Paint()..style = PaintingStyle.fill;

  // Pre-generated deterministic fiber particles (normalized 0.0 to 1.0)
  static final List<_FiberParticle> _fiberParticles = _generateFibers(140);

  _BookPaperPainter({
    required this.textureId,
    required this.baseColor,
    required this.showSpine,
    required this.isLeftPage,
    required this.isDarkTheme,
    this.isEInk = false,
  });

  static List<_FiberParticle> _generateFibers(int count) {
    final list = <_FiberParticle>[];
    // Deterministic LCG pseudo-random generator
    int seed = 42817;
    double nextDouble() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    for (int i = 0; i < count; i++) {
      list.add(_FiberParticle(
        nx: nextDouble(),
        ny: nextDouble(),
        length: 1.5 + nextDouble() * 3.5,
        angle: nextDouble() * math.pi,
        opacity: 0.025 + nextDouble() * 0.055,
      ));
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Base paper fill
    _basePaint.color = baseColor;
    _basePaint.shader = null;
    canvas.drawRect(rect, _basePaint);

    if (textureId != BookTextures.none) {
      _paintPaperTexture(canvas, size);
    }

    // 2. Book physical features
    if (showSpine) {
      _paintSpineGutter(canvas, size);
      _paintStackedPageEdges(canvas, size);
    }

    // 3. Subtle page perimeter vignette
    if (textureId != BookTextures.none && !isEInk) {
      _paintMarginVignette(canvas, size);
    }
  }

  void _paintPaperTexture(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    switch (textureId) {
      case BookTextures.linen:
        // Fine laid paper: subtle horizontal laid wire ribs and vertical chain lines
        _laidLinePaint.color = isDarkTheme
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xFF6B5842).withValues(alpha: 0.035);

        // Horizontal laid lines every 5.5px
        const double laidSpacing = 5.5;
        for (double y = 0; y < height; y += laidSpacing) {
          canvas.drawLine(Offset(0, y), Offset(width, y), _laidLinePaint);
        }

        // Vertical chain lines every 38px
        _laidLinePaint.color = isDarkTheme
            ? Colors.white.withValues(alpha: 0.015)
            : const Color(0xFF6B5842).withValues(alpha: 0.025);
        const double chainSpacing = 38.0;
        for (double x = chainSpacing; x < width; x += chainSpacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, height), _laidLinePaint);
        }
        break;

      case BookTextures.parchment:
        // Soft antique mottling and organic fibers
        _vignettePaint.shader = RadialGradient(
          center: const Alignment(0.1, -0.2),
          radius: 0.95,
          colors: [
            Colors.transparent,
            const Color(0xFF8B6B38).withValues(alpha: 0.04),
            const Color(0xFF704C1C).withValues(alpha: 0.08),
          ],
          stops: const [0.5, 0.82, 1.0],
        ).createShader(Offset.zero & size);
        canvas.drawRect(Offset.zero & size, _vignettePaint);
        _paintFibers(canvas, size, const Color(0xFF5C4020));
        break;

      case BookTextures.kraft:
        // Unbleached recycled craft paper with organic cellulose flecks
        _paintFibers(canvas, size, const Color(0xFF4A341B), extraOpacity: 1.3);
        break;

      case BookTextures.natural:
        // Natural book paper: delicate warm fiber grain
        _paintFibers(canvas, size, const Color(0xFF5A4D41));
        break;

      case BookTextures.slate:
        // Soft velvet night paper stippling
        _paintFibers(canvas, size, Colors.white, extraOpacity: 0.7);
        break;

      case BookTextures.washi:
        // Handmade Japanese mulberry tea paper: soft botanical tea wash and kozo fibers
        _vignettePaint.shader = RadialGradient(
          center: const Alignment(-0.15, -0.25),
          radius: 1.1,
          colors: [
            Colors.transparent,
            const Color(0xFF385E46).withValues(alpha: 0.025),
            const Color(0xFF244430).withValues(alpha: 0.05),
          ],
          stops: const [0.45, 0.80, 1.0],
        ).createShader(Offset.zero & size);
        canvas.drawRect(Offset.zero & size, _vignettePaint);
        _paintFibers(canvas, size, const Color(0xFF284835), extraOpacity: 0.85);
        break;

      case BookTextures.deckle:
        // Deckle rag folio: archival cotton pulp clouding and warm cellulose grain
        _vignettePaint.shader = RadialGradient(
          center: const Alignment(0.2, 0.15),
          radius: 1.05,
          colors: [
            Colors.transparent,
            const Color(0xFF7A6245).withValues(alpha: 0.025),
            const Color(0xFF5E462E).withValues(alpha: 0.06),
          ],
          stops: const [0.55, 0.85, 1.0],
        ).createShader(Offset.zero & size);
        canvas.drawRect(Offset.zero & size, _vignettePaint);
        _paintFibers(canvas, size, const Color(0xFF523B25), extraOpacity: 0.9);
        break;

      case BookTextures.obsidian:
        // Obsidian velvet: pure 0-nit pitch black with microscopic starlight silver dust
        _paintFibers(canvas, size, const Color(0xFFD8DCE3), extraOpacity: 0.45);
        break;
    }
  }

  void _paintFibers(Canvas canvas, Size size, Color fiberColor, {double extraOpacity = 1.0}) {
    final width = size.width;
    final height = size.height;

    for (final fiber in _fiberParticles) {
      final x = fiber.nx * width;
      final y = fiber.ny * height;
      final dx = math.cos(fiber.angle) * fiber.length;
      final dy = math.sin(fiber.angle) * fiber.length;

      _speckPaint
        ..strokeWidth = 1.2
        ..color = fiberColor.withValues(
          alpha: (fiber.opacity * extraOpacity).clamp(0.0, 0.15),
        );

      canvas.drawLine(Offset(x, y), Offset(x + dx, y + dy), _speckPaint);
    }
  }

  void _paintSpineGutter(Canvas canvas, Size size) {
    // Spine shadow at the binding edge (left in single-page, or right if left page)
    final spineLeft = !isLeftPage;
    final double gutterWidth = math.min(38.0, size.width * 0.10);
    final rect = spineLeft
        ? Rect.fromLTWH(0, 0, gutterWidth, size.height)
        : Rect.fromLTWH(size.width - gutterWidth, 0, gutterWidth, size.height);

    final spineColors = isDarkTheme
        ? [
            Colors.black.withValues(alpha: 0.45),
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.07),
            Colors.transparent,
          ]
        : [
            Colors.black.withValues(alpha: 0.24),
            Colors.black.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.03),
            Colors.transparent,
          ];

    _spinePaint.shader = LinearGradient(
      begin: spineLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: spineLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: spineColors,
      stops: const [0.0, 0.18, 0.55, 1.0],
    ).createShader(rect);

    canvas.drawRect(rect, _spinePaint);

    // Microscopic catch-light on the physical inner binding crease
    final creaseX = spineLeft ? 1.5 : size.width - 1.5;
    _edgeLinePaint.color = isDarkTheme
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.15);
    canvas.drawLine(Offset(creaseX, 0), Offset(creaseX, size.height), _edgeLinePaint);
  }

  void _paintStackedPageEdges(Canvas canvas, Size size) {
    // Stacked paper leaf edges along the outer margin
    final onRight = !isLeftPage;
    final double edgeMargin = onRight ? size.width : 0.0;
    final double direction = onRight ? -1.0 : 1.0;

    final baseEdgeAlpha = isDarkTheme ? 0.04 : 0.07;
    final edgeColor = isDarkTheme ? Colors.white : Colors.black;

    // Draw 4 fine parallel stacked page edge lines (simulating thickness of 500 pages)
    for (int i = 1; i <= 4; i++) {
      final x = edgeMargin + (direction * (i * 2.5));
      _edgeLinePaint.color = edgeColor.withValues(alpha: baseEdgeAlpha * (1.1 - i * 0.18));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _edgeLinePaint);
    }

    // Outer edge depth vignette
    final double edgeBandWidth = 14.0;
    final edgeRect = onRight
        ? Rect.fromLTWH(size.width - edgeBandWidth, 0, edgeBandWidth, size.height)
        : Rect.fromLTWH(0, 0, edgeBandWidth, size.height);

    _spinePaint.shader = LinearGradient(
      begin: onRight ? Alignment.centerRight : Alignment.centerLeft,
      end: onRight ? Alignment.centerLeft : Alignment.centerRight,
      colors: [
        edgeColor.withValues(alpha: isDarkTheme ? 0.18 : 0.09),
        Colors.transparent,
      ],
    ).createShader(edgeRect);

    canvas.drawRect(edgeRect, _spinePaint);
  }

  void _paintMarginVignette(Canvas canvas, Size size) {
    // Subtle ambient darkening around page corners and perimeter
    _vignettePaint.shader = RadialGradient(
      center: Alignment.center,
      radius: 1.05,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: isDarkTheme ? 0.08 : 0.04),
      ],
      stops: const [0.82, 1.0],
    ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, _vignettePaint);
  }

  @override
  bool shouldRepaint(covariant _BookPaperPainter oldDelegate) =>
      oldDelegate.textureId != textureId ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.showSpine != showSpine ||
      oldDelegate.isLeftPage != isLeftPage ||
      oldDelegate.isDarkTheme != isDarkTheme;
}

class _FiberParticle {
  final double nx;
  final double ny;
  final double length;
  final double angle;
  final double opacity;

  const _FiberParticle({
    required this.nx,
    required this.ny,
    required this.length,
    required this.angle,
    required this.opacity,
  });
}
