import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/models/library_location.dart';
import 'package:reader_app/core/widgets/delete_book_dialog.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/library/widgets/kindle_book_action_sheet.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/features/reader/split_reader_screen.dart';

/// Central action handler for all book view items to guarantee 100% feature
/// parity across all 8 view modes (tap, split mode, long-press, more options).
class BookItemActionHandler {
  BookItemActionHandler._();

  static void handleTap(BuildContext context, Book book, LibraryController controller) {
    final state = context.read<LibraryState>();
    final hasPendingSplit = state.splitPendingBook != null;
    final isSplitPendingBook = state.splitPendingBook?.id == book.id;

    if (hasPendingSplit && !isSplitPendingBook) {
      final leftBook = state.splitPendingBook!;
      controller.clearSplitPending();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SplitReaderScreen(
            leftBook: leftBook,
            rightBook: book,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ReaderScreen(book: book),
        ),
      ).then((_) {
        if (!context.mounted) return;
        controller.loadBooks();
      });
    }
  }

  static void showBookOptionsMenu(BuildContext context, Book book, LibraryController controller) {
    HapticFeedback.lightImpact();
    final currentTheme = context.read<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    if (isEInk) {
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (ctx, anim1, anim2) {
          return Stack(
            children: [
              // Subtle monochrome halftone dot pattern overlay
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const RepaintBoundary(
                    child: CustomPaint(
                      painter: HalftoneScrimPainter(),
                    ),
                  ),
                ),
              ),
              // Sharp Kindle Dialog Box
              Material(
                color: Colors.transparent,
                child: KindleBookActionSheet(
                  book: book,
                  onSplitView: () {
                    Navigator.pop(ctx);
                    controller.setSplitPendingBook(book);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tap another book to open in split view')),
                    );
                  },
                  onAddToCollection: () {
                    Navigator.pop(ctx);
                    _showAddToCollectionDialog(context, book, isEInk: true);
                  },
                  onDeleteBook: () {
                    Navigator.pop(ctx);
                    _confirmDeleteBook(context, book, controller);
                  },
                  onCancel: () => Navigator.pop(ctx),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      elevation: 4,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (book.author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.vertical_split_outlined),
                title: const Text('Open in Split View'),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.setSplitPendingBook(book);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tap another book to open in split view')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Add to Collection'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToCollectionDialog(context, book, isEInk: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text(
                  'Delete Book',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteBook(context, book, controller);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _confirmDeleteBook(BuildContext context, Book book, LibraryController controller) async {
    final result = await showDeleteBookDialog(
      context: context,
      book: book,
    );

    if (result != null && result.confirmed && context.mounted) {
      await controller.deleteBook(book.id, deleteFile: result.deletePhysicalFile);
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

  static Future<void> _showAddToCollectionDialog(BuildContext context, Book book, {bool isEInk = false}) async {
    final collectionRepo = context.read<CollectionRepository>();
    final collections = collectionRepo.getAllCollections();
    final theme = Theme.of(context);

    if (collections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No collections created yet')),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierColor: isEInk ? const Color(0xFF1A1A18).withValues(alpha: 0.14) : null,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
          side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
        ),
        backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
        elevation: isEInk ? 0 : null,
        title: Text(
          'Add to Collection',
          style: isEInk
              ? GoogleFonts.robotoSlab(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF1A1A18),
                )
              : null,
        ),
        children: collections.asMap().entries.map((entry) {
          final i = entry.key;
          final collection = entry.value;
          final isInCollection = collection.bookIds.contains(book.id);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEInk && i > 0)
                const Divider(height: 1, thickness: 1, color: Color(0xFF9E9A90)),
              SimpleDialogOption(
                onPressed: () async {
                  if (isInCollection) {
                    Navigator.pop(context);
                    return;
                  }
                  await collectionRepo.addBookToCollection(collection.id, book.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added to ${collection.name}')),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      if (isEInk)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isInCollection ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
                          ),
                          child: isInCollection
                              ? const Icon(Icons.check, size: 15, color: Color(0xFFEAE6DF))
                              : null,
                        )
                      else
                        Icon(
                          isInCollection ? Icons.check_box : Icons.check_box_outline_blank,
                          color: isInCollection ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          collection.name,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 14,
                                  fontWeight: isInCollection ? FontWeight.bold : FontWeight.w500,
                                  color: const Color(0xFF1A1A18),
                                )
                              : TextStyle(
                                  fontWeight: isInCollection ? FontWeight.bold : FontWeight.normal,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  static String formatDate(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    if (difference.inDays == 0 && dt.day == now.day) {
      return 'Today';
    } else if (difference.inDays <= 1 && (now.day - dt.day == 1 || difference.inDays == 1)) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
  }
}

Widget _buildFormatBadge(BuildContext context, String format, {required bool isEInk}) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: isEInk ? Colors.transparent : theme.colorScheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(isEInk ? 2 : 4),
      border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
    ),
    child: Text(
      format.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
      ),
    ),
  );
}

Widget _buildCoverProgressBar(BuildContext context, double progress, {required bool isEInk, double height = 4.0}) {
  final theme = Theme.of(context);
  return Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary.withValues(alpha: 0.2),
      border: isEInk ? const Border(top: BorderSide(color: Color(0xFF1A1A18), width: 1.0)) : null,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: isEInk ? const Color(0xFF1A1A18) : null,
            borderRadius: isEInk ? BorderRadius.zero : const BorderRadius.horizontal(right: Radius.circular(2)),
            gradient: isEInk
                ? null
                : LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                  ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. Extra Large Icons Card
// ---------------------------------------------------------------------------
class BookExtraLargeCard extends StatelessWidget {
  final Book book;

  const BookExtraLargeCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
        side: isEInk ? const BorderSide(color: Color(0xFF9E9A90), width: 1.0) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(isEInk ? 2 : AppRadius.lg)),
                  child: BookCover(
                    book: book,
                    height: 270,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (book.progress > 0)
                  _buildCoverProgressBar(context, book.progress, isEInk: isEInk, height: 5),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A18),
                                )
                              : theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author.isNotEmpty ? book.author : 'Unknown Author',
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontSize: 13,
                            color: const Color(0xFF3D3C38),
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildFormatBadge(context, book.format, isEInk: isEInk),
                          const SizedBox(width: 8),
                          Text(
                            LibraryLocation.formatBytes(book.safeFileSize),
                            style: TextStyle(
                              fontSize: 11,
                              color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}% read",
                          style: TextStyle(
                            fontSize: 12,
                            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Large Icons Card (Standard Default)
// ---------------------------------------------------------------------------
class BookLargeCard extends StatelessWidget {
  final Book book;

  const BookLargeCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        side: isEInk ? const BorderSide(color: Color(0xFF9E9A90), width: 1.0) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(isEInk ? 2 : 15)),
                  child: BookCoverCard(book: book),
                ),
                if (book.progress > 0)
                  _buildCoverProgressBar(context, book.progress, isEInk: isEInk, height: 4),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A18),
                                )
                              : theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.1,
                                ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontSize: 11,
                            color: const Color(0xFF3D3C38),
                          )
                        : theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFormatBadge(context, book.format, isEInk: isEInk),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}% read",
                          style: TextStyle(
                            fontSize: 10,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Medium Icons Card
// ---------------------------------------------------------------------------
class BookMediumCard extends StatelessWidget {
  final Book book;

  const BookMediumCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.md),
        side: isEInk ? const BorderSide(color: Color(0xFF9E9A90), width: 1.0) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(isEInk ? 2 : AppRadius.md)),
                  child: BookCover(
                    book: book,
                    height: 135,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (book.progress > 0)
                  _buildCoverProgressBar(context, book.progress, isEInk: isEInk, height: 3),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A18),
                            height: 1.2,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author.isNotEmpty ? book.author : 'Unknown',
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontSize: 10,
                            color: const Color(0xFF3D3C38),
                          )
                        : theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 10,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFormatBadge(context, book.format, isEInk: isEInk),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}%",
                          style: TextStyle(
                            fontSize: 9,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Small Icons Card
// ---------------------------------------------------------------------------
class BookSmallCard extends StatelessWidget {
  final Book book;

  const BookSmallCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
        side: isEInk ? const BorderSide(color: Color(0xFF9E9A90), width: 1.0) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(isEInk ? 2 : AppRadius.sm)),
                  child: BookCover(
                    book: book,
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (book.progress > 0)
                  _buildCoverProgressBar(context, book.progress, isEInk: isEInk, height: 2.5),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 4.0),
              child: Text(
                book.title,
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A18),
                        height: 1.1,
                      )
                    : const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. List Item
// ---------------------------------------------------------------------------
class BookListItem extends StatelessWidget {
  final Book book;

  const BookListItem({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Container(
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.md),
        border: Border.all(
          color: isEInk ? const Color(0xFF9E9A90) : theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
          width: 1.0,
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isEInk ? 2 : 4),
                child: BookCover(
                  book: book,
                  height: 48,
                  width: 34,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: const Color(0xFF1A1A18),
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.author.isNotEmpty ? book.author : 'Unknown Author',
                      style: isEInk
                          ? const TextStyle(
                              color: Color(0xFF3D3C38),
                              fontSize: 11,
                            )
                          : theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildFormatBadge(context, book.format, isEInk: isEInk),
              if (book.progress > 0) ...[
                const SizedBox(width: 8),
                Text(
                  "${(book.progress * 100).toInt()}%",
                  style: TextStyle(
                    fontSize: 11,
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Details View Header & Item
// ---------------------------------------------------------------------------
class BookDetailsHeader extends StatelessWidget {
  const BookDetailsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
        border: isEInk ? Border.all(color: const Color(0xFF9E9A90), width: 1.0) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              'Name',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Format',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Size',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Read/Added',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class BookDetailsItem extends StatelessWidget {
  final Book book;

  const BookDetailsItem({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
        border: Border.all(
          color: isEInk ? const Color(0xFF9E9A90) : theme.colorScheme.outlineVariant.withValues(alpha: 0.1),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(isEInk ? 2 : 3),
                      child: BookCover(
                        book: book,
                        height: 36,
                        width: 26,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: isEInk
                                ? GoogleFonts.robotoSlab(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1A18),
                                  )
                                : const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            book.author.isNotEmpty ? book.author : 'Unknown',
                            style: TextStyle(
                              fontSize: 10,
                              color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: _buildFormatBadge(context, book.format, isEInk: isEInk),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  LibraryLocation.formatBytes(book.safeFileSize),
                  style: TextStyle(
                    fontSize: 11,
                    color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  BookItemActionHandler.formatDate(book.lastOpened),
                  style: TextStyle(
                    fontSize: 10,
                    color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              InkWell(
                onTap: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                borderRadius: BorderRadius.circular(isEInk ? 2 : 12),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Tiles Item
// ---------------------------------------------------------------------------
class BookTileItem extends StatelessWidget {
  final Book book;

  const BookTileItem({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.md),
        side: isEInk ? const BorderSide(color: Color(0xFF9E9A90), width: 1.0) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.xs),
                child: BookCover(
                  book: book,
                  height: 62,
                  width: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title,
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.15,
                              color: const Color(0xFF1A1A18),
                            )
                          : const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.15,
                            ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.author.isNotEmpty ? book.author : 'Unknown Author',
                      style: TextStyle(
                        fontSize: 11,
                        color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildFormatBadge(context, book.format, isEInk: isEInk),
                        const SizedBox(width: 6),
                        Text(
                          LibraryLocation.formatBytes(book.safeFileSize),
                          style: TextStyle(
                            fontSize: 10,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        if (book.progress > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            "• ${(book.progress * 100).toInt()}%",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Content Item
// ---------------------------------------------------------------------------
class BookContentItem extends StatelessWidget {
  final Book book;

  const BookContentItem({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
        border: Border.all(
          color: isEInk ? const Color(0xFF9E9A90) : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => BookItemActionHandler.handleTap(context, book, controller),
        onLongPress: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
                    child: BookCover(
                      book: book,
                      height: 96,
                      width: 68,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (book.progress > 0) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 68,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isEInk ? 0 : 2),
                        child: LinearProgressIndicator(
                          value: book.progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            style: isEInk
                                ? GoogleFonts.robotoSlab(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1A1A18),
                                  )
                                : theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.1,
                                  ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildFormatBadge(context, book.format, isEInk: isEInk),
                        InkWell(
                          onTap: () => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6.0, top: 2.0),
                            child: Icon(
                              Icons.more_vert,
                              size: 18,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.author.isNotEmpty ? book.author : 'Unknown Author',
                      style: isEInk
                          ? const TextStyle(
                              color: Color(0xFF3D3C38),
                              fontSize: 12,
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Progress and status line
                    if (book.progress > 0)
                      Text(
                        "${(book.progress * 100).toInt()}% read • ${book.currentPage > 0 ? 'Page ${book.currentPage}' : 'Section ${book.sectionIndex + 1}'}",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                        ),
                      )
                    else
                      Text(
                        "Not started yet",
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Metadata chips / row
                    Row(
                      children: [
                        Icon(Icons.sd_storage_outlined, size: 12, color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(
                          LibraryLocation.formatBytes(book.safeFileSize),
                          style: TextStyle(
                            fontSize: 10,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.access_time, size: 12, color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(
                          BookItemActionHandler.formatDate(book.lastOpened),
                          style: TextStyle(
                            fontSize: 10,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "• ${book.sourceType == BookSourceType.linked ? 'Linked' : 'Imported'}",
                          style: TextStyle(
                            fontSize: 10,
                            color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
