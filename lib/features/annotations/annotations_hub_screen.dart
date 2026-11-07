import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class AnnotationsHubScreen extends StatefulWidget {
  const AnnotationsHubScreen({super.key});

  @override
  State<AnnotationsHubScreen> createState() => _AnnotationsHubScreenState();
}

class _AnnotationsHubScreenState extends State<AnnotationsHubScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final annotationRepo = context.watch<AnnotationRepository>();
    final bookRepo = context.read<BookRepository>();
    
    // Get all annotations
    final allAnnotations = annotationRepo.getAllAnnotations();
    
    if (allAnnotations.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Annotations'),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      size: 38,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No annotations yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Highlight passages and write notes while reading. Simply press and hold any text in an e-book to add an annotation.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // Group by book ID
    final Map<String, List<Annotation>> grouped = {};
    for (var a in allAnnotations) {
      if (!grouped.containsKey(a.bookId)) {
        grouped[a.bookId] = [];
      }
      grouped[a.bookId]!.add(a);
    }
    
    final isDark = theme.brightness == Brightness.dark;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    final borderColor = isEInk
        ? const Color(0xFF9E9A90)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotations'),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: grouped.keys.length,
          itemBuilder: (context, index) {
            final bookId = grouped.keys.elementAt(index);
            final annotations = grouped[bookId]!;
            final book = bookRepo.getBook(bookId);
            
            if (book == null) return const SizedBox.shrink();
            
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 16),
              clipBehavior: Clip.antiAlias,
              color: isEInk ? const Color(0xFFEAE6DF) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
                side: BorderSide(color: borderColor, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.xs),
                          child: SizedBox(
                            width: 38,
                            height: 52,
                            child: BookCoverSmall(book: book),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                style: isEInk
                                    ? GoogleFonts.robotoSlab(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        letterSpacing: -0.2,
                                        color: const Color(0xFF1A1A18),
                                      )
                                    : theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        letterSpacing: -0.2,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                book.author,
                                style: isEInk
                                    ? const TextStyle(
                                        color: Color(0xFF3D3C38),
                                        fontSize: 13,
                                      )
                                    : theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                        fontSize: 13,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.pill),
                            border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                          ),
                          child: Text(
                            '${annotations.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: borderColor,
                  ),
                  ...annotations.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final a = entry.value;
                    return Column(
                      children: [
                        if (idx > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 16,
                            endIndent: 16,
                            color: borderColor,
                          ),
                        _buildAnnotationItem(context, a, book, isEInk: isEInk),
                      ],
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildAnnotationItem(BuildContext context, Annotation annotation, Book book, {required bool isEInk}) {
    final theme = Theme.of(context);
    final highlightColor = annotation.color != 0
        ? Color(annotation.color)
        : theme.colorScheme.primary;

    return InkWell(
      onTap: () {
        // Navigate to book at the exact chapter/section of this annotation
        final targetBook = book.copyWith(
          sectionIndex: annotation.chapterIndex,
          currentPage: annotation.chapterIndex,
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReaderScreen(book: targetBook),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: isEInk ? const Color(0xFFE0DCD3) : highlightColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
                border: isEInk
                    ? const Border(
                        left: BorderSide(color: Color(0xFF1A1A18), width: 3.0),
                        top: BorderSide(color: Color(0xFF9E9A90), width: 1.0),
                        right: BorderSide(color: Color(0xFF9E9A90), width: 1.0),
                        bottom: BorderSide(color: Color(0xFF9E9A90), width: 1.0),
                      )
                    : Border(
                        left: BorderSide(color: highlightColor, width: 3.5),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                annotation.selectedText,
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                        color: const Color(0xFF1A1A18),
                      )
                    : theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                      ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (annotation.note != null && annotation.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        annotation.note!,
                        style: isEInk
                            ? GoogleFonts.robotoSlab(
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1A1A18),
                              )
                            : theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (annotation.chapterIndex >= 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.xs),
                      border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                    ),
                    child: Text(
                      'Chapter ${annotation.chapterIndex + 1}',
                      style: TextStyle(
                        color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _formatDate(annotation.createdAt),
                  style: isEInk
                      ? const TextStyle(
                          color: Color(0xFF3D3C38),
                          fontSize: 12,
                        )
                      : theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit note',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: const EdgeInsets.all(10),
                  splashRadius: 20,
                  onPressed: () => _handleEdit(annotation),
                ),
                IconButton(
                  tooltip: 'Delete annotation',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.error,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: const EdgeInsets.all(10),
                  splashRadius: 20,
                  onPressed: () {
                    context.read<AnnotationRepository>().deleteAnnotation(annotation.id);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEdit(Annotation annotation) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AnnotationDialog(
        selectedText: annotation.selectedText,
        initialNote: annotation.note,
        initialColor: annotation.color,
      ),
    );

    if (result != null && mounted) {
      final updatedNote = (result['note'] as String?)?.trim();
      final updatedColor = result['color'] as int? ?? annotation.color;

      final updated = annotation.copyWith(
        note: updatedNote != null && updatedNote.isNotEmpty ? updatedNote : null,
        color: updatedColor,
      );

      await context.read<AnnotationRepository>().updateAnnotation(updated);
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
