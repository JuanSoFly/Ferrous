import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/pdf_text_picker_sheet.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'controllers/pdf_page_controller.dart';
import 'controllers/pdf_tts_controller.dart';
import 'controllers/reader_chrome_controller.dart';
import 'controllers/reader_mode_controller.dart';
import 'widgets/pdf_page_viewer.dart';
import 'widgets/pdf_reader_top_bar.dart';
import 'widgets/pdf_page_controls.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
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
      _pageController.restoreContinuousScroll();
    });
  }

  @override
  void dispose() {
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

  void _openTextPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return PdfTextPickerSheet(
          pageIndex: _pageController.pageIndex,
          pageCount: _pageController.pageCount <= 0 ? 1 : _pageController.pageCount,
          loadText: () async {
            await _pageController.loadPageText(_pageController.pageIndex);
            return _pageController.currentPageText;
          },
          onListenFromHere: (text) async {
            final trimmed = text.trim();
            if (trimmed.isEmpty) return;
            // Show TTS controls if not already visible
            if (!_ttsController.showTtsControls) {
              await _ttsController.toggleTts();
            }
            await _ttsController.startSpeakingOverride(trimmed);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    return Scaffold(
      body: Stack(
        children: [
          // Content layer - only rebuilds when page or TTS overlay needs update
          Positioned.fill(
            child: PdfPageViewer(
              pageController: _pageController,
              ttsController: _ttsController,
              chromeController: _chromeController,
              modeController: _modeController,
              transformController: _pdfTransformController,
              pageImageKey: _pageImageKey,
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
                      onOpenTextPicker: _openTextPicker,
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
                          textToSpeak: _ttsController.documentText?.fullText ?? _pageController.currentPageText,
                          resolveTextToSpeak: _ttsController.resolveTtsText,
                          onStart: () async {
                            // resolveTtsText also sets the base offset internally
                            final text = _ttsController.resolveTtsText();
                            if (text.trim().isNotEmpty) {
                              await _ttsController.ttsService.speak(text);
                            }
                          },
                          isTextLoading: _ttsController.documentTextLoading || _pageController.isTextLoading,
                          emptyTextMessage: _pageController.textError ?? 'No readable text on this page.',
                          isContinuous: _ttsController.ttsContinuous,
                          onContinuousChanged: (v) => _ttsController.setTtsContinuous(v),
                          isFollowMode: _ttsController.ttsFollowMode,
                          onFollowModeChanged: (v) => _ttsController.setTtsFollowMode(v),
                          isTapToStart: _ttsController.tapToStartEnabled,
                          onTapToStartChanged: (v) => _ttsController.setTapToStartEnabled(v),
                          onStop: _ttsController.saveCurrentTtsSentence,
                          onPause: _ttsController.saveCurrentTtsSentence,
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
        ],
      ),
    );
  }
}
