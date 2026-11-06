import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/app_constants.dart';
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.collections_bookmark_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No books in this collection',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Long-press any book in your library and select "Add to Collection" to add books here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: books.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 56,
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                    ),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: BookCoverSmall(book: book),
                        title: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: Text(
                          book.author.isNotEmpty ? book.author : 'Unknown Author',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          tooltip: 'Book options',
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
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
                        onLongPress: () {
                          HapticFeedback.lightImpact();
                          _confirmAndDeleteBook(context, book);
                        },
                        onTap: () {
                          HapticFeedback.selectionClick();
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
                ),
              ],
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
