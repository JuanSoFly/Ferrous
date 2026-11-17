import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'package:ferrous/features/reader/controllers/pdf_page_controller.dart';
import 'package:ferrous/features/reader/controllers/pdf_tts_controller.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/features/reader/widgets/cbz_adaptive_background.dart';
import 'package:ferrous/features/reader/widgets/pdf_page_viewer.dart';
import 'package:ferrous/src/rust/api/pdf.dart';
import 'package:ferrous/features/settings/app_themes.dart';

/// Self-contained reactive PDF page view item.
///
/// Wraps a single page index in a [ListenableBuilder] watching [PdfPageController]
/// so cached pages in [RealisticPageTurn] or [PageView] re-render automatically
/// as soon as the background raster completes without relying on parent rebuilds.
class PdfPageViewItem extends StatefulWidget {
  final int pageIndex;
  final PdfPageController pageController;
  final PdfTtsController ttsController;
  final bool isHorizontal;
  final GlobalKey? pageImageKey;

  const PdfPageViewItem({
    super.key,
    required this.pageIndex,
    required this.pageController,
    required this.ttsController,
    required this.isHorizontal,
    this.pageImageKey,
  });

  @override
  State<PdfPageViewItem> createState() => _PdfPageViewItemState();
}

class _PdfPageViewItemState extends State<PdfPageViewItem> {
  bool _preloadScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.pageController.scrollController.addListener(_onScroll);
    _checkPreload();
  }

  @override
  void didUpdateWidget(PdfPageViewItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.scrollController.removeListener(_onScroll);
      widget.pageController.scrollController.addListener(_onScroll);
    }
    if (oldWidget.pageIndex != widget.pageIndex || !widget.pageController.hasPageImage(widget.pageIndex)) {
      _preloadScheduled = false;
      _checkPreload();
    }
  }

  @override
  void dispose() {
    widget.pageController.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (!widget.pageController.hasPageImage(widget.pageIndex)) {
      _checkPreload();
    }
  }

  void _checkPreload() {
    if (_preloadScheduled) return;
    _preloadScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _preloadScheduled = false;
      if (!mounted) return;
      if (!widget.pageController.hasPageImage(widget.pageIndex)) {
        final isActive = widget.pageIndex == widget.pageController.pageIndex;
        widget.pageController.requestPageRender(
          widget.pageIndex,
          isActivePage: isActive,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pageController,
      builder: (context, _) {
        final pageController = widget.pageController;
        final index = widget.pageIndex;
        final hasImage = pageController.hasPageImage(index);
        final containerKey = (index >= 0 && index < pageController.pageKeys.length)
            ? pageController.pageKeys[index]
            : null;
        final cornerColors = pageController.getPageCornerColors(index);
        final double? pageAr = pageController.getPageAspectRatio(index);

        if (!hasImage) {
          _checkPreload();

          final placeholder = Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );

          final placeholderContent = CbzPageLetterboxContainer(
            colors: cornerColors,
            readingMode: pageController.readingMode,
            aspectRatio: pageAr,
            child: placeholder,
          );

          return KeyedSubtree(
            key: containerKey,
            child: RepaintBoundary(
              child: placeholderContent,
            ),
          );
        }

        final pageUiImage = pageController.getPageUiImage(index);

        final layoutSize = pageController.getLogicalPageSize(index).isEmpty
            ? (pageController.logicalPageSize.isEmpty
                ? pageController.renderedPageSize
                : pageController.logicalPageSize)
            : pageController.getLogicalPageSize(index);

        Widget imageWidget;
        if (pageUiImage != null) {
          imageWidget = RawImage(
            image: pageUiImage,
            fit: BoxFit.contain,
          );
        } else {
          imageWidget = const SizedBox.shrink();
        }

        final imageKey = widget.pageImageKey ??
            ((index >= 0 && index < pageController.pageImageKeys.length)
                ? pageController.pageImageKeys[index]
                : null);

        Widget layer;
        if (layoutSize.isEmpty) {
          layer = KeyedSubtree(
            key: imageKey,
            child: imageWidget,
          );
        } else {
          layer = SizedBox(
            key: imageKey,
            width: layoutSize.width,
            height: layoutSize.height,
            child: Stack(
              children: [
                Positioned.fill(child: imageWidget),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: Consumer2<ReaderThemeRepository, AppTheme?>(
                        builder: (context, themeRepo, currentTheme, _) {
                          final isEInk = currentTheme == AppTheme.eInk;
                          final highlightStyle = themeRepo.highlightStyle;

                          return ValueListenableBuilder<List<PdfTextRect>>(
                            valueListenable: widget.ttsController.highlightRectsNotifier,
                            builder: (context, rects, _) {
                              if (!widget.ttsController.showTtsControls ||
                                  rects.isEmpty ||
                                  widget.ttsController.highlightPageIndex != index) {
                                return const SizedBox.shrink();
                              }
                              return CustomPaint(
                                painter: PdfHighlightPainter(
                                  rects: rects,
                                  style: highlightStyle,
                                  primaryColor: Theme.of(context).colorScheme.primary,
                                  isEInk: isEInk,
                                  isDarkMode: Theme.of(context).brightness == Brightness.dark,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget content = CbzPageLetterboxContainer(
          colors: cornerColors,
          readingMode: pageController.readingMode,
          aspectRatio: pageAr,
          child: Center(child: layer),
        );

        return KeyedSubtree(
          key: containerKey,
          child: RepaintBoundary(
            child: content,
          ),
        );
      },
    );
  }
}
