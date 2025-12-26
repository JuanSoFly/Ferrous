import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'epub_content_viewer.dart';

class EpubPagedViewer extends StatefulWidget {
  final EpubChapterController chapterController;
  final EpubTtsController ttsController;
  final PageController pageController;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;

  const EpubPagedViewer({
    super.key,
    required this.chapterController,
    required this.ttsController,
    required this.pageController,
    required this.onToggleChrome,
    required this.onTapUp,
  });

  @override
  State<EpubPagedViewer> createState() => _EpubPagedViewerState();
}

class _EpubPagedViewerState extends State<EpubPagedViewer> {
  @override
  Widget build(BuildContext context) {
    if (widget.chapterController.chapters == null) return const SizedBox.shrink();

    return PageView.builder(
      controller: widget.pageController,
      itemCount: widget.chapterController.chapters!.length,
      onPageChanged: (index) {
        widget.chapterController.loadChapter(index, userInitiated: false);
      },
      itemBuilder: (context, index) {
        final htmlContent = widget.chapterController.allChapterContents[index];
        final scrollController = widget.chapterController.chapterScrollController(index);

        return GestureDetector(
          onTap: widget.onToggleChrome,
          onTapUp: widget.onTapUp,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(top: 16.0, bottom: 100.0),
            child: EpubContentViewer(
              chapterIndex: index,
              htmlContent: htmlContent,
              chapterController: widget.chapterController,
              ttsController: widget.ttsController,
            ),
          ),
        );
      },
    );
  }
}
