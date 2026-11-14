import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/features/reader/controllers/epub_chapter_controller.dart';
import 'package:ferrous/features/reader/controllers/epub_tts_controller.dart';
import 'package:ferrous/features/reader/controllers/reader_mode_controller.dart';
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
  });

  @override
  State<EpubContinuousViewer> createState() => _EpubContinuousViewerState();
}

class _EpubContinuousViewerState extends State<EpubContinuousViewer> {
  ReaderThemeConfig? _lastThemeConfig;
  Size? _lastScreenSize;

  @override
  Widget build(BuildContext context) {
    if (widget.chapterController.chapters == null) return const SizedBox.shrink();

    final themeRepo = context.watch<ReaderThemeRepository>();
    final themeConfig = themeRepo.config;
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
      child: GestureDetector(
        onTap: widget.onToggleChrome,
        onTapUp: widget.onTapUp,
        child: ListView.builder(
          key: ValueKey('epub-continuous-${widget.chapterController.scrollEpoch}'),
          controller: widget.chapterController.scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
          addRepaintBoundaries: false,
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
    );
  }
}
