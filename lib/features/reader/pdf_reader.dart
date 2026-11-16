import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/services/tts_service.dart';
import 'package:ferrous/features/reader/reading_mode_sheet.dart';
import 'package:ferrous/features/reader/widgets/pdf_toc_sheet.dart';
import 'package:ferrous/features/settings/app_themes.dart';
import 'controllers/pdf_page_controller.dart';
import 'controllers/pdf_tts_controller.dart';
import 'controllers/reader_chrome_controller.dart';
import 'controllers/reader_mode_controller.dart';
import 'widgets/cbz_adaptive_background.dart';
import 'widgets/pdf_page_viewer.dart';
import 'widgets/pdf_reader_top_bar.dart';
import 'widgets/pdf_page_controls.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'tts_controls_sheet.dart';

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const PdfReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> with WidgetsBindingObserver {
  late final PdfPageController _pageController;
  late final PdfTtsController _ttsController;
  late final TtsService _ttsService;
  late final ReaderChromeController _chromeController;
  late final ReaderModeController _modeController;
  
  final TransformationController _pdfTransformController = TransformationController();
  final GlobalKey _pageImageKey = GlobalKey();

  // Floating bottom-right unlock control
  bool _showFloatingUnlock = false;
  Timer? _unlockFadeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pageController = PdfPageController(
      book: widget.book,
      repository: widget.repository,
    );

    _ttsService = TtsService();
    _ttsController = PdfTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: _ttsService,
      pageController: _pageController,
    );
    _ttsController.pdfTransformController = _pdfTransformController;

    _chromeController = ReaderChromeController();
    _modeController = ReaderModeController(widget.book.readingMode);

    _pageController.loadDocument();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeController.enterImmersiveMode();
    });
  }

  @override
  void dispose() {
    _unlockFadeTimer?.cancel();
    _cleanupTempFile();
    _pageController.dispose();
    _ttsController.dispose();
    _ttsService.dispose();
    _chromeController.exitToNormalMode();
    _chromeController.dispose();
    _pdfTransformController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      if (_pageController.isContinuousMode) {
        _pageController.saveContinuousProgress();
      } else {
        _pageController.repository.updateReadingProgress(
          widget.book.id,
          currentPage: _pageController.pageIndex,
          totalPages: _pageController.pageCount,
        );
      }
      _ttsController.saveCurrentTtsSentence();
    }
  }

  void _cleanupTempFile() {
    final resolved = _pageController.resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      unawaited(File(resolved.path).delete());
    } catch (_) {}
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _pageController.readingMode,
      formatType: ReaderFormatType.pdf,
    );
    if (selected == null || selected == _pageController.readingMode) return;
    
    _pageController.updateReadingMode(selected);
    _modeController.mode = selected;
  }

  void _openTableOfContents() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return PdfTableOfContentsSheet(
          pageController: _pageController,
          onSelectChapter: (pageIndex) {
            _pageController.jumpToPage(pageIndex);
          },
        );
      },
    );
  }

  void _handleLockedTap() {
    _unlockFadeTimer?.cancel();
    setState(() {
      _showFloatingUnlock = true;
    });

    _unlockFadeTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _showFloatingUnlock = false;
        });
      }
    });
  }

  void _unlockReader() {
    _unlockFadeTimer?.cancel();
    _chromeController.toggleLockMode();
    setState(() {
      _showFloatingUnlock = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Content layer wrapped in CbzAdaptiveBackground
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _pageController,
              builder: (context, _) {
                return CbzAdaptiveBackground(
                  colors: _pageController.currentCornerColors,
                  readingMode: _pageController.readingMode,
                  fallbackColor: isEInk ? const Color(0xFFEAE6DF) : theme.scaffoldBackgroundColor,
                  isEInk: isEInk,
                  child: PdfPageViewer(
                    pageController: _pageController,
                    ttsController: _ttsController,
                    chromeController: _chromeController,
                    modeController: _modeController,
                    transformController: _pdfTransformController,
                    pageImageKey: _pageImageKey,
                    onLockedTap: _handleLockedTap,
                  ),
                );
              },
            ),
          ),

          // Chrome layers - only rebuild when chrome, TTS controls, or page changes
          ListenableBuilder(
            listenable: Listenable.merge([_chromeController, _ttsController, _pageController]),
            builder: (context, _) {
              final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
              final showTtsControls = showChrome && _ttsController.showTtsControls;
              final showBottomControls = showChrome && !_ttsController.showTtsControls && _modeController.isPagedMode;

              return Stack(
                children: [
                  if (showChrome)
                    PdfReaderTopBar(
                      book: widget.book,
                      pageController: _pageController,
                      ttsController: _ttsController,
                      chromeController: _chromeController,
                      onShowReadingModePicker: _showReadingModePicker,
                      onOpenTableOfContents: _openTableOfContents,
                    ),
                  if (showBottomControls)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: PdfPageControls(pageController: _pageController),
                    ),
                  if (showTtsControls)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        top: false,
                        child: TtsControlsSheet(
                          ttsService: _ttsController.ttsService,
                          textToSpeak: _ttsController.currentSentenceText,
                          resolveTextToSpeak: _ttsController.resolveTtsText,
                          onStart: _ttsController.play,
                          isTextLoading: _pageController.isTextLoading,
                          emptyTextMessage: _pageController.textError ?? 'No readable text on this page.',
                          isContinuous: _ttsController.ttsContinuous,
                          onContinuousChanged: (v) => _ttsController.setTtsContinuous(v),
                          isFollowMode: _ttsController.ttsFollowMode,
                          onFollowModeChanged: (v) => _ttsController.setTtsFollowMode(v),
                          isTapToStart: _ttsController.tapToStartEnabled,
                          onTapToStartChanged: (v) => _ttsController.setTapToStartEnabled(v),
                          onStop: _ttsController.stop,
                          onPause: _ttsController.pause,
                          onClose: _ttsController.closeTtsControls,
                          highlightStyle: themeRepo.highlightStyle,
                          onHighlightStyleChanged: themeRepo.setTtsHighlightStyle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // Floating Unlock Button in bottom-right corner when locked
          if (_showFloatingUnlock && _chromeController.isLocked)
            Positioned(
              right: 24,
              bottom: 24,
              child: SafeArea(
                child: Material(
                  elevation: 6,
                  shape: const CircleBorder(),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _unlockReader,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Icon(
                        Icons.lock_open,
                        size: 28,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
