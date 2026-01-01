import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';

/// A shared shell widget that wraps reader content with chrome (UI overlays).
class ReaderShell extends StatelessWidget {
  /// The main reader content.
  final Widget body;

  /// The top bar widget (title, back button, actions).
  final Widget topBar;

  /// Optional bottom controls (page slider, TTS controls, etc.).
  final Widget? bottomControls;

  /// Controller for chrome visibility and lock mode.
  final ReaderChromeController chromeController;

  /// Optional callback for center tap (defaults to toggling chrome).
  final VoidCallback? onCenterTap;

  /// Optional callback for double tap (e.g., lock mode toggle).
  final VoidCallback? onDoubleTap;

  /// Optional gesture handler for horizontal drag end (page navigation).
  final GestureDragEndCallback? onHorizontalDragEnd;

  /// Optional gesture handler for vertical drag end (page navigation).
  final GestureDragEndCallback? onVerticalDragEnd;

  /// Animation duration for chrome show/hide.
  final Duration animationDuration;

  const ReaderShell({
    super.key,
    required this.body,
    required this.topBar,
    required this.chromeController,
    this.bottomControls,
    this.onCenterTap,
    this.onDoubleTap,
    this.onHorizontalDragEnd,
    this.onVerticalDragEnd,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ListenableBuilder(
      listenable: chromeController,
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTapUp(details, screenSize),
          onDoubleTap: _handleDoubleTap,
          onHorizontalDragEnd: onHorizontalDragEnd,
          onVerticalDragEnd: onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main content
              body,

              // Top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  offset: chromeController.showChrome
                      ? Offset.zero
                      : const Offset(0, -1),
                  duration: animationDuration,
                  child: AnimatedOpacity(
                    opacity: chromeController.showChrome ? 1.0 : 0.0,
                    duration: animationDuration,
                    child: IgnorePointer(
                      ignoring: !chromeController.showChrome,
                      child: topBar,
                    ),
                  ),
                ),
              ),

              // Bottom controls
              if (bottomControls != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    offset: chromeController.showChrome
                        ? Offset.zero
                        : const Offset(0, 1),
                    duration: animationDuration,
                    child: AnimatedOpacity(
                      opacity: chromeController.showChrome ? 1.0 : 0.0,
                      duration: animationDuration,
                      child: IgnorePointer(
                        ignoring: !chromeController.showChrome,
                        child: bottomControls,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleTapUp(TapUpDetails details, Size screenSize) {
    if (chromeController.isCenterTap(details.globalPosition, screenSize)) {
      if (onCenterTap != null) {
        onCenterTap!();
      } else {
        chromeController.toggleChrome();
      }
    }
  }

  void _handleDoubleTap() {
    if (onDoubleTap != null) {
      onDoubleTap!();
    }
  }
}
