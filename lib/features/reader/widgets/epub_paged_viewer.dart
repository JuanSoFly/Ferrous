import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'book_cover_page.dart';
import 'epub_content_viewer.dart';
import 'realistic_page_turn.dart';

class EpubPagedViewer extends StatefulWidget {
  final EpubChapterController chapterController;
  final EpubTtsController ttsController;
  final PageController pageController;
  final ReadingMode readingMode;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;

  const EpubPagedViewer({
    super.key,
    required this.chapterController,
    required this.ttsController,
    required this.pageController,
    required this.readingMode,
    required this.onToggleChrome,
    required this.onTapUp,
  });

  @override
  State<EpubPagedViewer> createState() => _EpubPagedViewerState();
}

class _EpubPagedViewerState extends State<EpubPagedViewer> {
  late int _activePage;
  late PageController _viewPageController;

  @override
  void initState() {
    super.initState();
    widget.chapterController.addListener(_onChapterControllerChanged);
    final book = widget.chapterController.book;
    final isFirstOpen = book.sectionIndex == 0 &&
        book.scrollPosition == 0.0 &&
        book.lastReadingSentenceStart == -1;
    _activePage = isFirstOpen ? 0 : widget.chapterController.currentChapterIndex + 1;
    _viewPageController = PageController(initialPage: _activePage);
  }

  @override
  void didUpdateWidget(EpubPagedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterController != widget.chapterController) {
      oldWidget.chapterController.removeListener(_onChapterControllerChanged);
      widget.chapterController.addListener(_onChapterControllerChanged);
    }
    _syncActivePage();
  }

  @override
  void dispose() {
    widget.chapterController.removeListener(_onChapterControllerChanged);
    _viewPageController.dispose();
    super.dispose();
  }

  void _onChapterControllerChanged() {
    _syncActivePage();
  }

  PageController _getOrUpdatePageController() {
    if (!_viewPageController.hasClients) {
      if (_viewPageController.initialPage != _activePage) {
        _viewPageController.dispose();
        _viewPageController = PageController(initialPage: _activePage);
      }
    }
    return _viewPageController;
  }

  void _syncActivePage() {
    final targetPage = widget.chapterController.currentChapterIndex + 1;
    if (_activePage != targetPage) {
      if (mounted) {
        setState(() {
          _activePage = targetPage;
        });
      } else {
        _activePage = targetPage;
      }
      if (_viewPageController.hasClients) {
        if (_viewPageController.page?.round() != targetPage) {
          _viewPageController.jumpToPage(targetPage);
        }
      } else {
        if (_viewPageController.initialPage != targetPage) {
          _viewPageController.dispose();
          _viewPageController = PageController(initialPage: targetPage);
        }
      }
      if (widget.pageController.hasClients &&
          widget.pageController.page?.round() != targetPage) {
        widget.pageController.jumpToPage(targetPage);
      }
    }
  }

  void _handlePageChanged(int index) {
    if (_activePage == index) return;
    // Save reading progress of the chapter we are navigating away from
    if (_activePage > 0) {
      widget.chapterController.saveReadingPositionForMode(widget.readingMode);
    }
    _activePage = index;
    if (index > 0) {
      final chapterIndex = index - 1;
      widget.chapterController.loadChapter(chapterIndex, userInitiated: false);
    }
    if (_viewPageController.hasClients &&
        _viewPageController.page?.round() != index) {
      _viewPageController.jumpToPage(index);
    } else if (!_viewPageController.hasClients &&
        _viewPageController.initialPage != index) {
      _viewPageController.dispose();
      _viewPageController = PageController(initialPage: index);
    }
    if (widget.pageController.hasClients &&
        widget.pageController.page?.round() != index) {
      widget.pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapterController.chapters == null) return const SizedBox.shrink();

    final themeRepo = context.watch<ReaderThemeRepository>();
    final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
        themeRepo.config.pageFlip;

    // Total page count is 1 cover page + N chapter pages
    final totalPages = widget.chapterController.chapters!.length + 1;

    if (useRealisticCurl) {
      return RealisticPageTurn(
        pageCount: totalPages,
        currentPage: _activePage,
        textureId: themeRepo.config.paperTexture,
        showSpine: themeRepo.config.showBookSpine,
        onPageChanged: _handlePageChanged,
        onToggleChrome: widget.onToggleChrome,
        onTapUp: widget.onTapUp,
        pageBuilder: (context, index) {
          if (index == 0) {
            return BookCoverPage(
              book: widget.chapterController.book,
              onToggleChrome: widget.onToggleChrome,
            );
          }

          final chapterIndex = index - 1;
          final htmlContent = widget.chapterController.allChapterContents[chapterIndex];
          final scrollController =
              widget.chapterController.chapterScrollController(chapterIndex);

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                widget.chapterController.saveReadingPositionForMode(widget.readingMode);
              }
              return false;
            },
            child: SingleChildScrollView(
              key: PageStorageKey('epub-chapter-scroll-$chapterIndex'),
              controller: scrollController,
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: 100.0,
              ),
              child: EpubContentViewer(
                chapterIndex: chapterIndex,
                htmlContent: htmlContent,
                chapterController: widget.chapterController,
                ttsController: widget.ttsController,
              ),
            ),
          );
        },
      );
    }

    return PageView.builder(
      controller: _getOrUpdatePageController(),
      scrollDirection: widget.readingMode == ReadingMode.vertical
          ? Axis.vertical
          : Axis.horizontal,
      itemCount: totalPages,
      onPageChanged: _handlePageChanged,
      itemBuilder: (context, index) {
        if (index == 0) {
          return BookCoverPage(
            book: widget.chapterController.book,
            onToggleChrome: widget.onToggleChrome,
          );
        }

        final chapterIndex = index - 1;
        final htmlContent = widget.chapterController.allChapterContents[chapterIndex];
        final scrollController =
            widget.chapterController.chapterScrollController(chapterIndex);

        return GestureDetector(
          onTap: widget.onToggleChrome,
          onTapUp: widget.onTapUp,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                widget.chapterController.saveReadingPositionForMode(widget.readingMode);
              }
              return false;
            },
            child: SingleChildScrollView(
              key: PageStorageKey('epub-chapter-scroll-$chapterIndex'),
              controller: scrollController,
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: 100.0,
              ),
              child: EpubContentViewer(
                chapterIndex: chapterIndex,
                htmlContent: htmlContent,
                chapterController: widget.chapterController,
                ttsController: widget.ttsController,
              ),
            ),
          ),
        );
      },
    );
  }
}
