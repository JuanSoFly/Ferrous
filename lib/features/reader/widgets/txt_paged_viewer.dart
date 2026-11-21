import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/models/annotation.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/core/utils/safe_screen_paginator.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/data/repositories/annotation_repository.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/features/reader/controllers/txt_chapter_controller.dart';
import 'package:ferrous/features/reader/controllers/txt_tts_controller.dart';
import 'package:ferrous/features/reader/controllers/reader_selection_controller.dart';
import 'txt_content_viewer.dart';
import 'realistic_page_turn.dart';
import 'reader_selection_menu_builder.dart';

class TxtPagedViewer extends StatefulWidget {
  final TxtChapterController chapterController;
  final TxtTtsController ttsController;
  final PageController pageController;
  final ReadingMode readingMode;
  final VoidCallback onToggleChrome;
  final Function(TapUpDetails) onTapUp;
  final bool Function()? onTryDismissSelection;
  final VoidCallback? onClearSelection;
  final ReaderSelectionController selectionController;
  final void Function(String cleanText) onAnnotate;

  const TxtPagedViewer({
    super.key,
    required this.chapterController,
    required this.ttsController,
    required this.pageController,
    required this.readingMode,
    required this.onToggleChrome,
    required this.onTapUp,
    this.onTryDismissSelection,
    this.onClearSelection,
    required this.selectionController,
    required this.onAnnotate,
  });

  @override
  State<TxtPagedViewer> createState() => _TxtPagedViewerState();
}

class _TxtPagedViewerState extends State<TxtPagedViewer> {
  final GlobalKey<RealisticPageTurnState> _realisticPageTurnKey = GlobalKey<RealisticPageTurnState>();
  bool _hadSelectionOnTapDown = false;
  late int _currentChapter;
  late int _activeSlot;
  late PageController _viewPageController;
  bool _isSwappingChapter = false;
  bool _isPageAnimating = false;
  int? _lastTtsHandledOffset;
  Size? _lastMeasuredSize;
  String? _lastFontFamily;

