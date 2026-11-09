import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'package:reader_app/features/reader/widgets/book_background_texture.dart';
import 'package:reader_app/features/reader/widgets/epub_continuous_viewer.dart';
import 'package:reader_app/features/reader/widgets/epub_paged_viewer.dart';
import 'package:reader_app/features/reader/widgets/epub_reader_top_bar.dart';
import 'package:reader_app/features/reader/widgets/epub_reader_bottom_controls.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';
import 'package:reader_app/features/reader/widgets/tap_selection_overlay.dart';
import 'package:reader_app/features/reader/widgets/reader_error_view.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class EpubReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const EpubReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> with WidgetsBindingObserver {
  late EpubChapterController _chapterController;
  late EpubTtsController _ttsController;
  late final TtsService _ttsService;
  late ReaderChromeController _chromeController;
  late ReaderModeController _modeController;
  late PageController _pageController;

  ReadingMode _readingMode = ReadingMode.leftToRight;
  Offset? _lastDoubleTapDown;
  String _lastLoadedFontFamily = '';
  ReaderThemeRepository? _themeRepository;
  bool _hasRestoredPosition = false;
  bool _wasLoading = true;
  String? _lastError;
  int _lastChapterIndex = -1;

  // Tap-to-start confirmation state
  TapDetectionResult? _pendingTapResult;
  SelectedContent? _selectedContent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HyphenationHelper.init();

    _readingMode = widget.book.readingMode;
    _modeController = ReaderModeController(_readingMode);
    
    _chapterController = EpubChapterController(
      book: widget.book,
      repository: widget.repository,
    )..init();

    // Listen for loading completion to restore reading position
    _chapterController.addListener(_onChapterControllerChanged);

    _ttsService = TtsService();
    _ttsController = EpubTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: _ttsService,
      chapterController: _chapterController,
    );

    _chromeController = ReaderChromeController();
    final initialChapter = widget.book.sectionIndex.clamp(0, double.maxFinite.toInt());
    _pageController = PageController(
      initialPage: initialChapter,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chromeController.enterImmersiveMode();
      _themeRepository = context.read<ReaderThemeRepository>();
      _themeRepository?.addListener(_onThemeChanged);
      
      // Initial font preload
      final initialFont = _themeRepository?.config.fontFamily ?? '';
      if (initialFont.isNotEmpty) {
        _lastLoadedFontFamily = initialFont;
        _preloadFont(initialFont);
      }
    });
  }

  @override
  void dispose() {
    _themeRepository?.removeListener(_onThemeChanged);
    _chapterController.removeListener(_onChapterControllerChanged);
    _chapterController.dispose();
    _ttsController.dispose();
    _ttsService.dispose();
    _chromeController.dispose();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onChapterControllerChanged() {
    if (!mounted) return;
    final isLoadingChanged = _chapterController.isLoading != _wasLoading;
    final errorChanged = _chapterController.error != _lastError;
    final chapterChanged = _chapterController.currentChapterIndex != _lastChapterIndex;

    if (isLoadingChanged || errorChanged || chapterChanged) {
      _wasLoading = _chapterController.isLoading;
      _lastError = _chapterController.error;
      _lastChapterIndex = _chapterController.currentChapterIndex;
      setState(() {});
    }
    if (!_chapterController.isLoading && !_hasRestoredPosition) {
      _hasRestoredPosition = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _chapterController.restoreReadingPosition(_readingMode);
        }
      });
    }
  }

  void _onThemeChanged() {
    final newFontFamily = _themeRepository?.config.fontFamily ?? '';
    if (newFontFamily.isNotEmpty && newFontFamily != _lastLoadedFontFamily) {
      _lastLoadedFontFamily = newFontFamily;
      _preloadFont(newFontFamily).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _preloadFont(String fontFamily) async {
    try {
      GoogleFonts.getFont(fontFamily);
      await GoogleFonts.pendingFonts();
    } catch (e) {
      debugPrint('Failed to preload font $fontFamily: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _chapterController.saveReadingPositionForMode(_readingMode, refreshChapter: false);
      _ttsController.saveCurrentTtsSentence();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    final position = _lastDoubleTapDown;
    if (position == null) return;
    final screenSize = MediaQuery.of(context).size;

    // 1. If locked, double tap center unlocks
    if (_chromeController.isLocked) {
      if (_chromeController.isCenterTap(position, screenSize)) {
        final isLocked = _chromeController.toggleLockMode();
        if (isLocked) {
          _ttsController.setTtsControlsVisible(false);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isLocked ? 'Lock mode on. Double-tap center to unlock.' : 'Lock mode off.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      return;
    }

    // 2. Normal reading: double tap on a word triggers the "read from" toggle
    if (_ttsController.tapToStartEnabled) {
      final result = _ttsController.detectWordAtTap(
        position: position,
        modeController: _modeController,
        context: context,
      );
      if (result != null) {
        setState(() {
          _pendingTapResult = result;
        });
      } else if (_pendingTapResult != null) {
        setState(() {
          _pendingTapResult = null;
        });
      }
    }
  }

  /// Toggle reader chrome. TTS controls are closed when hiding chrome
  /// and remain hidden by default until the user explicitly taps the TTS icon.
  void _toggleAllUi() {
    if (_pendingTapResult != null) {
      setState(() => _pendingTapResult = null);
      return;
    }
    _chromeController.toggleChrome();
    if (!_chromeController.showChrome) {
      _ttsController.setTtsControlsVisible(false);
    }
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.text,
    );
    if (selected == null || selected == _readingMode) return;
    if (!mounted) return;
    
    final targetChapter = _chapterController.currentChapterIndex;
    _chapterController.startModeTransition();
    _chapterController.saveReadingPositionForMode(_readingMode, refreshChapter: false);

    final switchingToPaged = selected == ReadingMode.vertical || selected == ReadingMode.leftToRight;

    if (switchingToPaged) {
      _chapterController.prepareForPagedMode(targetChapter);
      final targetPage = targetChapter;
      if (!_pageController.hasClients) {
        _pageController.dispose();
        _pageController = PageController(initialPage: targetPage);
      } else if (_pageController.page?.round() != targetPage) {
        _pageController.jumpToPage(targetPage);
      }
    } else {
      _chapterController.prepareForContinuousMode(targetChapter);
    }

    setState(() {
      _readingMode = selected;
      _modeController = ReaderModeController(selected);
      widget.book.readingMode = selected;
      _chapterController.book.readingMode = selected;
    });

    unawaited(widget.repository.updateReadingProgress(
      widget.book.id,
      readingMode: selected,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chapterController.restoreReadingPosition(_readingMode);
    });
  }

  void _showSettingsSheet() {
    AppTheme? currentTheme;
    try {
      currentTheme = context.read<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: isEInk ? Colors.transparent : null,
      builder: (context) => const ReaderSettingsSheet(),
    );
  }

  void _goToChapter(int index) {
    if (_chapterController.chapters == null) return;
    if (index < 0 || index >= _chapterController.chapters!.length) return;

    _chapterController.loadChapter(index, userInitiated: true);

    if (_modeController.isPagedMode) {
      final targetPage = index;
      if (_pageController.hasClients && _pageController.page?.round() != targetPage) {
        _pageController.jumpToPage(targetPage);
      }
    } else {
      _chapterController.scrollToChapter(index);
    }
  }

  void _showChapterList() {
    final chapters = _chapterController.chapters;
    if (chapters == null) return;

    final initialIndex = _chapterController.currentChapterIndex.clamp(0, chapters.length - 1);
    final scrollController = ScrollController(
      initialScrollOffset: (initialIndex * 56.0).clamp(0.0, double.infinity),
    );

    AppTheme? currentTheme;
    try {
      currentTheme = context.read<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
      shape: isEInk
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
              side: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
            )
          : null,
      builder: (context) => ListView.separated(
        controller: scrollController,
        itemCount: chapters.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: isEInk ? const Color(0xFFC2BEB4) : Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          final isSelected = index == _chapterController.currentChapterIndex;
          return ListTile(
            title: Text(
              chapter.Title ?? 'Chapter ${index + 1}',
              style: isEInk
                  ? GoogleFonts.robotoSlab(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: const Color(0xFF1A1A18),
                      fontSize: 14.0,
                    )
                  : TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
            ),
            selected: isSelected,
            selectedTileColor: isEInk
                ? const Color(0xFFE0DCD3)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            trailing: isSelected
                ? Icon(Icons.check, color: isEInk ? const Color(0xFF1A1A18) : Theme.of(context).colorScheme.primary)
                : null,
            onTap: () {
              Navigator.pop(context);
              _goToChapter(index);
            },
          );
        },
      ),
    );
  }

  void _handleTapUpForTts(TapUpDetails details) {
    if (_pendingTapResult != null) {
      setState(() => _pendingTapResult = null);
    }
  }

  /// Confirm the pending tap selection and start TTS.
  void _confirmTapSelection() {
    final result = _pendingTapResult;
    if (result == null) return;

    setState(() {
      _pendingTapResult = null;
    });

    _ttsController.speakFromLocation(
      chapterIndex: result.chapterIndex,
      offset: result.offset,
    );
  }

  /// Cancel the pending tap selection.
  void _cancelTapSelection() {
    setState(() {
      _pendingTapResult = null;
    });
  }

  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find in Chapter'),
        content: TextField(
          controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text to find...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final query = searchController.text.trim();
              Navigator.pop(ctx);
              if (query.isNotEmpty) {
                final txt = _chapterController.currentPlainText;
                final found = txt.toLowerCase().contains(query.toLowerCase());
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(found ? 'Found "$query" in this chapter.' : '"$query" not found.')),
                );
              }
            },
            child: const Text('Find'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAnnotationDialog(String selectedText) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AnnotationDialog(selectedText: selectedText),
    );

    if (result != null && mounted) {
      final note = (result['note'] as String?)?.trim();
      final color = result['color'] as int? ?? 0xFFFFF176;

      final plainText = _chapterController.currentPlainText;
      final cleanSelected = selectedText.replaceAll('\u00AD', '');
      int start = plainText.indexOf(cleanSelected);
      if (start == -1) start = plainText.indexOf(selectedText);
      int end = start != -1 ? start + cleanSelected.length : cleanSelected.length;
      if (start == -1) start = 0;

      final annotation = Annotation(
        id: const Uuid().v4(),
        bookId: widget.book.id,
        selectedText: selectedText,
        note: note != null && note.isNotEmpty ? note : null,
        chapterIndex: _chapterController.currentChapterIndex,
        startOffset: start,
        endOffset: end,
        color: color,
        createdAt: DateTime.now(),
      );

      await context.read<AnnotationRepository>().addAnnotation(annotation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Annotation saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();

    if (_chapterController.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_chapterController.error != null) {
      final currentTheme = context.watch<AppTheme?>();
      final isEInk = currentTheme == AppTheme.eInk;
      return ReaderErrorView(
        formatTitle: 'EPUB',
        error: _chapterController.error!,
        isEInk: isEInk,
      );
    }

    return Scaffold(
      body: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _chapterController.saveReadingPositionForMode(_readingMode, refreshChapter: false);
            _ttsController.saveCurrentTtsSentence();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: SelectionArea(
            onSelectionChanged: (content) {
              _selectedContent = content;
            },
            contextMenuBuilder: (context, selectableRegionState) {
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: selectableRegionState.contextMenuAnchors,
                buttonItems: [
                  ContextMenuButtonItem(
                    label: 'Annotate',
                    onPressed: () {
                      final text = _selectedContent?.plainText.trim() ?? '';
                      selectableRegionState.hideToolbar();
                      if (text.isNotEmpty) {
                        _showAnnotationDialog(text);
                      }
                    },
                  ),
                  ...selectableRegionState.contextMenuButtonItems,
                ],
              );
            },
            child: Stack(
              children: [
                // Reader Viewers wrapped in physical book background (NOT rebuilt on chrome/tts/chapter ticks!)
                Positioned.fill(
                  child: RealBookBackground(
                    textureId: themeRepo.config.paperTexture,
                    showSpine: themeRepo.config.showBookSpine,
                    child: _modeController.isPagedMode
                        ? EpubPagedViewer(
                            chapterController: _chapterController,
                            ttsController: _ttsController,
                            pageController: _pageController,
                            readingMode: _readingMode,
                            onToggleChrome: _toggleAllUi,
                            onTapUp: _handleTapUpForTts,
                          )
                        : EpubContinuousViewer(
                            chapterController: _chapterController,
                            ttsController: _ttsController,
                            modeController: _modeController,
                            onToggleChrome: _toggleAllUi,
                            onTapUp: _handleTapUpForTts,
                          ),
                  ),
                ),

                // Chrome and HUD layers - only rebuild when chrome, TTS controls, or chapter changes
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _chapterController,
                    _ttsController,
                    _chromeController,
                  ]),
                  builder: (context, _) {
                    final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
                    final showTtsControls = showChrome && _ttsController.showTtsControls;
                    final showBottomControls = showChrome && !_ttsController.showTtsControls;

                    return Stack(
                      children: [
                        if (showChrome)
                          EpubReaderTopBar(
                            book: widget.book,
                            lockMode: _chromeController.isLocked,
                            showTtsControls: _ttsController.showTtsControls,
                            onBack: () => Navigator.of(context).maybePop(),
                            onToggleLock: () {
                              final isLocked = _chromeController.toggleLockMode();
                              if (isLocked) {
                                _ttsController.setTtsControlsVisible(false);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isLocked ? 'Lock mode on.' : 'Lock mode off.')),
                              );
                            },
                            onShowSettings: _showSettingsSheet,
                            onShowReadingMode: _showReadingModePicker,
                            onToggleTts: () => _ttsController.toggleTts(modeController: _modeController),
                            onShowSearch: _showSearchDialog,
                            onShowChapters: _showChapterList,
                          ),
                        if (showBottomControls)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: EpubReaderBottomControls(
                              currentChapterIndex: _chapterController.currentChapterIndex,
                              totalChapters: _chapterController.chapters?.length ?? 0,
                              onShowChapters: _showChapterList,
                              onLoadChapter: _goToChapter,
                            ),
                          ),

                        // Tap Selection Overlay
                        if (_pendingTapResult != null)
                          TapSelectionOverlay(
                            word: _pendingTapResult!.word,
                            position: _pendingTapResult!.tapPosition,
                            onConfirm: _confirmTapSelection,
                            onCancel: _cancelTapSelection,
                          ),

                        // TTS Controls
                        if (showTtsControls)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: TtsControlsSheet(
                              ttsService: _ttsController.ttsService,
                              textToSpeak: '', 
                              resolveTextToSpeak: () => _ttsController.resolveTtsText(modeController: _modeController),
                              onStart: () async {
                                await _ttsController.startPlayback(modeController: _modeController);
                              },
                              isContinuous: _ttsController.ttsContinuous,
                              isFollowMode: _ttsController.ttsFollowMode,
                              isTapToStart: _ttsController.tapToStartEnabled,
                              onContinuousChanged: _ttsController.setTtsContinuous,
                              onFollowModeChanged: _ttsController.setTtsFollowMode,
                              onTapToStartChanged: _ttsController.setTapToStartEnabled,
                              onClose: _ttsController.closeTtsControls,
                              highlightStyle: themeRepo.highlightStyle,
                              onHighlightStyleChanged: themeRepo.setTtsHighlightStyle,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
