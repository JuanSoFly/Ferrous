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
import 'package:reader_app/features/reader/controllers/mobi_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/mobi_tts_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'package:reader_app/features/reader/widgets/book_background_texture.dart';
import 'package:reader_app/features/reader/widgets/mobi_continuous_viewer.dart';
import 'package:reader_app/features/reader/widgets/mobi_paged_viewer.dart';
import 'package:reader_app/features/reader/widgets/mobi_reader_top_bar.dart';
import 'package:reader_app/features/reader/widgets/mobi_reader_bottom_controls.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';
import 'package:reader_app/features/reader/widgets/tap_selection_overlay.dart';

class MobiReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const MobiReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<MobiReaderScreen> createState() => _MobiReaderScreenState();
}

class _MobiReaderScreenState extends State<MobiReaderScreen> with WidgetsBindingObserver {
  late MobiChapterController _chapterController;
  late MobiTtsController _ttsController;
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

  TapDetectionResult? _pendingTapResult;
  DateTime? _lastWordTapTime;
  TapDetectionResult? _lastWordTapResult;
  SelectedContent? _selectedContent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HyphenationHelper.init();

    _readingMode = widget.book.readingMode;
    _modeController = ReaderModeController(_readingMode);
    
    _chapterController = MobiChapterController(
      book: widget.book,
      repository: widget.repository,
    )..init();

    _chapterController.addListener(_onChapterControllerChanged);

