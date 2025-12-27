import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';

class EpubReaderTopBar extends StatelessWidget {
  final Book book;
  final bool lockMode;
  final bool showTtsControls;
  final VoidCallback onBack;
  final VoidCallback onToggleLock;
  final VoidCallback onShowSettings;
  final VoidCallback onShowReadingMode;
  final VoidCallback onToggleTts;
  final VoidCallback onShowSearch;
  final VoidCallback onShowChapters;

  const EpubReaderTopBar({
    super.key,
    required this.book,
    required this.lockMode,
    required this.showTtsControls,
    required this.onBack,
    required this.onToggleLock,
    required this.onShowSettings,
    required this.onShowReadingMode,
    required this.onToggleTts,
    required this.onShowSearch,
    required this.onShowChapters,
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
                  onPressed: onBack,
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
                  icon: Icon(lockMode ? Icons.lock : Icons.lock_open),
                  tooltip: lockMode ? 'Unlock' : 'Lock',
                  onPressed: onToggleLock,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: onShowSettings,
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: onShowReadingMode,
                ),
                IconButton(
                  icon: Icon(showTtsControls ? Icons.volume_off : Icons.volume_up),
                  tooltip: 'Listen',
                  onPressed: onToggleTts,
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Find in chapter',
                  onPressed: onShowSearch,
                ),
                IconButton(
                  icon: const Icon(Icons.list),
                  tooltip: 'Chapters',
                  onPressed: onShowChapters,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
