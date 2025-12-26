import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';
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

    _ttsController = PdfTtsController(
      book: widget.book,
      repository: widget.repository,
      ttsService: TtsService(),
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
    _cleanupTempFile();
    _pageController.dispose();
    _ttsController.dispose();
    _chromeController.exitToNormalMode();
    _chromeController.dispose();
    _pdfTransformController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _pageController.repository.updateReadingProgress(
        widget.book.id,
        currentPage: _pageController.pageIndex,
        totalPages: _pageController.pageCount,
      );
      _ttsController.saveCurrentTtsSentence();
    }
  }

  void _cleanupTempFile() {
    final resolved = _pageController.resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      File(resolved.path).deleteSync();
    } catch (_) {}
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _modeController.mode,
      formatType: ReaderFormatType.pdf,
    );
    if (selected == null || selected == _modeController.mode) return;
    
    // Note: Re-initializing the screen or controller might be needed if reading mode changes fundamentally
    // For now we just update DB. In a real app we might want to restart the reader with new mode.
    unawaited(widget.repository.updateReadingProgress(widget.book.id, readingMode: selected));
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Reading mode updated. Re-open book to apply changes.')),
       );
    }
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
          onListenFromHere: (text) {
            final trimmed = text.trim();
            if (trimmed.isEmpty) return;

            // In our new architecture, ttsController handles this
            _ttsController.toggleTts(); // Ensure it's showing
            // Actually let's refine this to start speaking immediately
            _ttsController.startSpeakingOverride(trimmed);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Chrome layers - only rebuild when chrome or TTS controls visibility changes
          ListenableBuilder(
            listenable: Listenable.merge([_chromeController, _ttsController]),
            builder: (context, _) {
              final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
              final showTtsControls = showChrome && _ttsController.showTtsControls;
              final showBottomControls = showChrome && !_ttsController.showTtsControls;

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
                          textToSpeak: _pageController.currentPageText,
                          resolveTextToSpeak: _ttsController.resolveTtsText,
                          isTextLoading: _pageController.isTextLoading,
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
