import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/reader/controllers/reader_chrome_controller.dart';
import 'package:reader_app/features/reader/controllers/reader_mode_controller.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // CRITICAL: Limit image cache size to prevent OOM
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeController.enterImmersiveMode();
      _pageController.restoreContinuousScroll();
    });
  }

  @override
  void dispose() {
    _pageController.cleanupTempFile();
    _pageController.dispose();
    _chromeController.removeListener(_onChromeChanged);
    _chromeController.exitToNormalMode();
    _chromeController.dispose();
    _imageTransformController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_pageController.isContinuousMode) {
        _pageController.saveContinuousProgress();
      } else {
        widget.repository.updateReadingProgress(
          widget.book.id,
          currentPage: _pageController.pageIndex,
          totalPages: _pageController.pageCount,
        );
      }
    }
  }

  void _onChromeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _pageController.readingMode,
      formatType: ReaderFormatType.image,
    );
    if (selected == null || selected == _pageController.readingMode) return;
    
    _pageController.updateReadingMode(selected);
    _modeController.mode = selected;
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
    return Scaffold(
      body: Stack(
        children: [
          // Content layer
          Positioned.fill(
            child: CbzPageViewer(
              pageController: _pageController,
              chromeController: _chromeController,
              modeController: _modeController,
              transformController: _imageTransformController,
            ),
          ),

          // Chrome layers
          ListenableBuilder(
            listenable: _chromeController,
            builder: (context, _) {
              final showChrome = _chromeController.showChrome && !_chromeController.isLocked;
              final showBottomControls = showChrome && _modeController.isPagedMode;

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
    );
  }
}
