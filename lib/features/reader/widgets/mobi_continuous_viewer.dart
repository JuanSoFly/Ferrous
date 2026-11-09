import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/features/reader/controllers/mobi_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/mobi_tts_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'book_cover_page.dart';
import 'mobi_content_viewer.dart';

class MobiContinuousViewer extends StatelessWidget {
  final MobiChapterController chapterController;
  final MobiTtsController ttsController;
  final ReaderModeController modeController;
  final double chapterSpacing;
  final double topPadding;
  final double bottomPadding;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;

  const MobiContinuousViewer({
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
  Widget build(BuildContext context) {
    if (chapterController.chapters == null) return const SizedBox.shrink();

    final totalCount = chapterController.chapters!.length + 1;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (chapterController.isTransitioningMode ||
            chapterController.isRestoringPosition ||
            chapterController.isProgrammaticScroll) {
          return false;
        }
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          chapterController.updateCurrentChapterFromScroll(context, force: true);
        } else if (notification is ScrollUpdateNotification) {
          chapterController.updateCurrentChapterFromScroll(context);
        }
        return false;
      },
      child: GestureDetector(
        onTap: onToggleChrome,
        onTapUp: onTapUp,
        child: ListView.builder(
          key: ValueKey('mobi-continuous-${chapterController.scrollEpoch}'),
          controller: chapterController.scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
          addRepaintBoundaries: true,
          itemCount: totalCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return BookCoverPage(
                book: chapterController.book,
                isContinuous: true,
              );
            }

            final chapterIndex = index - 1;
            final isLast = chapterIndex == chapterController.chapters!.length - 1;
            final htmlContent = chapterController.allChapterContents[chapterIndex];

            return RepaintBoundary(
              key: chapterController.chapterKeys[chapterIndex],
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: chapterSpacing,
                  bottom: isLast ? bottomPadding : 0.0,
                ),
                child: MobiContentViewer(
                  chapterIndex: chapterIndex,
                  htmlContent: htmlContent,
                  chapterController: chapterController,
                  ttsController: ttsController,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
