import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/features/reader/widgets/book_background_texture.dart';

import 'controllers/cbz_page_controller.dart';
import 'widgets/cbz_page_viewer.dart';
import 'widgets/cbz_reader_top_bar.dart';
import 'widgets/cbz_page_controls.dart';

class CbzReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const CbzReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<CbzReaderScreen> createState() => _CbzReaderScreenState();
}

class _CbzReaderScreenState extends State<CbzReaderScreen> with WidgetsBindingObserver {
  late final CbzPageController _pageController;
  late final ReaderChromeController _chromeController;
  late ReaderModeController _modeController;
  final TransformationController _imageTransformController = TransformationController();
  bool _didRestoreInitialScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    PaintingBinding.instance.imageCache.maximumSize = 10;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

    _pageController = CbzPageController(
      book: widget.book,
      repository: widget.repository,
    );

    _chromeController = ReaderChromeController();
    _modeController = ReaderModeController(widget.book.readingMode);

    _pageController.loadDocument();
    
    _chromeController.addListener(_onChromeChanged);
    _pageController.addListener(_onPageControllerChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeController.enterImmersiveMode();
    });
  }

  @override
  void dispose() {
    _saveProgress();
    _pageController.removeListener(_onPageControllerChanged);
    _pageController.cleanupTempFile();
    _pageController.dispose();
    _chromeController.removeListener(_onChromeChanged);
    _chromeController.exitToNormalMode();
    _chromeController.dispose();
    _imageTransformController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _saveProgress() {
    if (_pageController.isContinuousMode) {
      _pageController.saveProgressImmediately();
    } else if (_pageController.pageCount > 0) {
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: _pageController.pageIndex,
        totalPages: _pageController.pageCount,
        readingMode: _pageController.readingMode,
      );
    }
    widget.book.currentPage = _pageController.pageIndex;
    widget.book.scrollPosition = _pageController.scrollPosition;
    widget.book.readingMode = _pageController.readingMode;
    widget.book.lastReadingSentenceStart = _pageController.inPageScrollOffset.round();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _saveProgress();
    }
  }

  void _onChromeChanged() {
    if (mounted) setState(() {});
  }

  void _onPageControllerChanged() {
    if (!_didRestoreInitialScroll && !_pageController.isLoading && _pageController.pageCount > 0) {
      _didRestoreInitialScroll = true;
      if (_pageController.isContinuousMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.restoreContinuousScroll();
        });
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _pageController.readingMode,
      formatType: ReaderFormatType.image,
    );
    if (!mounted || selected == null || selected == _pageController.readingMode) return;
    
    setState(() {
      _modeController.mode = selected;
    });
    _pageController.updateReadingMode(selected, context: context);
  }

  void _toggleLockModeWithFeedback() {
    final isLocked = _chromeController.toggleLockMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isLocked
              ? 'Lock mode on. Double-tap center to unlock.'
              : 'Lock mode off.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveProgress();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Content layer wrapped in physical book background
            Positioned.fill(
              child: RealBookBackground(
                textureId: themeRepo.config.paperTexture,
                showSpine: themeRepo.config.showBookSpine,
                child: CbzPageViewer(
                  pageController: _pageController,
                  chromeController: _chromeController,
                  modeController: _modeController,
                  transformController: _imageTransformController,
                ),
              ),
            ),

            // Chrome layers
            ListenableBuilder(
              listenable: _chromeController,
              builder: (context, _) {
                final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
                final showBottomControls = showChrome;

                return Stack(
                  children: [
                    if (showChrome)
                      CbzReaderTopBar(
                        book: widget.book,
                        pageController: _pageController,
                        chromeController: _chromeController,
                        onShowReadingModePicker: _showReadingModePicker,
                        onToggleLock: _toggleLockModeWithFeedback,
                      ),
                    if (showBottomControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: CbzPageControls(pageController: _pageController),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
