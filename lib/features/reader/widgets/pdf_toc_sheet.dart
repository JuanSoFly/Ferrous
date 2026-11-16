import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/features/settings/app_themes.dart';
import '../controllers/pdf_page_controller.dart';
import '../models/pdf_chapter.dart';

class PdfTableOfContentsSheet extends StatelessWidget {
  final PdfPageController pageController;
  final ValueChanged<int> onSelectChapter;

  const PdfTableOfContentsSheet({
    super.key,
    required this.pageController,
    required this.onSelectChapter,
  });

  @override
  Widget build(BuildContext context) {
    AppTheme? currentTheme;
    try {
      currentTheme = context.read<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.75,
      child: Material(
        color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface,
        shape: isEInk
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                side: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
              )
            : const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted,
                    size: 20,
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Table of Contents',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A18),
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: isEInk ? 1.5 : 0.5,
              color: isEInk ? const Color(0xFF1A1A18) : theme.dividerColor.withValues(alpha: 0.2),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: pageController,
                builder: (context, _) {
                  if (pageController.isLoadingChapters) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading chapters...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isEInk ? const Color(0xFF4A4945) : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final chapters = pageController.chapters;
                  if (chapters.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'No outline or chapters detected in this PDF.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isEInk
                                ? const Color(0xFF4A4945)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  final currentIndex = _findCurrentChapterIndex(chapters, pageController.pageIndex);
                  final scrollController = ScrollController(
                    initialScrollOffset: currentIndex >= 0
                        ? (currentIndex * 56.0).clamp(0.0, double.infinity)
                        : 0.0,
                  );

                  return ListView.separated(
                    controller: scrollController,
                    itemCount: chapters.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: isEInk
                          ? const Color(0xFFC2BEB4)
                          : theme.dividerColor.withValues(alpha: 0.15),
                    ),
                    itemBuilder: (context, index) {
                      final chapter = chapters[index];
                      final isSelected = index == currentIndex;

                      return ListTile(
                        contentPadding: EdgeInsets.only(
                          left: 20.0 + (chapter.depth * 16.0),
                          right: 20.0,
                        ),
                        title: Text(
                          chapter.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: const Color(0xFF1A1A18),
                                  fontSize: 14.0,
                                )
                              : TextStyle(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Page ${chapter.pageIndex + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isEInk
                                    ? const Color(0xFF4A4945)
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check,
                                size: 18,
                                color: isEInk
                                    ? const Color(0xFF1A1A18)
                                    : theme.colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        selected: isSelected,
                        selectedTileColor: isEInk
                            ? const Color(0xFFE0DCD3)
                            : theme.colorScheme.primary.withValues(alpha: 0.10),
                        onTap: () {
                          Navigator.pop(context);
                          onSelectChapter(chapter.pageIndex);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _findCurrentChapterIndex(List<PdfChapter> chapters, int currentPage) {
    if (chapters.isEmpty) return -1;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (chapters[i].pageIndex <= currentPage) {
        return i;
      }
    }
    return 0;
  }
}
