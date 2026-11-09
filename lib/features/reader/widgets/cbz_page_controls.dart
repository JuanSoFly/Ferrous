import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/dimension_controller.dart';
import '../controllers/cbz_page_controller.dart';
import 'cbz_page_select_sheet.dart';

/// Compact Bottom Reader HUD for Comic/Manga archives (`.CBZ` / `.CBR`).
/// Provides:
/// 1. Interactive Page Scrubber Slider with live floating page counter preview.
/// 2. Compact navigation bar with First/Prev/Next/Last and tappable `< Page X / Total >` indicator to open Page Select Sheet.
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
        final outerBorder = Border(
          top: BorderSide(
            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 1.0,
          ),
        );
        final dividerColor = isEInk
            ? const Color(0xFF9E9A90)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.2);
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
                  // Row 1: Interactive Scrubber Slider Bar (sleek & compact)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
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

                  Divider(height: 1, thickness: 0.5, color: dividerColor),

                  // Row 2: Standard Bottom Reader Navigation Controls (compact)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 20),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'First page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: currentPage > 0
                              ? () => widget.pageController.jumpToPage(0)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Previous page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                          icon: const Icon(Icons.chevron_right, size: 20),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Next page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: currentPage < totalPages - 1
                              ? () => widget.pageController.jumpToPage(currentPage + 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 20),
                          color: textInk,
                          disabledColor: disabledInk,
                          tooltip: 'Last page',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
    final double thumbWidth = isEInk ? 12.0 : 16.0;
    final double thumbHeight = isEInk ? 16.0 : 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final trackWidth = totalWidth - thumbWidth;
        final progress = (totalPages <= 1)
            ? 0.0
            : (currentPage / (totalPages - 1)).clamp(0.0, 1.0);
        final thumbX = progress * trackWidth;

        // Floating bubble layout: ~90px wide, 20px high
        const bubbleWidth = 90.0;
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
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Floating live preview bubble (above thumb when scrubbing)
                if (isDragging)
                  Positioned(
                    left: bubbleLeft,
                    top: 0,
                    width: bubbleWidth,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isEInk
                            ? const Color(0xFF1A1A18)
                            : theme.colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(isEInk ? 2.0 : 6.0),
                        boxShadow: isEInk
                            ? const []
                            : const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
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
                                fontSize: 10,
                              )
                            : theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                      ),
                    ),
                  ),

                // 2. Track & Thumb Area (bottom 20px)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 20,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Slider Track (3.5px tall)
                      Positioned(
                        left: thumbWidth / 2,
                        right: thumbWidth / 2,
                        height: 3.5,
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
                                      blurRadius: 2,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                fontSize: 12,
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
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.pageText,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
