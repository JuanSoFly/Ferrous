import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';
import '../controllers/cbz_page_controller.dart';
import '../controllers/reader_chrome_controller.dart';

class CbzReaderTopBar extends StatelessWidget {
  final Book book;
  final CbzPageController pageController;
  final ReaderChromeController chromeController;
  final VoidCallback onShowReadingModePicker;
  final VoidCallback onToggleLock;

  const CbzReaderTopBar({
    super.key,
    required this.book,
    required this.pageController,
    required this.chromeController,
    required this.onShowReadingModePicker,
    required this.onToggleLock,
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
          child: ListenableBuilder(
            listenable: pageController,
            builder: (context, _) {
              return Padding(
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
                    if (pageController.pageCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text("${pageController.pageIndex + 1} / ${pageController.pageCount}"),
                      ),
                    IconButton(
                      icon: Icon(chromeController.isLocked ? Icons.lock : Icons.lock_open),
                      tooltip: chromeController.isLocked ? 'Unlock' : 'Lock',
                      onPressed: onToggleLock,
                    ),
                    IconButton(
                      icon: const Icon(Icons.view_carousel),
                      tooltip: 'Reading mode',
                      onPressed: onShowReadingModePicker,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
