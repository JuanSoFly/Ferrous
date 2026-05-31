import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/collections/collections_tab.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/reader/split_reader_screen.dart';
import 'package:reader_app/data/services/saf_service.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StateNotifierProvider<LibraryController, LibraryState>(
      create: (context) => LibraryController(context.read<BookRepository>()),
      child: const _LibraryView(),
    );
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LibraryState>();
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);

    // Sync search controller if cleared externally
    if (state.searchQuery.isEmpty && _searchController.text.isNotEmpty) {
      _searchController.clear();
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Container(
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search your library...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) => controller.setSearchQuery(value),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      controller.setSearchQuery('');
                      setState(() {});
                    },
                    child: Icon(
                      Icons.cancel,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: state.isLoading
                  ? null
                  : () => controller.rescanFolders(),
              tooltip: "Rescan Folders",
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: state.isLoading
                  ? null
                  : () async {
                      final mode = await _promptStorageMode(context);
                      if (mode != null && context.mounted) {
                        controller.pickAndScanDirectory(mode);
                      }
                    },
              tooltip: "Add Folder",
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    width: 1,
                  ),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: theme.colorScheme.onPrimary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(text: "Books"),
                    Tab(text: "Collections"),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildBooksTab(context, state, controller),
            const CollectionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBooksTab(BuildContext context, LibraryState state, LibraryController controller) {
    final theme = Theme.of(context);
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (state.statusMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                state.statusMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      );
    }
    
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Error: ${state.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    
    if (state.books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories,
                size: 80, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            Text(
              'Your Library is Empty',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a folder to scan for supported books.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text("Select Folder"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final mode = await _promptStorageMode(context);
                if (mode != null && context.mounted) {
                  controller.pickAndScanDirectory(mode);
                }
              },
            )
          ],
        ),
      );
    }
    
    final displayedBooks = state.filteredBooks;
    final continueReadingBooks = state.searchQuery.isEmpty 
        ? displayedBooks.where((b) => b.progress > 0).toList()
        : <Book>[];

    return CustomScrollView(
      slivers: [
        if (state.isGeneratingCovers)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Generating covers…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (continueReadingBooks.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Text(
                    "Continue Reading",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                SizedBox(
                  height: 310,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: continueReadingBooks.length,
                    itemBuilder: (context, index) {
                      final book = continueReadingBooks[index];
                      return SizedBox(
                        width: 156,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _BookCard(book: book),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Divider(height: 1, thickness: 1),
                ),
              ],
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 100), // Extra bottom padding for floating nav bar
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: displayedBooks.length,
            itemBuilder: (context, index) {
              return _BookCard(book: displayedBooks[index]);
            },
          ),
        ),
      ],
    );
  }

  Future<SafStorageMode?> _promptStorageMode(BuildContext context) {
    final theme = Theme.of(context);
    return showDialog<SafStorageMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Folder'),
          content: const Text(
            'Choose how to add books from this folder. '
            'Link keeps files in place and saves storage.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(context).pop(SafStorageMode.imported),
                  child: const Text('Import'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(SafStorageMode.linked),
                  child: const Text('Link'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;

  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final hasPendingSplit = context.select<LibraryState, bool>((s) => s.splitPendingBook != null);
    final isSplitPendingBook = context.select<LibraryState, bool>((s) => s.splitPendingBook?.id == book.id);
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (hasPendingSplit && !isSplitPendingBook) {
            final leftBook = context.read<LibraryState>().splitPendingBook!;
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
               context.read<LibraryController>().loadBooks();
            });
          }
        },
        onLongPress: () => _showBookOptionsMenu(context, controller),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: BookCoverCard(book: book),
                ),
                if (book.progress > 0)
                  Container(
                    height: 4,
                    width: double.infinity,
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: book.progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.secondary,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    style: theme.textTheme.bodySmall?.copyWith(
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          book.format.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}% read",
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

  void _showBookOptionsMenu(BuildContext context, LibraryController controller) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.vertical_split, color: theme.colorScheme.primary),
            title: const Text('Open in Split View'),
            subtitle: const Text('Select another book to open both side-by-side'),
            onTap: () {
              Navigator.pop(ctx);
              controller.setSplitPendingBook(book);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tap another book to open in split view')),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.collections_bookmark, color: theme.colorScheme.primary),
            title: const Text('Add to Collection'),
            onTap: () {
              Navigator.pop(ctx);
              _showAddToCollectionDialog(context);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
  
  Future<void> _showAddToCollectionDialog(BuildContext context) async {
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
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add to Collection'),
        children: collections.map((collection) {
          final isInCollection = collection.bookIds.contains(book.id);
          return SimpleDialogOption(
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
                  Icon(
                    isInCollection ? Icons.check_box : Icons.check_box_outline_blank,
                    color: isInCollection ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    collection.name,
                    style: TextStyle(
                      fontWeight: isInCollection ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
