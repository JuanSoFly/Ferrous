import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import '../models/page_corner_colors.dart';

/// Renders a dynamic background for comic reading modes.
///
/// In paged modes ([ReadingMode.vertical], [ReadingMode.leftToRight]):
/// smoothly transitions between page corner palettes as pages turn.
///
/// In continuous modes ([ReadingMode.verticalContinuous], [ReadingMode.webtoon],
/// [ReadingMode.horizontalContinuous]):
/// maintains a calm, stable backdrop to prevent flashing during scrolling,
/// while individual page letterboxes and seam separators handle transitions locally.
class CbzAdaptiveBackground extends StatelessWidget {
  final Widget child;
  final PageCornerColors? colors;
  final ReadingMode readingMode;
  final Duration animationDuration;

  const CbzAdaptiveBackground({
    super.key,
    required this.child,
    required this.colors,
    required this.readingMode,
    this.animationDuration = const Duration(milliseconds: 260),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallbackColor = theme.scaffoldBackgroundColor;
    final fallback = PageCornerColors.fallback(baseColor: fallbackColor);
    final targetColors = colors ?? fallback;

    final isContinuous = readingMode == ReadingMode.verticalContinuous ||
        readingMode == ReadingMode.webtoon ||
        readingMode == ReadingMode.horizontalContinuous;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background layer isolated with RepaintBoundary so color transitions
        // never trigger re-rasterization of the comic content
        RepaintBoundary(
          child: isContinuous
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: targetColors.isMangaWhitePaper ? const Color(0xFFFFFFFF) : fallbackColor,
                  ),
                  child: const SizedBox.expand(),
                )
              : TweenAnimationBuilder<PageCornerColors?>(
                  tween: _PageCornerColorsTween(
                    begin: targetColors,
                    end: targetColors,
                  ),
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedColors, _) {
                    final activeColors = animatedColors ?? targetColors;

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            activeColors.topColor,
                            activeColors.bottomColor,
                          ],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
        ),

        // Foreground comic content
        child,
      ],
    );
  }
}

/// A container that wraps individual comic pages in paged and continuous views,
/// painting page-locked letterbox and pillarbox margins matching that page's
/// exact horizontal profiles and dominant edge colors.
class CbzPageLetterboxContainer extends StatelessWidget {
  final Widget child;
  final PageCornerColors? colors;
  final ReadingMode readingMode;
  final double? aspectRatio;

  const CbzPageLetterboxContainer({
    super.key,
    required this.child,
    required this.colors,
    required this.readingMode,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    if (colors == null) {
      return child;
    }

    return CustomPaint(
      painter: _PageLetterboxPainter(
        colors: colors!,
        aspectRatio: aspectRatio,
      ),
      child: child,
    );
  }
}

/// Paints top/bottom letterboxing and left/right pillarboxing independently
/// on all 4 margins without unbounded layout calculations or single-gradient limitations.
class _PageLetterboxPainter extends CustomPainter {
  final PageCornerColors colors;
  final double? aspectRatio;

  const _PageLetterboxPainter({
    required this.colors,
    required this.aspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final contentRect = _calculateContentRect(size);
    final paint = Paint()..isAntiAlias = false;

    // 1. Top margin (Letterboxing) - Multi-stop horizontal gradient
    if (contentRect.top > 0.5) {
      final topShader = ui.Gradient.linear(
        Offset(contentRect.left, 0),
        Offset(contentRect.right > contentRect.left ? contentRect.right : size.width, 0),
        colors.topProfile,
        _calculateStops(colors.topProfile.length),
      );
      paint.shader = topShader;
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, contentRect.top), paint);
    }

    // 2. Bottom margin (Letterboxing) - Multi-stop horizontal gradient
    if (contentRect.bottom < size.height - 0.5) {
      final bottomShader = ui.Gradient.linear(
        Offset(contentRect.left, 0),
        Offset(contentRect.right > contentRect.left ? contentRect.right : size.width, 0),
        colors.bottomProfile,
        _calculateStops(colors.bottomProfile.length),
      );
      paint.shader = bottomShader;
      canvas.drawRect(Rect.fromLTRB(0, contentRect.bottom, size.width, size.height), paint);
    }

    // 3. Left margin (Pillarboxing) - Dominant left edge color
    if (contentRect.left > 0.5) {
      paint.shader = null;
      paint.color = colors.leftColor;
      canvas.drawRect(Rect.fromLTRB(0, 0, contentRect.left, size.height), paint);
    }

    // 4. Right margin (Pillarboxing) - Dominant right edge color
    if (contentRect.right < size.width - 0.5) {
      paint.shader = null;
      paint.color = colors.rightColor;
      canvas.drawRect(Rect.fromLTRB(contentRect.right, 0, size.width, size.height), paint);
    }
  }

  Rect _calculateContentRect(Size size) {
    if (aspectRatio == null || aspectRatio! <= 0 || size.width <= 0 || size.height <= 0) {
      return Rect.fromLTWH(0, 0, size.width, size.height);
    }

    final boxAr = size.width / size.height;
    if (boxAr > aspectRatio!) {
      // Container is wider than comic page -> Pillarbox Left & Right
      final fittedW = (size.height * aspectRatio!).clamp(0.0, size.width);
      final dx = (size.width - fittedW) / 2.0;
      return Rect.fromLTWH(dx, 0.0, fittedW, size.height);
    } else {
      // Container is taller than comic page -> Letterbox Top & Bottom
      final fittedH = (size.width / aspectRatio!).clamp(0.0, size.height);
      final dy = (size.height - fittedH) / 2.0;
      return Rect.fromLTWH(0.0, dy, size.width, fittedH);
    }
  }

  static List<double> _calculateStops(int length) {
    if (length <= 1) return const [0.0];
    return List.generate(length, (i) => i / (length - 1));
  }

  @override
  bool shouldRepaint(covariant _PageLetterboxPainter oldDelegate) {
    return oldDelegate.colors != colors || oldDelegate.aspectRatio != aspectRatio;
  }
}

class _PageCornerColorsTween extends Tween<PageCornerColors?> {
  _PageCornerColorsTween({super.begin, super.end});

  @override
  PageCornerColors? lerp(double t) => PageCornerColors.lerp(begin, end, t);
}
