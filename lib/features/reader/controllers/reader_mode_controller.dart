import 'package:reader_app/core/models/book.dart';

/// Controller for reading mode logic.
class ReaderModeController {
  ReadingMode mode;

  ReaderModeController(this.mode);

  /// Horizontal swipe enabled.
  bool get useHorizontalSwipe {
    switch (mode) {
      case ReadingMode.leftToRight:
      case ReadingMode.horizontalContinuous:
        return true;
      case ReadingMode.vertical:
      case ReadingMode.verticalContinuous:
      case ReadingMode.webtoon:
        return false;
    }
  }

  /// Vertical swipe enabled.
  bool get useVerticalSwipe => !useHorizontalSwipe;

  /// Discrete pages.
  bool get isPagedMode {
    switch (mode) {
      case ReadingMode.vertical:
      case ReadingMode.leftToRight:
        return true;
      case ReadingMode.verticalContinuous:
      case ReadingMode.horizontalContinuous:
      case ReadingMode.webtoon:
        return false;
    }
  }

  /// Continuous scroll.
  bool get isContinuousMode => !isPagedMode;

  /// Whether the mode is horizontal (either paged or continuous).
  bool get isHorizontal {
    switch (mode) {
      case ReadingMode.leftToRight:
      case ReadingMode.horizontalContinuous:
        return true;
      case ReadingMode.vertical:
      case ReadingMode.verticalContinuous:
      case ReadingMode.webtoon:
        return false;
    }
  }

  /// Whether the mode is vertical (either paged or continuous).
  bool get isVertical => !isHorizontal;

  /// Swipe velocity threshold.
  double get swipeVelocityThreshold => 200.0;

  /// Page turn direction from horizontal drag.
  int getHorizontalSwipeDelta(double velocity) {
    if (!useHorizontalSwipe) return 0;
    if (velocity.abs() < swipeVelocityThreshold) return 0;
    return velocity > 0 ? -1 : 1;
  }

  /// Page turn direction from vertical drag.
  int getVerticalSwipeDelta(double velocity) {
    if (!useVerticalSwipe) return 0;
    if (velocity.abs() < swipeVelocityThreshold) return 0;
    return velocity > 0 ? -1 : 1;
  }
}
