import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';

import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';

import 'package:reader_app/features/reader/controllers/epub_chapter_controller.dart';
import 'package:reader_app/features/reader/controllers/epub_tts_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';

import 'package:reader_app/features/reader/widgets/epub_continuous_viewer.dart';
import 'package:reader_app/features/reader/widgets/epub_paged_viewer.dart';
import 'package:reader_app/features/reader/widgets/epub_reader_top_bar.dart';
import 'package:reader_app/features/reader/widgets/epub_reader_bottom_controls.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';

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
  late ReaderChromeController _chromeController;
  late ReaderModeController _modeController;
  late PageController _pageController;

  ReadingMode _readingMode = ReadingMode.vertical;
  Offset? _lastDoubleTapDown;
  String _lastLoadedFontFamily = '';
  ReaderThemeRepository? _themeRepository;

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

    _ttsController = EpubTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: TtsService(),
      chapterController: _chapterController,
    );

    _chromeController = ReaderChromeController();
    _pageController = PageController(initialPage: widget.book.sectionIndex);

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
    _chapterController.dispose();
    _ttsController.dispose();
    _chromeController.dispose();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.text,
    );
    if (selected == null || selected == _readingMode) return;
    if (!mounted) return;
    
    _chapterController.saveReadingPositionForMode(_readingMode, context: context);
    setState(() {
      _readingMode = selected;
      _modeController = ReaderModeController(selected);
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

  void _showChapterList() {
    final chapters = _chapterController.chapters;
    if (chapters == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          return ListTile(
            title: Text(chapter.Title ?? 'Chapter ${index + 1}'),
            selected: index == _chapterController.currentChapterIndex,
            onTap: () {
              Navigator.pop(context);
              _chapterController.loadChapter(index, userInitiated: true);
              if (_modeController.isPagedMode && _pageController.hasClients) {
                _pageController.jumpToPage(index);
              }
            },
          );
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _chapterController,
        _ttsController,
        _chromeController,
      ]),
      builder: (context, _) {
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
                    const Icon(Icons.error_outline, size: 48, color: Colors.red), // Use Colors.red for simplicity in error screen
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
                onSelectionChanged: (value) {
                  // This could be used to trigger annotation dialog or dictionary
                },
                child: Stack(
                  children: [
                    // Reader Viewers
                    if (_modeController.isPagedMode)
                      EpubPagedViewer(
                        chapterController: _chapterController,
                        ttsController: _ttsController,
                        pageController: _pageController,
                        onToggleChrome: _chromeController.toggleChrome,
                        onTapUp: (details) => _ttsController.startTtsFromTap(
                          details,
                          modeController: _modeController,
                          context: context,
                        ),
                      )
                    else
                      EpubContinuousViewer(
                        chapterController: _chapterController,
                        ttsController: _ttsController,
                        modeController: _modeController,
                        onToggleChrome: _chromeController.toggleChrome,
                        onTapUp: (details) => _ttsController.startTtsFromTap(
                          details,
                          modeController: _modeController,
                          context: context,
                        ),
                      ),

                  // UI Overlays
                  if (_chromeController.showChrome && !_chromeController.isLocked) ...[
                    EpubReaderTopBar(
                      book: widget.book,
                      lockMode: _chromeController.isLocked,
                      showTtsControls: _ttsController.showTtsControls,
                      onBack: () => Navigator.of(context).maybePop(),
                      onToggleLock: () {
                        final isLocked = _chromeController.toggleLockMode();
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
                    if (!_ttsController.showTtsControls)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: EpubReaderBottomControls(
                          currentChapterIndex: _chapterController.currentChapterIndex,
                          totalChapters: _chapterController.chapters?.length ?? 0,
                          onLoadChapter: (index) {
                            _chapterController.loadChapter(index, userInitiated: true);
                            if (_modeController.isPagedMode && _pageController.hasClients) {
                              _pageController.jumpToPage(index);
                            }
                          },
                        ),
                      ),
                  ],

                  // TTS Controls
                  if (_ttsController.showTtsControls)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: TtsControlsSheet(
                        ttsService: _ttsController.ttsService,
                        textToSpeak: '', // Let resolveTextToSpeak handle it
                        resolveTextToSpeak: () => _ttsController.resolveTtsText(modeController: _modeController),
                        isContinuous: _ttsController.ttsContinuous,
                        isFollowMode: _ttsController.ttsFollowMode,
                        isTapToStart: _ttsController.tapToStartEnabled,
                        onContinuousChanged: _ttsController.setTtsContinuous,
                        onFollowModeChanged: _ttsController.setTtsFollowMode,
                        onTapToStartChanged: _ttsController.setTapToStartEnabled,
                        onClose: _ttsController.closeTtsControls,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
