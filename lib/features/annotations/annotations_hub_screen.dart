import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/reader/reader_screen.dart';

class AnnotationsHubScreen extends StatefulWidget {
  const AnnotationsHubScreen({super.key});

  @override
  State<AnnotationsHubScreen> createState() => _AnnotationsHubScreenState();
}

class _AnnotationsHubScreenState extends State<AnnotationsHubScreen> {
  @override
  Widget build(BuildContext context) {
    final annotationRepo = context.watch<AnnotationRepository>();
    final bookRepo = context.read<BookRepository>();
    
    // Get all annotations
    final allAnnotations = annotationRepo.getAllAnnotations();
    
    if (allAnnotations.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.brush_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No annotations yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Highlight passages and write notes while reading. Simply press and hold any text in an e-book to add an annotation.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final bookId = grouped.keys.elementAt(index);
        final annotations = grouped[bookId]!;
        final book = bookRepo.getBook(bookId);
        
        if (book == null) return const SizedBox.shrink();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: BookCoverSmall(book: book),
                title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(book.author),
              ),
              const Divider(),
              ...annotations.map((a) => _buildAnnotationItem(context, a, book)),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildAnnotationItem(BuildContext context, Annotation annotation, Book book) {
    final theme = Theme.of(context);
    final color = Color(annotation.color);

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                annotation.selectedText,
                style: const TextStyle(fontStyle: FontStyle.italic),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (annotation.note != null && annotation.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  annotation.note!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (annotation.chapterIndex >= 0) ...[
                  Text(
                    'Chapter ${annotation.chapterIndex + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('•', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                ],
                Text(
                  _formatDate(annotation.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Edit note',
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _handleEdit(annotation),
                ),
                IconButton(
                  tooltip: 'Delete annotation',
                  icon: const Icon(Icons.delete_outline, size: 16),
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
