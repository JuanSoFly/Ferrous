import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/dimension_controller.dart';
import '../controllers/cbz_page_controller.dart';
import 'cbz_page_select_sheet.dart';

/// Bottom Reader HUD for Comic/Manga archives (`.CBZ` / `.CBR`).
/// Provides:
/// 1. Interactive Page Scrubber Slider with live floating page counter preview and `-1`/`+1` stepping buttons.
/// 2. Navigation bar with First/Prev/Next/Last and tappable `< Page X / Total >` indicator to open Page Select Sheet.
/// 3. Strict Kindle Carta 1300 E-Ink Paper mode overrides when `E-Ink Paper` or `Compact Slate` is active.
class CbzPageControls extends StatefulWidget {
  final CbzPageController pageController;

  const CbzPageControls({
    super.key,
    required this.pageController,
  });

  @override
  State<CbzPageControls> createState() => _CbzPageControlsState();
}

class _CbzPageControlsState extends State<CbzPageControls> {
  int? _draggedPage;
  bool _isDragging = false;

  bool _checkIsEInk(BuildContext context) {
    try {
      final theme = Provider.of<AppTheme>(context, listen: false);
      if (theme == AppTheme.eInk) return true;
    } catch (_) {}
    try {
      final dimState = Provider.of<DimensionState>(context, listen: false);
      if (dimState.dimension == AppDimension.compactSlate) return true;
    } catch (_) {}
    final themeData = Theme.of(context);
    return themeData.scaffoldBackgroundColor == const Color(0xFFEAE6DF) &&
        themeData.colorScheme.primary == const Color(0xFF1A1A18);
  }

  void _onStepPrevious() {
    if (widget.pageController.pageIndex > 0) {
      widget.pageController.jumpToPage(widget.pageController.pageIndex - 1);
    }
  }

