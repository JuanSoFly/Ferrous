import 'package:reader_app/data/models/book.dart';

/// Controller for reading mode behavior and swipe direction logic.
/// 
/// Centralizes the repeated reading mode checks from all reader implementations:
/// - Determines if horizontal/vertical swipe navigation is active
/// - Determines if paged or continuous scrolling mode is active
class ReaderModeController {
  ReadingMode mode;

  ReaderModeController(this.mode);

  /// Whether to use horizontal swipe for page navigation (left-to-right or horizontal continuous).
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

  /// Whether to use vertical swipe for page navigation.
  bool get useVerticalSwipe => !useHorizontalSwipe;

  /// Whether the reader is in paged mode (discrete pages vs continuous scroll).
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

  /// Whether the reader is in continuous scrolling mode.
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

  /// Determine swipe delta threshold for page navigation.
  /// Returns the minimum velocity for a swipe to trigger page turn.
  double get swipeVelocityThreshold => 200.0;

  /// Determine page turn direction from horizontal drag end.
  /// Returns -1 for previous, 1 for next, 0 for no action.
  int getHorizontalSwipeDelta(double velocity) {
    if (!useHorizontalSwipe) return 0;
    if (velocity.abs() < swipeVelocityThreshold) return 0;
    return velocity > 0 ? -1 : 1;
  }

  /// Determine page turn direction from vertical drag end.
  /// Returns -1 for previous, 1 for next, 0 for no action.
  int getVerticalSwipeDelta(double velocity) {
    if (!useVerticalSwipe) return 0;
    if (velocity.abs() < swipeVelocityThreshold) return 0;
    return velocity > 0 ? -1 : 1;
  }
}
