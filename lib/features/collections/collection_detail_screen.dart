import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/models/collection.dart';
import 'package:reader_app/core/widgets/delete_book_dialog.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/reader/reader_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  final Collection collection;

  const CollectionDetailScreen({super.key, required this.collection});

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final bookRepo = context.read<BookRepository>();
    // Re-fetch collection to get updates
    final collection = context.watch<CollectionRepository>().getCollection(widget.collection.id) ?? widget.collection;
    final theme = Theme.of(context);
    
    final books = collection.bookIds
        .map((id) => bookRepo.getBook(id))
        .whereType<Book>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(collection.name),
      ),
      body: books.isEmpty
          ? const Center(child: Text('Empty collection'))
          : ListView.builder(
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return ListTile(
                  leading: BookCoverSmall(book: book),
                  title: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Book options',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) async {
                      if (value == 'remove') {
                        await context.read<CollectionRepository>().removeBookFromCollection(collection.id, book.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Removed "${book.title}" from ${collection.name}')),
                          );
                        }
                      } else if (value == 'delete') {
                        await _confirmAndDeleteBook(context, book);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.remove_circle_outline, size: 20, color: theme.colorScheme.onSurface),
                            const SizedBox(width: 12),
                            const Text('Remove from collection'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                            const SizedBox(width: 12),
                            Text(
                              'Delete book',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onLongPress: () => _confirmAndDeleteBook(context, book),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReaderScreen(book: book),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _confirmAndDeleteBook(BuildContext context, Book book) async {
    final result = await showDeleteBookDialog(
      context: context,
      book: book,
    );

    if (result != null && result.confirmed && context.mounted) {
      final bookRepo = context.read<BookRepository>();
      final collectionRepo = context.read<CollectionRepository>();
      final annotationRepo = context.read<AnnotationRepository>();

      await collectionRepo.removeBookFromAllCollections(book.id);
      await annotationRepo.deleteAnnotationsForBook(book.id);
      await bookRepo.deleteBook(book.id, deleteFile: result.deletePhysicalFile);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${book.title}" from library'),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }
}
