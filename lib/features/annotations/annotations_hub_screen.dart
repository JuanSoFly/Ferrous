import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.brush, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No annotations yet'),
          ],
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
    return InkWell(
      onTap: () {
        // Navigate to book at location
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReaderScreen(book: book),
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
                color: Color(annotation.color).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.all(4),
              child: Text(
                annotation.selectedText,
                style: const TextStyle(fontStyle: FontStyle.italic),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (annotation.note != null && annotation.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  annotation.note!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatDate(annotation.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 16),
                  onPressed: () {
                    context.read<AnnotationRepository>().deleteAnnotation(annotation.id);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}