  void _checkFontReadiness() {
    final themeRepo = context.read<ReaderThemeRepository>();
    final family = themeRepo.config.fontFamily;
    if (family.isNotEmpty && family != 'default') {
      try {
        GoogleFonts.getFont(family);
        GoogleFonts.pendingFonts().then((_) {
          if (mounted) {
            SafeScreenPaginator.clearCache();
            setState(() {});
          }
        }).catchError((_) {});
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapterController.currentChapterIndex.clamp(
      0,
      (widget.chapterController.chapters?.length ?? 1) - 1,
    );
    final hasLeading = _currentChapter > 0;
    _activeSlot = hasLeading ? 1 : 0;
    _viewPageController = PageController(initialPage: _activeSlot);

    widget.chapterController.addListener(_onChapterControllerChanged);
    widget.ttsController.addListener(_onTtsControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeRepo = context.read<ReaderThemeRepository>();
    final currentFont = themeRepo.config.fontFamily;
    if (_lastFontFamily != currentFont) {
      _lastFontFamily = currentFont;
      _checkFontReadiness();
    }
    _calibrateActiveSlotForCurrentPosition();
  }

  @override
  void didUpdateWidget(TxtPagedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterController != widget.chapterController) {
      oldWidget.chapterController.removeListener(_onChapterControllerChanged);
      widget.chapterController.addListener(_onChapterControllerChanged);
    }
    if (oldWidget.ttsController != widget.ttsController) {
      oldWidget.ttsController.removeListener(_onTtsControllerChanged);
      widget.ttsController.addListener(_onTtsControllerChanged);
    }
    if (oldWidget.readingMode != widget.readingMode) {
      _calibrateActiveSlotForCurrentPosition();
    }
  }

  @override
  void dispose() {
    widget.chapterController.removeListener(_onChapterControllerChanged);
    widget.ttsController.removeListener(_onTtsControllerChanged);
    _viewPageController.dispose();
    super.dispose();
  }

  void _onChapterControllerChanged() {
    final controllerChapter = widget.chapterController.currentChapterIndex;
    if (controllerChapter != _currentChapter && !_isSwappingChapter) {
      setState(() {
        _currentChapter = controllerChapter;
        final hasLeading = _currentChapter > 0;
        _activeSlot = hasLeading ? 1 : 0;
        if (_viewPageController.hasClients) {
          _viewPageController.jumpToPage(_activeSlot);
        } else {
          _viewPageController = PageController(initialPage: _activeSlot);
        }
      });
      _calibrateActiveSlotForCurrentPosition();
    }
  }

  void _onTtsControllerChanged() {
    final ttsHighlightStart = widget.ttsController.lastHighlightStart;
    if (ttsHighlightStart == null || ttsHighlightStart == _lastTtsHandledOffset) return;
    _lastTtsHandledOffset = ttsHighlightStart;

    if (!widget.ttsController.ttsFollowMode) return;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotations = context.read<AnnotationRepository>().getAnnotationsForBook(widget.chapterController.book.id);

    final size = _lastMeasuredSize ?? MediaQuery.sizeOf(context);
    final horizontalMargin = themeRepo.config.pageMargins ? 16.0 : 0.0;
    final availWidth = (size.width - 32.0 - (horizontalMargin * 2)).clamp(100.0, double.infinity);
    final availHeight = (size.height - 32.0).clamp(100.0, double.infinity);

    final slices = _getPagedSlices(_currentChapter, availWidth, availHeight, themeRepo.config, annotations);
    for (int i = 0; i < slices.length; i++) {
      final slice = slices[i];
      if (ttsHighlightStart >= slice.startCharOffset && ttsHighlightStart < slice.endCharOffset) {
        final hasLeading = _currentChapter > 0;
        final targetSlot = i + (hasLeading ? 1 : 0);
        if (_activeSlot != targetSlot && !_isPageAnimating) {
          _activeSlot = targetSlot;
          if (_viewPageController.hasClients) {
            _isPageAnimating = true;
            _viewPageController
                .animateToPage(
                  targetSlot,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                )
                .then((_) => _isPageAnimating = false)
                .catchError((_) => _isPageAnimating = false);
          }
        }
        break;
      }
    }
  }

  void _calibrateActiveSlotForCurrentPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final themeRepo = context.read<ReaderThemeRepository>();
      final annotations = context.read<AnnotationRepository>().getAnnotationsForBook(widget.chapterController.book.id);

      final size = _lastMeasuredSize ?? MediaQuery.sizeOf(context);
      final horizontalMargin = themeRepo.config.pageMargins ? 16.0 : 0.0;
      final availWidth = (size.width - 32.0 - (horizontalMargin * 2)).clamp(100.0, double.infinity);
      final availHeight = (size.height - 32.0).clamp(100.0, double.infinity);

      final slices = _getPagedSlices(_currentChapter, availWidth, availHeight, themeRepo.config, annotations);
      if (slices.isEmpty) return;

      final savedStart = widget.chapterController.lastReadingSentenceStart;
      final hasLeading = _currentChapter > 0;
      int targetSliceIdx = 0;

      if (savedStart > 0) {
        for (int i = 0; i < slices.length; i++) {
          if (savedStart >= slices[i].startCharOffset && savedStart < slices[i].endCharOffset) {
            targetSliceIdx = i;
            break;
          }
        }
      }

      final targetSlot = targetSliceIdx + (hasLeading ? 1 : 0);
      if (_activeSlot != targetSlot) {
        _activeSlot = targetSlot;
        if (_viewPageController.hasClients) {
          _viewPageController.jumpToPage(targetSlot);
        } else {
          _viewPageController = PageController(initialPage: targetSlot);
        }
        setState(() {});
      }
      _saveReadingPositionForSlot(targetSliceIdx, slices);
    });
  }

  List<PageSlice> _getPagedSlices(
    int chapterIndex,
    double availWidth,
    double availHeight,
    ReaderThemeConfig themeConfig,
    List<Annotation> annotations,
  ) {
    if (chapterIndex < 0 || chapterIndex >= widget.chapterController.allChapterContents.length) {
      return const [];
    }

    final html = widget.chapterController.allChapterContents[chapterIndex];
    final plainText = (chapterIndex < widget.chapterController.allChapterPlainTexts.length)
        ? widget.chapterController.allChapterPlainTexts[chapterIndex]
        : '';

    final chapterAnnotations = annotations.where((a) => a.chapterIndex == chapterIndex).toList();

    return SafeScreenPaginator.paginateChapter(
      bookId: widget.chapterController.book.id,
      chapterIndex: chapterIndex,
      chapterHtml: html,
      chapterPlainText: plainText,
      availableWidth: availWidth,
      availableHeight: availHeight,
      fontSize: themeConfig.fontSize,
      lineHeight: themeConfig.lineHeight,
      paragraphSpacing: themeConfig.paragraphSpacing,
      fontFamily: themeConfig.fontFamily,
      paragraphIndent: themeConfig.paragraphIndent,
      hyphenation: themeConfig.hyphenation,
      annotations: chapterAnnotations,
    );
  }

  void _swapToAdjacentChapter({
    required int targetChapter,
    required bool landOnLastPage,
    BoxConstraints? constraints,
  }) {
    if (_isSwappingChapter) return;
    _isSwappingChapter = true;

    final totalChapters = widget.chapterController.chapters?.length ?? 0;
    if (targetChapter < 0 || targetChapter >= totalChapters) {
      _isSwappingChapter = false;
      return;
    }

    widget.chapterController.setChapterIndex(targetChapter, userInitiated: true);

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotations = context.read<AnnotationRepository>().getAnnotationsForBook(widget.chapterController.book.id);

    final actualConstraints = constraints ?? BoxConstraints.tight(_lastMeasuredSize ?? Size.zero);
    final horizontalMargin = themeRepo.config.pageMargins ? 16.0 : 0.0;
    final availWidth = (actualConstraints.maxWidth - 32.0 - (horizontalMargin * 2)).clamp(100.0, double.infinity);
    final availHeight = (actualConstraints.maxHeight - 32.0).clamp(100.0, double.infinity);

    final newSlices = _getPagedSlices(targetChapter, availWidth, availHeight, themeRepo.config, annotations);
    final hasLeading = targetChapter > 0;
    final newSlot = landOnLastPage
        ? ((newSlices.length - 1).clamp(0, newSlices.length) + (hasLeading ? 1 : 0))
        : (hasLeading ? 1 : 0);

    setState(() {
      _currentChapter = targetChapter;
      _activeSlot = newSlot;
      _viewPageController.dispose();
      _viewPageController = PageController(initialPage: newSlot);
    });

    final targetSliceIdx = landOnLastPage ? (newSlices.length - 1).clamp(0, newSlices.length) : 0;
    _saveReadingPositionForSlot(targetSliceIdx, newSlices);

    _isSwappingChapter = false;
  }

  void _saveReadingPositionForSlot(int sliceIdx, List<PageSlice> slices) {
    if (sliceIdx < 0 || sliceIdx >= slices.length) return;
    final slice = slices[sliceIdx];

    widget.chapterController.setActivePageBounds(slice.startCharOffset, slice.endCharOffset);

    final totalPages = widget.chapterController.chapters?.length ?? 1;
    widget.chapterController.repository.updateReadingProgress(
      widget.chapterController.book.id,
      sectionIndex: _currentChapter,
      totalPages: totalPages,
      lastReadingSentenceStart: slice.startCharOffset,
      lastReadingSentenceEnd: slice.endCharOffset,
    );
  }

  void _goToPreviousPage(int totalSlots) {
    if (_activeSlot > 0 && !_isPageAnimating) {
      widget.selectionController.clearSelection();
      widget.onClearSelection?.call();
      final target = _activeSlot - 1;
      final themeRepo = context.read<ReaderThemeRepository>();
      final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
          themeRepo.config.pageFlip;
      if (useRealisticCurl) {
        _handleSlotChanged(target);
      } else if (_viewPageController.hasClients) {
        _isPageAnimating = true;
        _viewPageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            )
            .then((_) => _isPageAnimating = false)
            .catchError((_) => _isPageAnimating = false);
      }
    }
  }

  void _goToNextPage(int totalSlots) {
    if (_activeSlot < totalSlots - 1 && !_isPageAnimating) {
      widget.selectionController.clearSelection();
      widget.onClearSelection?.call();
      final target = _activeSlot + 1;
      final themeRepo = context.read<ReaderThemeRepository>();
      final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
          themeRepo.config.pageFlip;
      if (useRealisticCurl) {
        _handleSlotChanged(target);
      } else if (_viewPageController.hasClients) {
        _isPageAnimating = true;
        _viewPageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            )
            .then((_) => _isPageAnimating = false)
            .catchError((_) => _isPageAnimating = false);
      }
    }
  }

  void _handleTapUp(TapUpDetails details, Size size, int totalSlots) {
    final themeRepo = context.read<ReaderThemeRepository>();
    final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
        themeRepo.config.pageFlip;

    if (widget.readingMode == ReadingMode.vertical) {
      const marginRatio = 0.15;
      final tapY = details.globalPosition.dy;
      final height = size.height;
      if (tapY < height * marginRatio) {
        _goToPreviousPage(totalSlots);
      } else if (tapY > height * (1.0 - marginRatio)) {
        _goToNextPage(totalSlots);
      } else {
        widget.onToggleChrome();
        widget.onTapUp(details);
      }
    } else {
      const marginRatio = 0.18;
      final tapX = details.globalPosition.dx;
      final width = size.width;
      if (tapX < width * marginRatio) {
        if (useRealisticCurl) {
          _realisticPageTurnKey.currentState?.turnPageAnimated(-1);
        } else {
          _goToPreviousPage(totalSlots);
        }
      } else if (tapX > width * (1.0 - marginRatio)) {
        if (useRealisticCurl) {
          _realisticPageTurnKey.currentState?.turnPageAnimated(1);
        } else {
          _goToNextPage(totalSlots);
        }
      } else {
        widget.onToggleChrome();
        widget.onTapUp(details);
      }
    }
  }

  Widget _buildPageItem(
    BuildContext context,
    int chapterIndex,
    PageSlice? slice,
    int totalSlots,
  ) {
    if (slice == null) return const SizedBox.shrink();
    final sliceIdx = slice.pageIndex;

    return SelectionArea(
      key: widget.selectionController.keyForPage(chapterIndex, sliceIdx),
      onSelectionChanged: (content) =>
          widget.selectionController.updateSelection('$chapterIndex-$sliceIdx', content),
      contextMenuBuilder: (context, selectableRegionState) =>
          ReaderSelectionMenuBuilder.build(
            context: context,
            selectableRegionState: selectableRegionState,
            selectedContent: widget.selectionController.selectedContent,
            onAnnotate: widget.onAnnotate,
            onSelectionCleared: () =>
                widget.selectionController.updateSelection('$chapterIndex-$sliceIdx', null),
          ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) {
          _hadSelectionOnTapDown = widget.selectionController.hasSelection;
        },
        onTapCancel: () {
          _hadSelectionOnTapDown = false;
        },
        onTapUp: (details) {
          final shouldConsume =
              _hadSelectionOnTapDown || widget.selectionController.tryDismissSelection();
          _hadSelectionOnTapDown = false;
          if (shouldConsume) {
            widget.selectionController.clearSelection();
            return;
          }
          _handleTapUp(details, MediaQuery.sizeOf(context), totalSlots);
        },
        child: SizedBox.expand(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0.0,
              maxHeight: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 16.0,
                  bottom: 16.0,
                ),
                child: TxtContentViewer(
                  chapterIndex: chapterIndex,
                  htmlContent: slice.html,
                  chapterController: widget.chapterController,
                  ttsController: widget.ttsController,
                  pageSlice: slice,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSlotChanged(int newSlot, [BoxConstraints? constraints]) {
    if (_isSwappingChapter) return;
    widget.selectionController.clearSelection();
    widget.selectionController.pruneChapter(_currentChapter);
    widget.onClearSelection?.call();
    _activeSlot = newSlot;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    final innerConstraints = constraints ?? BoxConstraints.tight(_lastMeasuredSize ?? Size.zero);
    final horizontalMargin = themeRepo.config.pageMargins ? 16.0 : 0.0;
    final availWidth = (innerConstraints.maxWidth - 32.0 - (horizontalMargin * 2)).clamp(100.0, double.infinity);
    final availHeight = (innerConstraints.maxHeight - 32.0).clamp(100.0, double.infinity);

    final slices = _getPagedSlices(
      _currentChapter,
      availWidth,
      availHeight,
      themeRepo.config,
      annotations,
    );

    final totalChapters = widget.chapterController.chapters?.length ?? 0;
    final hasLeading = _currentChapter > 0;
    final leadingOffset = hasLeading ? 1 : 0;
    final trailingSlot = leadingOffset + slices.length;

    if (hasLeading && newSlot == 0) {
      _swapToAdjacentChapter(targetChapter: _currentChapter - 1, landOnLastPage: true, constraints: innerConstraints);
    } else if (_currentChapter < totalChapters - 1 && newSlot == trailingSlot) {
      _swapToAdjacentChapter(targetChapter: _currentChapter + 1, landOnLastPage: false, constraints: innerConstraints);
    } else {
      final sliceIdx = newSlot - leadingOffset;
      _saveReadingPositionForSlot(sliceIdx, slices);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final annotationRepo = context.watch<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        _lastMeasuredSize = Size(constraints.maxWidth, constraints.maxHeight);
        final horizontalMargin = themeRepo.config.pageMargins ? 16.0 : 0.0;
        final availWidth = (constraints.maxWidth - 32.0 - (horizontalMargin * 2)).clamp(100.0, double.infinity);
        final availHeight = (constraints.maxHeight - 32.0).clamp(100.0, double.infinity);

        final slices = _getPagedSlices(_currentChapter, availWidth, availHeight, themeRepo.config, annotations);
        final totalChapters = widget.chapterController.chapters?.length ?? 1;

        final hasLeading = _currentChapter > 0;
        final hasTrailing = _currentChapter < totalChapters - 1;
        final leadingOffset = hasLeading ? 1 : 0;
        final trailingOffset = hasTrailing ? 1 : 0;
        final totalSlots = slices.length + leadingOffset + trailingOffset;
        final trailingSlot = totalSlots - 1;

        final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
            themeRepo.config.pageFlip;

        if (useRealisticCurl) {
          return RealisticPageTurn(
            key: _realisticPageTurnKey,
            chapterIndex: _currentChapter,
            pageCount: totalSlots,
            currentPage: _activeSlot,
            textureId: themeRepo.config.paperTexture,
            showSpine: themeRepo.config.showBookSpine,
            onPageChanged: (slot) => _handleSlotChanged(slot, constraints),
            onToggleChrome: widget.onToggleChrome,
            onTapUp: widget.onTapUp,
            onTryDismissSelection: widget.selectionController.tryDismissSelection,
            onClearSelection: widget.selectionController.clearSelection,
            pageBuilder: (context, slot) {
              if (hasLeading && slot == 0) {
                final prevSlices = _getPagedSlices(_currentChapter - 1, availWidth, availHeight, themeRepo.config, annotations);
                final prevSlice = prevSlices.isNotEmpty ? prevSlices.last : null;
                return _buildPageItem(context, _currentChapter - 1, prevSlice, totalSlots);
              }
              if (hasTrailing && slot == trailingSlot) {
                final nextSlices = _getPagedSlices(_currentChapter + 1, availWidth, availHeight, themeRepo.config, annotations);
                final nextSlice = nextSlices.isNotEmpty ? nextSlices.first : null;
                return _buildPageItem(context, _currentChapter + 1, nextSlice, totalSlots);
              }
              final sliceIdx = slot - leadingOffset;
              final slice = (sliceIdx >= 0 && sliceIdx < slices.length) ? slices[sliceIdx] : null;
              return _buildPageItem(context, _currentChapter, slice, totalSlots);
            },
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification && notification.dragDetails != null) {
              widget.selectionController.clearSelection();
              widget.onClearSelection?.call();
            }
            if (notification is ScrollEndNotification) {
              if (notification.depth != 0 || !_viewPageController.hasClients) return false;
              final settledSlot = _viewPageController.page?.round();
              if (settledSlot == null || _isSwappingChapter) return false;

              if (hasLeading && settledSlot == 0) {
                _swapToAdjacentChapter(targetChapter: _currentChapter - 1, landOnLastPage: true, constraints: constraints);
              } else if (hasTrailing && settledSlot == trailingSlot) {
                _swapToAdjacentChapter(targetChapter: _currentChapter + 1, landOnLastPage: false, constraints: constraints);
              } else {
                final sliceIdx = settledSlot - leadingOffset;
                if (sliceIdx >= 0 && sliceIdx < slices.length) {
                  _activeSlot = settledSlot;
                  _saveReadingPositionForSlot(sliceIdx, slices);
                }
              }
            }
            return false;
          },
          child: PageView.builder(
            key: ValueKey('txt-paged-pv-$_currentChapter'),
            controller: _viewPageController,
            scrollDirection: widget.readingMode == ReadingMode.vertical
                ? Axis.vertical
                : Axis.horizontal,
            itemCount: totalSlots,
            itemBuilder: (context, slot) {
              if (hasLeading && slot == 0) {
                final prevSlices = _getPagedSlices(_currentChapter - 1, availWidth, availHeight, themeRepo.config, annotations);
                final prevSlice = prevSlices.isNotEmpty ? prevSlices.last : null;
                return _buildPageItem(context, _currentChapter - 1, prevSlice, totalSlots);
              }
              if (hasTrailing && slot == trailingSlot) {
                final nextSlices = _getPagedSlices(_currentChapter + 1, availWidth, availHeight, themeRepo.config, annotations);
                final nextSlice = nextSlices.isNotEmpty ? nextSlices.first : null;
                return _buildPageItem(context, _currentChapter + 1, nextSlice, totalSlots);
              }
              final sliceIdx = slot - leadingOffset;
              final slice = (sliceIdx >= 0 && sliceIdx < slices.length) ? slices[sliceIdx] : null;
              return _buildPageItem(context, _currentChapter, slice, totalSlots);
            },
          ),
        );
      },
    );
  }
}
