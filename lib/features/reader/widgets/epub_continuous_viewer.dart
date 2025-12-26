import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'epub_content_viewer.dart';

class EpubContinuousViewer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (chapterController.chapters == null) return const SizedBox.shrink();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          chapterController.updateCurrentChapterFromScroll(context);
        }
        return false;
      },
      child: GestureDetector(
        onTap: onToggleChrome,
        onTapUp: onTapUp,
        child: ListView.builder(
          controller: chapterController.scrollController,
          itemCount: chapterController.chapters!.length,
          itemBuilder: (context, index) {
            final isFirst = index == 0;
            final isLast = index == chapterController.chapters!.length - 1;
            final htmlContent = chapterController.allChapterContents[index];

            return Container(
              key: chapterController.chapterKeys[index],
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: isFirst ? topPadding : chapterSpacing,
                bottom: isLast ? bottomPadding : 0.0,
              ),
              child: EpubContentViewer(
                chapterIndex: index,
                htmlContent: htmlContent,
                chapterController: chapterController,
                ttsController: ttsController,
              ),
            );
          },
        ),
      ),
    );
  }
}
