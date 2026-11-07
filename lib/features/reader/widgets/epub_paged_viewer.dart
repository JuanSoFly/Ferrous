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
  double _accumulatedOverscroll = 0.0;
  DateTime? _lastPageTurnTime;

  @override
  void initState() {
    super.initState();
    widget.chapterController.addListener(_onChapterControllerChanged);
    final isCover = widget.chapterController.currentChapterIndex == 0 &&
        widget.chapterController.lastReadingSentenceStart == -1;
    _activePage = isCover ? 0 : widget.chapterController.currentChapterIndex + 1;
    _viewPageController = PageController(initialPage: _activePage);
  }

  @override
  void didUpdateWidget(EpubPagedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterController != widget.chapterController) {
      oldWidget.chapterController.removeListener(_onChapterControllerChanged);
      widget.chapterController.addListener(_onChapterControllerChanged);
    }
    if (oldWidget.readingMode != widget.readingMode) {
      _viewPageController.dispose();
      _viewPageController = PageController(initialPage: _activePage);
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
    final isCover = widget.chapterController.currentChapterIndex == 0 &&
        widget.chapterController.lastReadingSentenceStart == -1;
    final targetPage = isCover ? 0 : widget.chapterController.currentChapterIndex + 1;
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

  void _goToPreviousPage() {
    if (_activePage > 0) {
      final target = _activePage - 1;
      final themeRepo = context.read<ReaderThemeRepository>();
      final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
          themeRepo.config.pageFlip;
      if (useRealisticCurl) {
        _handlePageChanged(target);
      } else if (_viewPageController.hasClients) {
        _viewPageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        _handlePageChanged(target);
      }
    }
  }

  void _goToNextPage() {
    final totalPages = (widget.chapterController.chapters?.length ?? 0) + 1;
    if (_activePage < totalPages - 1) {
      final target = _activePage + 1;
      final themeRepo = context.read<ReaderThemeRepository>();
      final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
          themeRepo.config.pageFlip;
      if (useRealisticCurl) {
        _handlePageChanged(target);
      } else if (_viewPageController.hasClients) {
        _viewPageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        _handlePageChanged(target);
      }
    }
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    widget.onTapUp(details);

    if (widget.readingMode == ReadingMode.vertical) {
      const marginRatio = 0.15;
      final tapY = details.globalPosition.dy;
      final height = size.height;
      if (tapY < height * marginRatio) {
        _goToPreviousPage();
      } else if (tapY > height * (1.0 - marginRatio)) {
        _goToNextPage();
      } else {
        widget.onToggleChrome();
      }
    } else {
      const marginRatio = 0.18;
      final tapX = details.globalPosition.dx;
      final width = size.width;
      if (tapX < width * marginRatio) {
        _goToPreviousPage();
      } else if (tapX > width * (1.0 - marginRatio)) {
        _goToNextPage();
      } else {
        widget.onToggleChrome();
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      widget.chapterController.saveReadingPositionForMode(widget.readingMode);
    }

    if (widget.readingMode != ReadingMode.vertical) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _accumulatedOverscroll = 0.0;
    } else if (notification is OverscrollNotification) {
      _accumulatedOverscroll += notification.overscroll;
    } else if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final delta = notification.scrollDelta ?? 0.0;
      if (metrics.pixels <= metrics.minScrollExtent && delta < 0) {
        _accumulatedOverscroll += delta;
      } else if (metrics.pixels >= metrics.maxScrollExtent && delta > 0) {
        _accumulatedOverscroll += delta;
      }
    } else if (notification is ScrollEndNotification) {
      final now = DateTime.now();
      if (_lastPageTurnTime == null ||
          now.difference(_lastPageTurnTime!).inMilliseconds > 400) {
        const threshold = 35.0;
        final metrics = notification.metrics;
        final isAtTop = metrics.pixels <= metrics.minScrollExtent + 2.0;
        final isAtBottom = metrics.pixels >= metrics.maxScrollExtent - 2.0;

        if (_accumulatedOverscroll < -threshold || (isAtTop && _accumulatedOverscroll < -10)) {
          _lastPageTurnTime = now;
          _goToPreviousPage();
        } else if (_accumulatedOverscroll > threshold || (isAtBottom && _accumulatedOverscroll > 10)) {
          _lastPageTurnTime = now;
          _goToNextPage();
        }
      }
      _accumulatedOverscroll = 0.0;
    }
    return false;
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
    } else {
      widget.chapterController.onNavigatedToCover();
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
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, MediaQuery.of(context).size),
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0.0;
              if (velocity < -200) {
                _goToNextPage();
              }
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0.0;
              if (velocity < -200) {
                _goToNextPage();
              }
            },
            child: BookCoverPage(
              book: widget.chapterController.book,
              onToggleChrome: widget.onToggleChrome,
              onTurnPage: _goToNextPage,
            ),
          );
        }

        final chapterIndex = index - 1;
        final htmlContent = widget.chapterController.allChapterContents[chapterIndex];
        final scrollController =
            widget.chapterController.chapterScrollController(chapterIndex);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTapUp(details, MediaQuery.of(context).size),
          onHorizontalDragEnd: (details) {
            if (widget.readingMode == ReadingMode.vertical) {
              final velocity = details.primaryVelocity ?? 0.0;
              if (velocity < -200) {
                _goToNextPage();
              } else if (velocity > 200) {
                _goToPreviousPage();
              }
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: SingleChildScrollView(
              key: PageStorageKey('epub-chapter-scroll-$chapterIndex'),
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
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
