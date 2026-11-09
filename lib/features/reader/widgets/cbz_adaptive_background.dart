import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import '../models/page_corner_colors.dart';

/// Renders a dynamic, smoothly animated background for comic reading modes.
///
/// Adapts the letterbox / background colors to match the corners of the current page:
/// - In [ReadingMode.vertical], [ReadingMode.leftToRight], [ReadingMode.verticalContinuous],
///   and [ReadingMode.webtoon]: top bar corresponds to [PageCornerColors.topColor],
///   and bottom bar corresponds to [PageCornerColors.bottomColor].
/// - In [ReadingMode.horizontalContinuous]: left corresponds to [PageCornerColors.leftColor],
///   and right corresponds to [PageCornerColors.rightColor].
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

    final isHorizontal = readingMode == ReadingMode.horizontalContinuous;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background layer isolated with RepaintBoundary so color transitions
        // never trigger re-rasterization of the comic content
        RepaintBoundary(
          child: TweenAnimationBuilder<PageCornerColors?>(
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
                  gradient: isHorizontal
                      ? LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            activeColors.leftColor,
                            activeColors.rightColor,
                          ],
                        )
                      : LinearGradient(
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

/// A container that wraps individual comic pages in paged views (PageView / RealisticPageTurn),
/// providing page-locked letterboxing colors matching that page's corners.
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

    final isHorizontal = readingMode == ReadingMode.horizontalContinuous;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        Gradient gradient;

        if (isHorizontal) {
          // Horizontal continuous or horizontal pillarboxing
          if (aspectRatio != null && aspectRatio! > 0 && height > 0) {
            final fittedW = (height * aspectRatio!).clamp(0.0, width);
            final pillarboxW = (width - fittedW) / 2.0;
            if (pillarboxW > 2.0 && width > 0) {
              final stopL = (pillarboxW / width).clamp(0.0, 0.49);
              final stopR = ((width - pillarboxW) / width).clamp(0.51, 1.0);
              gradient = LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  colors!.leftColor,
                  colors!.leftColor,
                  colors!.rightColor,
                  colors!.rightColor,
                ],
                stops: [0.0, stopL, stopR, 1.0],
              );
            } else {
              gradient = LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [colors!.leftColor, colors!.rightColor],
              );
            }
          } else {
            gradient = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [colors!.leftColor, colors!.rightColor],
            );
          }
        } else {
          // Vertical paged, left to right, vertical continuous, webtoon
          if (aspectRatio != null && aspectRatio! > 0 && width > 0) {
            final fittedH = (width / aspectRatio!).clamp(0.0, height);
            final letterboxH = (height - fittedH) / 2.0;
            if (letterboxH > 2.0 && height > 0) {
              final stopT = (letterboxH / height).clamp(0.0, 0.49);
              final stopB = ((height - letterboxH) / height).clamp(0.51, 1.0);
              gradient = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors!.topColor,
                  colors!.topColor,
                  colors!.bottomColor,
                  colors!.bottomColor,
                ],
                stops: [0.0, stopT, stopB, 1.0],
              );
            } else {
              gradient = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors!.topColor, colors!.bottomColor],
              );
            }
          } else {
            gradient = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors!.topColor, colors!.bottomColor],
            );
          }
        }

        return DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: child,
        );
      },
    );
  }
}

class _PageCornerColorsTween extends Tween<PageCornerColors?> {
  _PageCornerColorsTween({super.begin, super.end});

  @override
  PageCornerColors? lerp(double t) => PageCornerColors.lerp(begin, end, t);
}
