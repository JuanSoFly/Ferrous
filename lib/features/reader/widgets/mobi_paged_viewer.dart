import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/models/annotation.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/core/utils/safe_screen_paginator.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/data/repositories/annotation_repository.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/features/reader/controllers/mobi_chapter_controller.dart';
import 'package:ferrous/features/reader/controllers/mobi_tts_controller.dart';
import 'mobi_content_viewer.dart';
import 'realistic_page_turn.dart';

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
  void didUpdateWidget(MobiPagedViewer oldWidget) {
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
      if (_viewPageController.hasClients) {
        final oldController = _viewPageController;
        _viewPageController = PageController(initialPage: _activeSlot);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
    }
    _syncActiveChapter();
  }

  @override
  void dispose() {
    widget.chapterController.removeListener(_onChapterControllerChanged);
    widget.ttsController.removeListener(_onTtsControllerChanged);
    _viewPageController.dispose();
    super.dispose();
  }

  void _onChapterControllerChanged() {
    _syncActiveChapter();
  }

  BoxConstraints _getInnerConstraints() {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final width = (size.width - padding.left - padding.right).clamp(50.0, size.width);
    final height = (size.height - padding.top - padding.bottom).clamp(50.0, size.height);
    return BoxConstraints.tightFor(width: width, height: height);
  }

  void _calibrateActiveSlotForCurrentPosition() {
    if (!mounted) return;
    final constraints = _getInnerConstraints();
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    if (_lastMeasuredSize != null && _lastMeasuredSize == size) return;
    _lastMeasuredSize = size;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);
    final (availWidth, availHeight) = _computeAvailableDimensions(constraints, themeRepo.config);

    final slices = _getPagedSlices(
      _currentChapter,
      availWidth,
      availHeight,
      themeRepo.config,
      annotations,
    );
    if (slices.isEmpty) return;

    final hasLeading = _currentChapter > 0;
    final leadingOffset = hasLeading ? 1 : 0;
    final maxSlot = slices.isNotEmpty ? leadingOffset + slices.length - 1 : leadingOffset;
    final targetSliceIdx = _findSliceForOffset(slices, widget.chapterController.lastReadingSentenceStart);
    final targetSlot = (targetSliceIdx + leadingOffset).clamp(leadingOffset, maxSlot);

    if (_activeSlot != targetSlot) {
      _activeSlot = targetSlot;
      final oldController = _viewPageController;
      _viewPageController = PageController(initialPage: targetSlot);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
      if (mounted) setState(() {});
    }
  }

  void _syncActiveChapter() {
    if (_isSwappingChapter) return;
    // Never interrupt an active user drag or fling animation
    if (_viewPageController.hasClients &&
        _viewPageController.position.isScrollingNotifier.value) {
      return;
    }

    final targetChapter = widget.chapterController.currentChapterIndex.clamp(
      0,
      (widget.chapterController.chapters?.length ?? 1) - 1,
    );

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);
    final constraints = _getInnerConstraints();
    final (availWidth, availHeight) = _computeAvailableDimensions(constraints, themeRepo.config);
    final slices = _getPagedSlices(targetChapter, availWidth, availHeight, themeRepo.config, annotations);

    final hasLeading = targetChapter > 0;
    final leadingOffset = hasLeading ? 1 : 0;
    final maxSlot = slices.isNotEmpty ? leadingOffset + slices.length - 1 : leadingOffset;
    final targetSliceIdx = _findSliceForOffset(slices, widget.chapterController.lastReadingSentenceStart);
    final targetSlot = (targetSliceIdx + leadingOffset).clamp(leadingOffset, maxSlot);

    if (_currentChapter != targetChapter) {
      _currentChapter = targetChapter;
      _activeSlot = targetSlot;

      final oldController = _viewPageController;
      _viewPageController = PageController(initialPage: targetSlot);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });

      if (mounted) {
        setState(() {});
      }
    } else if (_activeSlot != targetSlot) {
      // Same chapter (e.g., TOC re-anchor to Page 0): jump existing controller in place
      _activeSlot = targetSlot;
      if (_viewPageController.hasClients) {
        _viewPageController.jumpToPage(targetSlot);
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onTtsControllerChanged() {
    if (!mounted || _isSwappingChapter || _isPageAnimating) return;
    final highlightStart = widget.ttsController.lastHighlightStart;
    if (highlightStart == null || highlightStart == _lastTtsHandledOffset) return;
    _lastTtsHandledOffset = highlightStart;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    final constraints = _getInnerConstraints();
    final (availWidth, availHeight) = _computeAvailableDimensions(constraints, themeRepo.config);

    final slices = _getPagedSlices(
      _currentChapter,
      availWidth,
      availHeight,
      themeRepo.config,
      annotations,
    );
    if (slices.isEmpty) return;

    final hasLeading = _currentChapter > 0;
    final leadingOffset = hasLeading ? 1 : 0;
    final targetSliceIdx = _findSliceForOffset(slices, highlightStart);
    final targetSlot = targetSliceIdx + leadingOffset;

    if (targetSlot != _activeSlot) {
      _activeSlot = targetSlot;
      final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
          themeRepo.config.pageFlip;

      if (useRealisticCurl) {
        if (mounted) setState(() {});
      } else if (_viewPageController.hasClients) {
        _isPageAnimating = true;
        _viewPageController
            .animateToPage(
              targetSlot,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            )
            .then((_) => _isPageAnimating = false)
            .catchError((_) => _isPageAnimating = false);
      }
    }
  }

  (double, double) _computeAvailableDimensions(BoxConstraints constraints, ReaderThemeConfig config) {
    final horizontalMargin = config.pageMargins ? 32.0 : 16.0;
    const verticalTopBottomPadding = 32.0; // 16.0 top + 16.0 bottom
    final availWidth = (constraints.maxWidth - (horizontalMargin * 2)).clamp(50.0, constraints.maxWidth);
    final availHeight = (constraints.maxHeight - verticalTopBottomPadding).clamp(50.0, constraints.maxHeight);
    return (availWidth, availHeight);
  }

  List<PageSlice> _getPagedSlices(
    int chapterIndex,
    double width,
    double height,
    ReaderThemeConfig themeConfig,
    List<Annotation> annotations,
  ) {
    final totalChapters = widget.chapterController.chapters?.length ?? 0;
    if (chapterIndex < 0 || chapterIndex >= totalChapters) {
      return const [];
    }

    final html = widget.chapterController.allChapterContents.length > chapterIndex
        ? widget.chapterController.allChapterContents[chapterIndex]
        : '';
    final plainText = widget.chapterController.allChapterPlainTexts.length > chapterIndex
        ? widget.chapterController.allChapterPlainTexts[chapterIndex]
        : '';
    final chapterAnns = annotations.where((a) => a.chapterIndex == chapterIndex).toList();

    TextAlign parseTextAlign(String align) {
      switch (align) {
        case 'left':
          return TextAlign.left;
        case 'right':
          return TextAlign.right;
        case 'center':
          return TextAlign.center;
        case 'justify':
        default:
          return TextAlign.justify;
      }
    }

    return SafeScreenPaginator.paginateChapter(
      bookId: widget.chapterController.book.id,
      chapterIndex: chapterIndex,
      chapterHtml: html,
      chapterPlainText: plainText,
      availableWidth: width,
      availableHeight: height,
      fontSize: themeConfig.fontSize,
      lineHeight: themeConfig.lineHeight,
      paragraphSpacing: themeConfig.paragraphSpacing,
      fontFamily: themeConfig.fontFamily,
      paragraphIndent: themeConfig.paragraphIndent,
      hyphenation: themeConfig.hyphenation,
      annotations: chapterAnns,
      textAlign: parseTextAlign(themeConfig.textAlign),
      fontWeight: FontWeight.values[(themeConfig.fontWeight ~/ 100).clamp(0, 8)],
      wordSpacing: themeConfig.wordSpacing,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  int _findSliceForOffset(List<PageSlice> slices, int offset) {
    if (slices.isEmpty || offset <= 0) return 0;
    for (int i = 0; i < slices.length; i++) {
      if (offset >= slices[i].startCharOffset && offset < slices[i].endCharOffset) {
        return i;
      }
    }
    if (offset >= slices.last.endCharOffset) {
      return slices.length - 1;
    }
    return 0;
  }

  void _saveReadingPositionForSlot(int sliceIndex, List<PageSlice> slices) {
    if (sliceIndex < 0 || sliceIndex >= slices.length) return;
    final slice = slices[sliceIndex];
    widget.chapterController.setActivePageBounds(
      slice.startCharOffset,
      slice.endCharOffset,
    );
    final totalTextLen = widget.chapterController.allChapterPlainTexts.length > _currentChapter
        ? widget.chapterController.allChapterPlainTexts[_currentChapter].length
        : 1;
    final fraction = totalTextLen > 0
        ? (slice.startCharOffset / totalTextLen).clamp(0.0, 1.0)
        : 0.0;
    widget.chapterController.savePagedReadingPosition(
      _currentChapter,
      slice.startCharOffset,
      fraction,
    );
  }

  void _swapToAdjacentChapter({
    required int targetChapter,
    required bool landOnLastPage,
    BoxConstraints? constraints,
  }) {
    if (_isSwappingChapter) return;
    _isSwappingChapter = true;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    final innerConstraints = constraints ?? _getInnerConstraints();
    final (availWidth, availHeight) = _computeAvailableDimensions(innerConstraints, themeRepo.config);

    final targetSlices = _getPagedSlices(
      targetChapter,
      availWidth,
      availHeight,
      themeRepo.config,
      annotations,
    );

    final targetHasLeading = targetChapter > 0;
    final targetLeadingOffset = targetHasLeading ? 1 : 0;
    final targetSlot = landOnLastPage
        ? (targetLeadingOffset + targetSlices.length - 1).clamp(0, targetLeadingOffset + targetSlices.length)
        : targetLeadingOffset;

    // Safely re-seed page controller without bubbling disposal crashes
    final oldController = _viewPageController;
    _viewPageController = PageController(initialPage: targetSlot);
    _activeSlot = targetSlot;
    _currentChapter = targetChapter;

    widget.chapterController.loadChapter(targetChapter, userInitiated: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });

    final targetSliceIdx = targetSlot - targetLeadingOffset;
    if (targetSliceIdx >= 0 && targetSliceIdx < targetSlices.length) {
      _saveReadingPositionForSlot(targetSliceIdx, targetSlices);
    }

    if (mounted) {
      setState(() {
        _isSwappingChapter = false;
      });
    }
  }

  void _goToPreviousPage(int totalSlots) {
    if (_activeSlot > 0 && !_isPageAnimating) {
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
    widget.onTapUp(details);

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
      }
    } else {
      const marginRatio = 0.18;
      final tapX = details.globalPosition.dx;
      final width = size.width;
      if (tapX < width * marginRatio) {
        _goToPreviousPage(totalSlots);
      } else if (tapX > width * (1.0 - marginRatio)) {
        _goToNextPage(totalSlots);
      } else {
        widget.onToggleChrome();
      }
    }
  }

  void _handleSlotChanged(int newSlot, [BoxConstraints? constraints]) {
    if (_isSwappingChapter) return;
    _activeSlot = newSlot;

    final themeRepo = context.read<ReaderThemeRepository>();
    final annotationRepo = context.read<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    final innerConstraints = constraints ?? _getInnerConstraints();
    final (availWidth, availHeight) = _computeAvailableDimensions(innerConstraints, themeRepo.config);

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

  Widget _buildPageItem(BuildContext context, int chapterIndex, PageSlice? slice) {
    final html = widget.chapterController.allChapterContents.length > chapterIndex
        ? widget.chapterController.allChapterContents[chapterIndex]
        : '';

    return SingleChildScrollView(
      key: ValueKey('mobi-page-slice-$chapterIndex-${slice?.pageIndex ?? -1}'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 16.0,
      ),
      child: MobiContentViewer(
        chapterIndex: chapterIndex,
        htmlContent: html,
        chapterController: widget.chapterController,
        ttsController: widget.ttsController,
        pageSlice: slice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalChapters = widget.chapterController.chapters?.length ?? 0;
    if (totalChapters == 0) return const SizedBox.shrink();

    final themeRepo = context.watch<ReaderThemeRepository>();
    final annotationRepo = context.watch<AnnotationRepository>();
    final annotations = annotationRepo.getAnnotationsForBook(widget.chapterController.book.id);

    return SafeArea(
      top: true,
      bottom: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final (availWidth, availHeight) = _computeAvailableDimensions(constraints, themeRepo.config);

          final slices = _getPagedSlices(
            _currentChapter,
            availWidth,
            availHeight,
            themeRepo.config,
            annotations,
          );

          final hasLeading = _currentChapter > 0;
          final leadingOffset = hasLeading ? 1 : 0;
          final hasTrailing = _currentChapter < totalChapters - 1;
          final trailingSlot = leadingOffset + slices.length;
          final totalSlots = slices.length + leadingOffset + (hasTrailing ? 1 : 0);

          // Ensure _activeSlot is clamped within valid bounds
          if (_activeSlot >= totalSlots) {
            _activeSlot = (totalSlots - 1).clamp(0, totalSlots);
          }

          // Seed active page slice bounds on ChapterController
          final activeSliceIdx = _activeSlot - leadingOffset;
          if (activeSliceIdx >= 0 && activeSliceIdx < slices.length) {
            final activeSlice = slices[activeSliceIdx];
            widget.chapterController.setActivePageBounds(
              activeSlice.startCharOffset,
              activeSlice.endCharOffset,
            );
          }

          // Schedule background pre-pagination for adjacent sentinels
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_currentChapter + 1 < totalChapters) {
              _getPagedSlices(_currentChapter + 1, availWidth, availHeight, themeRepo.config, annotations);
            }
            if (_currentChapter - 1 >= 0) {
              _getPagedSlices(_currentChapter - 1, availWidth, availHeight, themeRepo.config, annotations);
            }
          });

          final useRealisticCurl = widget.readingMode != ReadingMode.vertical &&
              themeRepo.config.pageFlip;

          if (useRealisticCurl) {
            return RealisticPageTurn(
              key: ValueKey('mobi-curl-ch-$_currentChapter'),
              pageCount: totalSlots,
              currentPage: _activeSlot,
              textureId: themeRepo.config.paperTexture,
              showSpine: themeRepo.config.showBookSpine,
              onPageChanged: (slot) => _handleSlotChanged(slot, constraints),
              onToggleChrome: widget.onToggleChrome,
              onTapUp: widget.onTapUp,
              pageBuilder: (context, slot) {
                if (hasLeading && slot == 0) {
                  final prevSlices = _getPagedSlices(
                    _currentChapter - 1,
                    availWidth,
                    availHeight,
                    themeRepo.config,
                    annotations,
                  );
                  final prevSlice = prevSlices.isNotEmpty ? prevSlices.last : null;
                  return _buildPageItem(context, _currentChapter - 1, prevSlice);
                }
                if (hasTrailing && slot == trailingSlot) {
                  final nextSlices = _getPagedSlices(
                    _currentChapter + 1,
                    availWidth,
                    availHeight,
                    themeRepo.config,
                    annotations,
                  );
                  final nextSlice = nextSlices.isNotEmpty ? nextSlices.first : null;
                  return _buildPageItem(context, _currentChapter + 1, nextSlice);
                }
                final sliceIdx = slot - leadingOffset;
                final slice = (sliceIdx >= 0 && sliceIdx < slices.length) ? slices[sliceIdx] : null;
                return _buildPageItem(context, _currentChapter, slice);
              },
            );
          }

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _handleTapUp(details, MediaQuery.sizeOf(context), totalSlots),
              child: PageView.builder(
                key: ValueKey('mobi-paged-pv-$_currentChapter'),
                controller: _viewPageController,
                scrollDirection: widget.readingMode == ReadingMode.vertical
                    ? Axis.vertical
                    : Axis.horizontal,
                itemCount: totalSlots,
                itemBuilder: (context, slot) {
                  if (hasLeading && slot == 0) {
                    final prevSlices = _getPagedSlices(
                      _currentChapter - 1,
                      availWidth,
                      availHeight,
                      themeRepo.config,
                      annotations,
                    );
                    final prevSlice = prevSlices.isNotEmpty ? prevSlices.last : null;
                    return _buildPageItem(context, _currentChapter - 1, prevSlice);
                  }
                  if (hasTrailing && slot == trailingSlot) {
                    final nextSlices = _getPagedSlices(
                      _currentChapter + 1,
                      availWidth,
                      availHeight,
                      themeRepo.config,
                      annotations,
                    );
                    final nextSlice = nextSlices.isNotEmpty ? nextSlices.first : null;
                    return _buildPageItem(context, _currentChapter + 1, nextSlice);
                  }
                  final sliceIdx = slot - leadingOffset;
                  final slice = (sliceIdx >= 0 && sliceIdx < slices.length) ? slices[sliceIdx] : null;
                  return _buildPageItem(context, _currentChapter, slice);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
