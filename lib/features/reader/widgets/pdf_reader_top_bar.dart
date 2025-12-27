import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import '../controllers/pdf_page_controller.dart';
import '../controllers/pdf_tts_controller.dart';
import '../controllers/reader_chrome_controller.dart';

class PdfReaderTopBar extends StatelessWidget {
  final Book book;
  final PdfPageController pageController;
  final PdfTtsController ttsController;
  final ReaderChromeController chromeController;
  final VoidCallback onShowReadingModePicker;
  final VoidCallback onOpenTextPicker;

  const PdfReaderTopBar({
    super.key,
    required this.book,
    required this.pageController,
    required this.ttsController,
    required this.chromeController,
    required this.onShowReadingModePicker,
    required this.onOpenTextPicker,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(chromeController.isLocked ? Icons.lock : Icons.lock_open),
                  tooltip: chromeController.isLocked ? 'Unlock' : 'Lock',
                  onPressed: () => chromeController.toggleLockMode(),
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: onShowReadingModePicker,
                ),
                IconButton(
                  icon: Icon(ttsController.showTtsControls ? Icons.volume_off : Icons.volume_up),
                  tooltip: 'Listen',
                  onPressed: () => ttsController.toggleTts(),
                ),
                IconButton(
                  icon: const Icon(Icons.text_snippet),
                  tooltip: 'Text view',
                  onPressed: onOpenTextPicker,
                ),
                IconButton(
                  icon: Icon(pageController.autoCrop ? Icons.crop : Icons.crop_free),
                  tooltip: pageController.autoCrop ? 'Disable Auto-Crop' : 'Enable Auto-Crop',
                  onPressed: () => pageController.setAutoCrop(!pageController.autoCrop),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