    _ttsService = TtsService();
    _ttsController = MobiTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: _ttsService,
      chapterController: _chapterController,
    );

    _chromeController = ReaderChromeController();
    final isFirstOpen = widget.book.sectionIndex == 0 &&
        widget.book.scrollPosition == 0.0 &&
        widget.book.lastReadingSentenceStart == -1;
    _pageController = PageController(
      initialPage: isFirstOpen ? 0 : widget.book.sectionIndex + 1,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chromeController.enterImmersiveMode();
      _themeRepository = context.read<ReaderThemeRepository>();
      _themeRepository?.addListener(_onThemeChanged);
      
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
      _chapterController.saveReadingPositionForMode(_readingMode, context: context);
      _ttsController.saveCurrentTtsSentence();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!_chromeController.isLocked) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    
    if (_chromeController.isCenterTap(position, MediaQuery.of(context).size)) {
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
  }

  void _toggleAllUi() {
    _chromeController.toggleChrome();
    if (!_chromeController.showChrome) {
      _ttsController.setTtsControlsVisible(false);
    }
    if (_pendingTapResult != null) {
      setState(() => _pendingTapResult = null);
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
    
    _chapterController.saveReadingPositionForMode(_readingMode, context: context);

    final switchingToPaged = selected == ReadingMode.vertical || selected == ReadingMode.leftToRight;

    setState(() {
      _readingMode = selected;
      _modeController = ReaderModeController(selected);
      if (switchingToPaged) {
        _pageController.dispose();
        _pageController = PageController(
          initialPage: _chapterController.currentChapterIndex,
        );
      }
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ReaderSettingsSheet(),
    );
  }

  void _goToChapter(int index) {
    if (_chapterController.chapters == null) return;
    if (index < 0 || index >= _chapterController.chapters!.length) return;

    _chapterController.loadChapter(index, userInitiated: true);

    if (_modeController.isPagedMode) {
      final targetPage = index + 1;
      if (_pageController.hasClients && _pageController.page?.round() != targetPage) {
        _pageController.jumpToPage(targetPage);
      }
    }
  }

  void _showChapterList() {
    final chapters = _chapterController.chapters;
    if (chapters == null) return;

    final initialIndex = _chapterController.currentChapterIndex.clamp(0, chapters.length - 1);
    final scrollController = ScrollController(
      initialScrollOffset: (initialIndex * 56.0).clamp(0.0, double.infinity),
    );

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView.builder(
        controller: scrollController,
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          final isSelected = index == _chapterController.currentChapterIndex;
          return ListTile(
            title: Text(
              chapter.Title ?? 'Section ${index + 1}',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            trailing: isSelected
                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
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
    // Only active when TTS controls are visible and Double Tap is enabled
    if (!_ttsController.showTtsControls || !_ttsController.tapToStartEnabled) {
      if (_pendingTapResult != null) {
        setState(() => _pendingTapResult = null);
      }
      return;
    }

    final screenSize = MediaQuery.of(context).size;
    if (_chromeController.isCenterTap(details.globalPosition, screenSize)) {
      if (_pendingTapResult != null) {
        setState(() => _pendingTapResult = null);
      }
      return;
    }

    final result = _ttsController.detectWordAtTap(
      details,
      modeController: _modeController,
      context: context,
    );

    if (result == null) {
      if (_pendingTapResult != null) {
        setState(() => _pendingTapResult = null);
      }
      _lastWordTapResult = null;
      _lastWordTapTime = null;
      return;
    }

    final now = DateTime.now();
    final isDoubleTap = _lastWordTapResult != null &&
        _lastWordTapTime != null &&
        now.difference(_lastWordTapTime!) < const Duration(milliseconds: 650) &&
        _isSameTargetWord(_lastWordTapResult!, result);

    if (isDoubleTap) {
      _lastWordTapResult = null;
      _lastWordTapTime = null;
      setState(() {
        _pendingTapResult = result;
      });
    } else {
      // First tap on this word - record it and dismiss any previous overlay
      _lastWordTapResult = result;
      _lastWordTapTime = now;
      if (_pendingTapResult != null) {
        setState(() {
          _pendingTapResult = null;
        });
      }
    }
  }

  bool _isSameTargetWord(TapDetectionResult a, TapDetectionResult b) {
    if (a.chapterIndex != b.chapterIndex) return false;
    if (a.offset == b.offset) return true;
    final dist = (a.tapPosition - b.tapPosition).distance;
    if (dist < 48) return true;
    return a.word.trim().toLowerCase() == b.word.trim().toLowerCase() && dist < 120;
  }

  void _confirmTapSelection() {
    final result = _pendingTapResult;
    if (result == null) return;

    _lastWordTapResult = null;
    _lastWordTapTime = null;
    setState(() {
      _pendingTapResult = null;
    });

    _ttsController.speakFromLocation(
      chapterIndex: result.chapterIndex,
      offset: result.offset,
    );
  }

  void _cancelTapSelection() {
    _lastWordTapResult = null;
    _lastWordTapTime = null;
    setState(() {
      _pendingTapResult = null;
    });
  }

  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find in Section'),
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
                  SnackBar(content: Text(found ? 'Found "$query" in this section.' : '"$query" not found.')),
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
      int start = plainText.indexOf(selectedText);
      int end = start != -1 ? start + selectedText.length : selectedText.length;
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
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text("Error loading book:", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_chapterController.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Go Back")),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _chapterController.saveReadingPositionForMode(_readingMode, context: context);
            _ttsController.saveCurrentTtsSentence();
          }
        },
        child: GestureDetector(
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
                        ? MobiPagedViewer(
                            chapterController: _chapterController,
                            ttsController: _ttsController,
                            pageController: _pageController,
                            readingMode: _readingMode,
                            onToggleChrome: _toggleAllUi,
                            onTapUp: _handleTapUpForTts,
                          )
                        : MobiContinuousViewer(
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
                          MobiReaderTopBar(
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
                            child: MobiReaderBottomControls(
                              currentChapterIndex: _chapterController.currentChapterIndex,
                              totalChapters: _chapterController.chapters?.length ?? 0,
                              onShowChapters: _showChapterList,
                              onLoadChapter: _goToChapter,
                            ),
                          ),

                        if (_pendingTapResult != null)
                          TapSelectionOverlay(
                            word: _pendingTapResult!.word,
                            position: _pendingTapResult!.tapPosition,
                            onConfirm: _confirmTapSelection,
                            onCancel: _cancelTapSelection,
                          ),

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
                                final text = _ttsController.resolveTtsText(modeController: _modeController);
                                if (text.trim().isNotEmpty) {
                                  await _ttsController.ttsService.speak(text);
                                }
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
