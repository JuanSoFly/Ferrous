import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/controllers/mobi_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/mobi_tts_controller.dart';
import 'apple_books_page_curl.dart';
import 'mobi_content_viewer.dart';

class MobiPagedViewer extends StatefulWidget {
  final MobiChapterController chapterController;
  final MobiTtsController ttsController;
  final PageController pageController;
  final ReadingMode readingMode;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;

  const MobiPagedViewer({
    super.key,
    required this.chapterController,
    required this.ttsController,
    required this.pageController,
    required this.readingMode,
    required this.onToggleChrome,
    required this.onTapUp,
  });

  @override
  State<MobiPagedViewer> createState() => _MobiPagedViewerState();
}

class _MobiPagedViewerState extends State<MobiPagedViewer> {
  @override
  Widget build(BuildContext context) {
    if (widget.chapterController.chapters == null) return const SizedBox.shrink();

    final themeRepo = context.watch<ReaderThemeRepository>();
    final useAppleCurl = widget.readingMode != ReadingMode.vertical &&
        themeRepo.config.pageFlip;

    if (useAppleCurl) {
      return AppleBooksPageCurl(
        pageCount: widget.chapterController.chapters!.length,
        currentPage: widget.chapterController.currentChapterIndex,
        textureId: themeRepo.config.paperTexture,
        showSpine: themeRepo.config.showBookSpine,
        onPageChanged: (index) {
          widget.chapterController.loadChapter(index, userInitiated: false);
          if (widget.pageController.hasClients &&
              widget.pageController.page?.round() != index) {
            widget.pageController.jumpToPage(index);
          }
          final scrollController =
              widget.chapterController.chapterScrollController(index);
          if (scrollController.hasClients && scrollController.offset > 0) {
            scrollController.jumpTo(0.0);
          }
        },
        onToggleChrome: widget.onToggleChrome,
        onTapUp: widget.onTapUp,
        pageBuilder: (context, index) {
          final htmlContent = widget.chapterController.allChapterContents[index];
          final scrollController =
              widget.chapterController.chapterScrollController(index);

          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: 100.0,
            ),
            child: MobiContentViewer(
              chapterIndex: index,
              htmlContent: htmlContent,
              chapterController: widget.chapterController,
              ttsController: widget.ttsController,
            ),
          );
        },
      );
    }

    return PageView.builder(
      controller: widget.pageController,
      scrollDirection: widget.readingMode == ReadingMode.vertical
          ? Axis.vertical
          : Axis.horizontal,
      itemCount: widget.chapterController.chapters!.length,
      onPageChanged: (index) {
        widget.chapterController.loadChapter(index, userInitiated: false);
        final scrollController = widget.chapterController.chapterScrollController(index);
        if (scrollController.hasClients && scrollController.offset > 0) {
          scrollController.jumpTo(0.0);
        }
      },
      itemBuilder: (context, index) {
        final htmlContent = widget.chapterController.allChapterContents[index];
        final scrollController = widget.chapterController.chapterScrollController(index);

        return GestureDetector(
          onTap: widget.onToggleChrome,
          onTapUp: widget.onTapUp,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: 100.0,
            ),
            child: MobiContentViewer(
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
