import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/features/reader/controllers/epub_chapter_controller.dart';
import 'package:ferrous/features/reader/controllers/epub_tts_controller.dart';
import 'package:ferrous/features/reader/controllers/reader_mode_controller.dart';
import 'package:ferrous/features/reader/controllers/reader_selection_controller.dart';
import 'package:ferrous/features/reader/widgets/reader_selection_menu_builder.dart';
import 'epub_content_viewer.dart';

class EpubContinuousViewer extends StatefulWidget {
  final EpubChapterController chapterController;
  final EpubTtsController ttsController;
  final ReaderModeController modeController;
  final double chapterSpacing;
  final double topPadding;
  final double bottomPadding;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;
  final bool Function()? onTryDismissSelection;
  final VoidCallback? onClearSelection;
  final ReaderSelectionController selectionController;
  final void Function(String cleanText) onAnnotate;

  const EpubContinuousViewer({
    super.key,
    required this.chapterController,
    required this.ttsController,
    required this.modeController,
    this.chapterSpacing = 48.0,
    this.topPadding = 16.0,
    this.bottomPadding = 100.0,
    required this.onToggleChrome,
    required this.onTapUp,
    this.onTryDismissSelection,
    this.onClearSelection,
    required this.selectionController,
    required this.onAnnotate,
  });

  @override
  State<EpubContinuousViewer> createState() => _EpubContinuousViewerState();
}

class _EpubContinuousViewerState extends State<EpubContinuousViewer> {
  ReaderThemeConfig? _lastThemeConfig;
  Size? _lastScreenSize;
  bool _hadSelectionOnTapDown = false;

  @override
  Widget build(BuildContext context) {
    if (widget.chapterController.chapters == null) return const SizedBox.shrink();

    final themeConfig = context.select<ReaderThemeRepository, ReaderThemeConfig>((r) => r.config);
    final screenSize = MediaQuery.sizeOf(context);

    // Invalidate cached chapter heights and bounds when typography or screen orientation changes
    if (_lastThemeConfig != null &&
        (_lastThemeConfig!.fontSize != themeConfig.fontSize ||
         _lastThemeConfig!.lineHeight != themeConfig.lineHeight ||
         _lastThemeConfig!.fontFamily != themeConfig.fontFamily ||
         _lastThemeConfig!.pageMargins != themeConfig.pageMargins ||
         _lastThemeConfig!.paragraphSpacing != themeConfig.paragraphSpacing ||
         _lastThemeConfig!.paragraphIndent != themeConfig.paragraphIndent ||
         _lastScreenSize != screenSize)) {
      widget.chapterController.clearRecordedChapterHeights();
    }
    _lastThemeConfig = themeConfig;
    _lastScreenSize = screenSize;

    final totalCount = widget.chapterController.chapters!.length;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          widget.selectionController.clearSelection();
          widget.onClearSelection?.call();
        }
        if (widget.chapterController.isTransitioningMode ||
            widget.chapterController.isRestoringPosition ||
            widget.chapterController.isProgrammaticScroll) {
          return false;
        }
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.chapterController.updateCurrentChapterFromScroll(context, force: true);
        } else if (notification is ScrollUpdateNotification) {
          widget.chapterController.updateCurrentChapterFromScroll(context);
        }
        return false;
      },
      child: SelectionArea(
        key: widget.selectionController.keyForContinuousMode(),
        contextMenuBuilder: (context, selectableRegionState) => ReaderSelectionMenuBuilder.build(
          context: context,
          selectableRegionState: selectableRegionState,
          selectedContent: widget.selectionController.selectedContent,
          onAnnotate: widget.onAnnotate,
          onSelectionCleared: () => widget.selectionController.updateSelection(
            'continuous-viewport',
            null,
          ),
        ),
        onSelectionChanged: (content) {
          widget.selectionController.updateSelection(
            'continuous-viewport',
            content,
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            _hadSelectionOnTapDown = widget.selectionController.hasSelection;
          },
          onTapCancel: () {
            _hadSelectionOnTapDown = false;
          },
          onTapUp: (details) {
            if (_hadSelectionOnTapDown || widget.selectionController.tryDismissSelection()) {
              _hadSelectionOnTapDown = false;
              return;
            }
            _hadSelectionOnTapDown = false;
            widget.onToggleChrome();
            widget.onTapUp(details);
          },
          child: ListView.builder(
            key: ValueKey('epub-continuous-${widget.chapterController.scrollEpoch}'),
            controller: widget.chapterController.scrollController,
            scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
            addRepaintBoundaries: true,
            itemCount: totalCount,
            itemBuilder: (context, index) {
              final chapterIndex = index;
              final isLast = chapterIndex == widget.chapterController.chapters!.length - 1;
              final htmlContent = widget.chapterController.allChapterContents[chapterIndex];

              return Padding(
                key: widget.chapterController.chapterKeys[chapterIndex],
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: chapterIndex == 0 ? widget.topPadding : widget.chapterSpacing,
                  bottom: isLast ? widget.bottomPadding : 0.0,
                ),
                child: EpubContentViewer(
                  chapterIndex: chapterIndex,
                  htmlContent: htmlContent,
                  chapterController: widget.chapterController,
                  ttsController: widget.ttsController,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
