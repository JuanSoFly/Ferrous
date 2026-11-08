import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:reader_app/features/settings/app_themes.dart';

// ==========================================
// KINDLE THREE-DOT ACTION BUTTON & POPUP MENU
// ==========================================

class _KindleActionDotsButton extends StatefulWidget {
  final Future<void> Function(String value) onSelected;
  final ThemeData theme;

  const _KindleActionDotsButton({
    required this.onSelected,
    required this.theme,
  });

  @override
  State<_KindleActionDotsButton> createState() => _KindleActionDotsButtonState();
}

class _KindleActionDotsButtonState extends State<_KindleActionDotsButton> {
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: widget.theme.copyWith(
        cardColor: const Color(0xFFEAE6DF),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Book options',
        color: const Color(0xFFEAE6DF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
        ),
        onOpened: () => setState(() => _isMenuOpen = true),
        onCanceled: () => setState(() => _isMenuOpen = false),
        onSelected: (val) {
          setState(() => _isMenuOpen = false);
          widget.onSelected(val);
        },
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _isMenuOpen ? const Color(0xFF1A1A18) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: _isMenuOpen
                ? Border.all(color: const Color(0xFF1A1A18), width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.more_vert,
            size: 20,
            color: _isMenuOpen ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
          ),
        ),
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'remove',
            child: Row(
              children: const [
                Icon(Icons.remove_circle_outline, size: 20, color: Color(0xFF1A1A18)),
                SizedBox(width: 12),
                Text(
                  'Remove from collection',
                  style: TextStyle(
                    color: Color(0xFF1A1A18),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: const [
                Icon(Icons.delete_outline, size: 20, color: Color(0xFF1A1A18)),
                SizedBox(width: 12),
                Text(
                  'Delete book',
                  style: TextStyle(
                    color: Color(0xFF1A1A18),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// COLLECTION DETAIL SCREEN
// ==========================================

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
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;
    
    final books = collection.bookIds
        .map((id) => bookRepo.getBook(id))
        .whereType<Book>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          collection.name,
          style: isEInk
              ? GoogleFonts.robotoSlab(
                  color: const Color(0xFF1A1A18),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                )
              : null,
        ),
        iconTheme: isEInk ? const IconThemeData(color: Color(0xFF1A1A18)) : null,
        bottom: isEInk
            ? const PreferredSize(
                preferredSize: Size.fromHeight(1.5),
                child: Divider(
                  height: 1.5,
                  thickness: 1.5,
                  color: Color(0xFF1A1A18),
                ),
              )
            : null,
      ),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary.withValues(alpha: 0.08),
                        shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: isEInk ? BorderRadius.circular(2) : null,
                        border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.5) : null,
                      ),
                      child: Icon(
                        Icons.collections_bookmark_outlined,
                        size: 40,
                        color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No books in this collection',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: const Color(0xFF1A1A18),
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Long-press any book in your library and select "Add to Collection" to add books here.',
                      textAlign: TextAlign.center,
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              color: const Color(0xFF4A4945),
                              fontSize: 13,
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
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
                    color: isEInk
                        ? const Color(0xFFE0DCD3)
                        : (theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow),
                    borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
                    border: Border.all(
                      color: isEInk
                          ? const Color(0xFF1A1A18)
                          : (theme.brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04)),
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
                      thickness: isEInk ? 1 : 0.5,
                      indent: 56,
                      color: isEInk
                          ? const Color(0xFF9E9A90)
                          : (theme.brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04)),
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
                          style: TextStyle(
                            fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 15,
                            color: isEInk ? const Color(0xFF1A1A18) : null,
                          ),
                        ),
                        subtitle: Text(
                          book.author.isNotEmpty ? book.author : 'Unknown Author',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isEInk ? FontWeight.w500 : FontWeight.normal,
                            color: isEInk
                                ? const Color(0xFF4A4945)
                                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        trailing: isEInk
                            ? _KindleActionDotsButton(
                                theme: theme,
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
                              )
                            : PopupMenuButton<String>(
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