  void _onStepNext() {
    if (widget.pageController.pageIndex < widget.pageController.pageCount - 1) {
      widget.pageController.jumpToPage(widget.pageController.pageIndex + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pageController,
      builder: (context, _) {
        final totalPages = widget.pageController.pageCount;
        if (totalPages <= 1) return const SizedBox.shrink();

        final currentPage = widget.pageController.pageIndex;
        final displayPage = _isDragging ? (_draggedPage ?? currentPage) : currentPage;
        final theme = Theme.of(context);
        final isEInk = _checkIsEInk(context);

        // Styling tokens
        final containerBg = isEInk
            ? const Color(0xFFEAE6DF)
            : theme.colorScheme.surface.withValues(alpha: 0.94);
        final outerBorder = isEInk
            ? const Border(top: BorderSide(color: Color(0xFF1A1A18), width: 1.5))
            : Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1.0));
        final dividerColor = isEInk
            ? const Color(0xFF9E9A90)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
        final textInk = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface;
        final disabledInk = isEInk ? const Color(0xFF9E9A90) : theme.disabledColor;

        return SafeArea(
          top: false,
          child: Material(
            color: containerBg,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(border: outerBorder),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Interactive Scrubber Slider Bar
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left step button (- 1)
                        _StepButton(
                          label: '- 1',
                          tooltip: 'Previous page',
                          isEInk: isEInk,
                          enabled: currentPage > 0,
                          onPressed: _onStepPrevious,
                        ),

                        // Middle: Range Scrubber Slider with live floating bubble
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: _ComicScrubberSlider(
                              currentPage: displayPage,
                              totalPages: totalPages,
                              isDragging: _isDragging,
                              isEInk: isEInk,
                              onDragStart: (page) {
                                setState(() {
                                  _isDragging = true;
                                  _draggedPage = page;
                                });
                              },
                              onDragUpdate: (page) {
                                if (_draggedPage != page) {
                                  setState(() {
                                    _draggedPage = page;
                                  });
                                  if (!isEInk) {
                                    HapticFeedback.selectionClick();
                                  }
                                }
                              },
                              onDragEnd: (page) {
                                setState(() {
                                  _isDragging = false;
                                  _draggedPage = null;
                                });
                                widget.pageController.jumpToPage(page);
                              },
                            ),
                          ),
                        ),

                        // Right step button (+ 1)
                        _StepButton(
                          label: '+ 1',
                          tooltip: 'Next page',
                          isEInk: isEInk,
                          enabled: currentPage < totalPages - 1,
                          onPressed: _onStepNext,
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 1, thickness: 1, color: dividerColor),

                  // Row 2: Standard Bottom Reader Navigation Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.first_page),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'First page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: currentPage > 0
                              ? () => widget.pageController.jumpToPage(0)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Previous page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: currentPage > 0
                              ? () => widget.pageController.jumpToPage(currentPage - 1)
                              : null,
                        ),

                        // Tappable < Page X / Total > text opens Page Select Sheet
                        Flexible(
                          child: _TappablePageBadge(
                            pageText: '< Page ${currentPage + 1} / $totalPages >',
                            isEInk: isEInk,
                            onTap: () => showCbzPageSelectSheet(
                              context,
                              pageController: widget.pageController,
                            ),
                          ),
                        ),

                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Next page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: currentPage < totalPages - 1
                              ? () => widget.pageController.jumpToPage(currentPage + 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.last_page),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Last page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: currentPage < totalPages - 1
                              ? () => widget.pageController.jumpToPage(totalPages - 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Flanking single-page step button (- 1 / + 1)
class _StepButton extends StatefulWidget {
  final String label;
  final String tooltip;
  final bool isEInk;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepButton({
    required this.label,
    required this.tooltip,
    required this.isEInk,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isEInk) {
      final bg = widget.enabled
          ? (_isPressed ? const Color(0xFF1A1A18) : const Color(0xFFE0DCD3))
          : const Color(0xFFEAE6DF);
      final fg = widget.enabled
          ? (_isPressed ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18))
          : const Color(0xFF9E9A90);
      final border = widget.enabled
          ? const Color(0xFF1A1A18)
          : const Color(0xFF9E9A90);

      return Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: widget.enabled
              ? (_) {
                  setState(() => _isPressed = false);
                  widget.onPressed();
                }
              : null,
          onTapCancel: widget.enabled ? () => setState(() => _isPressed = false) : null,
          child: Container(
            width: 38,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(2.0),
              border: Border.all(color: border, width: 1.0),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: GoogleFonts.robotoMono(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: widget.enabled ? widget.onPressed : null,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: 38,
          height: 28,
          decoration: BoxDecoration(
            color: widget.enabled
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: widget.enabled
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: widget.enabled
                  ? theme.colorScheme.onSurface
                  : theme.disabledColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom horizontal scrubber slider with track, mechanical/circular thumb, and
/// live floating preview bubble (`Page X of Y`).
class _ComicScrubberSlider extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool isDragging;
  final bool isEInk;
  final ValueChanged<int> onDragStart;
  final ValueChanged<int> onDragUpdate;
  final ValueChanged<int> onDragEnd;

  const _ComicScrubberSlider({
    required this.currentPage,
    required this.totalPages,
    required this.isDragging,
    required this.isEInk,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  int _calculatePageFromDx(double dx, double width, double thumbWidth) {
    if (totalPages <= 1) return 0;
    final trackWidth = width - thumbWidth;
    if (trackWidth <= 0) return 0;
    final clampedX = (dx - thumbWidth / 2).clamp(0.0, trackWidth);
    final ratio = clampedX / trackWidth;
    return (ratio * (totalPages - 1)).round().clamp(0, totalPages - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double thumbWidth = isEInk ? 14.0 : 18.0;
    final double thumbHeight = isEInk ? 18.0 : 18.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final trackWidth = totalWidth - thumbWidth;
        final progress = (totalPages <= 1)
            ? 0.0
            : (currentPage / (totalPages - 1)).clamp(0.0, 1.0);
        final thumbX = progress * trackWidth;

        // Floating bubble layout: ~96px wide
        const bubbleWidth = 96.0;
        final bubbleLeft = (thumbX + thumbWidth / 2 - bubbleWidth / 2)
            .clamp(0.0, totalWidth - bubbleWidth);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            final page = _calculatePageFromDx(details.localPosition.dx, totalWidth, thumbWidth);
            onDragStart(page);
          },
          onHorizontalDragUpdate: (details) {
            final page = _calculatePageFromDx(details.localPosition.dx, totalWidth, thumbWidth);
            onDragUpdate(page);
          },
          onHorizontalDragEnd: (details) {
            onDragEnd(currentPage);
          },
          onTapDown: (details) {
            final page = _calculatePageFromDx(details.localPosition.dx, totalWidth, thumbWidth);
            onDragStart(page);
          },
          onTapUp: (details) {
            final page = _calculatePageFromDx(details.localPosition.dx, totalWidth, thumbWidth);
            onDragEnd(page);
          },
          child: SizedBox(
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Floating live preview bubble (above thumb when scrubbing)
                if (isDragging)
                  Positioned(
                    left: bubbleLeft,
                    top: 0,
                    width: bubbleWidth,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isEInk
                            ? const Color(0xFF1A1A18)
                            : theme.colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(isEInk ? 2.0 : 8.0),
                        boxShadow: isEInk
                            ? const []
                            : const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Page ${currentPage + 1} of $totalPages',
                        style: isEInk
                            ? GoogleFonts.robotoMono(
                                color: const Color(0xFFEAE6DF),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              )
                            : theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                                fontWeight: FontWeight.bold,
                              ),
                      ),
                    ),
                  ),

                // 2. Track & Thumb Area (bottom 28px)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Slider Track (4px tall)
                      Positioned(
                        left: thumbWidth / 2,
                        right: thumbWidth / 2,
                        height: 4.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isEInk
                                ? const Color(0xFFEAE6DF)
                                : theme.colorScheme.surfaceContainerHighest,
                            border: isEInk
                                ? Border.all(color: const Color(0xFF1A1A18), width: 1.0)
                                : null,
                            borderRadius: isEInk
                                ? BorderRadius.zero
                                : BorderRadius.circular(2.0),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isEInk
                                      ? const Color(0xFF1A1A18)
                                      : theme.colorScheme.primary,
                                  borderRadius: isEInk
                                      ? BorderRadius.zero
                                      : BorderRadius.circular(2.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Slider Thumb
                      Positioned(
                        left: thumbX,
                        child: Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          decoration: isEInk
                              ? BoxDecoration(
                                  color: const Color(0xFF1A1A18),
                                  border: Border.all(color: const Color(0xFFEAE6DF), width: 1.0),
                                  borderRadius: BorderRadius.circular(1.0),
                                )
                              : BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tappable `< Page X / Total >` indicator in the bottom HUD.
class _TappablePageBadge extends StatefulWidget {
  final String pageText;
  final bool isEInk;
  final VoidCallback onTap;

  const _TappablePageBadge({
    required this.pageText,
    required this.isEInk,
    required this.onTap,
  });

  @override
  State<_TappablePageBadge> createState() => _TappablePageBadgeState();
}

class _TappablePageBadgeState extends State<_TappablePageBadge> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isEInk) {
      final bg = _isPressed ? const Color(0xFF1A1A18) : const Color(0xFFE0DCD3);
      final fg = _isPressed ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);

      return Tooltip(
        message: 'Tap to select page',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(2.0),
              border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
            ),
            child: Text(
              widget.pageText,
              style: GoogleFonts.robotoSlab(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Tooltip(
      message: 'Tap to select page',
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            widget.pageText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
