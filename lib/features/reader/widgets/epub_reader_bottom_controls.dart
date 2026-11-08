import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class EpubReaderBottomControls extends StatelessWidget {
  final int currentChapterIndex;
  final int totalChapters;
  final Function(int) onLoadChapter;
  final VoidCallback? onShowChapters;

  const EpubReaderBottomControls({
    super.key,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.onLoadChapter,
    this.onShowChapters,
  });

  @override
  Widget build(BuildContext context) {
    if (totalChapters <= 1) return const SizedBox.shrink();

    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    return SafeArea(
      top: false,
      child: Material(
        color: isEInk
            ? const Color(0xFFEAE6DF)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        elevation: 0,
        child: Container(
          decoration: isEInk
              ? const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF9E9A90), width: 1.0),
                  ),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  color: isEInk ? const Color(0xFF1A1A18) : null,
                ),
                onPressed: currentChapterIndex > 0
                    ? () => onLoadChapter(currentChapterIndex - 1)
                    : null,
              ),
              InkWell(
                onTap: onShowChapters,
                borderRadius: BorderRadius.circular(isEInk ? 2 : 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Text(
                    "Chapter ${currentChapterIndex + 1} / $totalChapters",
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: const Color(0xFF1A1A18),
                          )
                        : Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: isEInk ? const Color(0xFF1A1A18) : null,
                ),
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
