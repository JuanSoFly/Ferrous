import 'package:flutter/material.dart';

class MobiReaderBottomControls extends StatelessWidget {
  final int currentChapterIndex;
  final int totalChapters;
  final Function(int) onLoadChapter;
  final VoidCallback? onShowChapters;

  const MobiReaderBottomControls({
    super.key,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.onLoadChapter,
    this.onShowChapters,
  });

  @override
  Widget build(BuildContext context) {
    if (totalChapters <= 1) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentChapterIndex > 0
                    ? () => onLoadChapter(currentChapterIndex - 1)
                    : null,
              ),
              InkWell(
                onTap: onShowChapters,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Text(
                    "Section ${currentChapterIndex + 1} / $totalChapters",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentChapterIndex < totalChapters - 1
                    ? () => onLoadChapter(currentChapterIndex + 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
