import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/collections/collections_tab.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';

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

class _LibraryView extends StatelessWidget {
  const _LibraryView();

  @override
  Widget build(BuildContext context) {
    // Watch state
    final state = context.watch<LibraryState>();
    final controller = context.read<LibraryController>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            decoration: const InputDecoration(
              hintText: 'Search books...',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => controller.setSearchQuery(value),
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
                  : () => controller.pickAndScanDirectory(),
              tooltip: "Add Folder",
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Books"),
              Tab(text: "Collections"),
            ],
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
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      );
    }
    
    if (state.error != null) {
      return Center(child: Text('Error: ${state.error}'));
    }
    
    if (state.books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_books,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No books found. Pick a folder to scan.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text("Scan Directory"),
              onPressed: () => controller.pickAndScanDirectory(),
            )
          ],
        ),
      );
    }
    
    final displayedBooks = state.filteredBooks;
    return CustomScrollView(
      slivers: [
        if (state.searchQuery.isEmpty && displayedBooks.any((b) => b.progress > 0))
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "Continue Reading",
                    style:
                        Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8),
                    itemCount: displayedBooks
                        .where((b) => b.progress > 0)
                        .length,
                    itemBuilder: (context, index) {
                      final book = displayedBooks
                          .where((b) => b.progress > 0)
                          .toList()[index];
                      return SizedBox(
                        width: 160,
                        child: _BookCard(book: book),
                      );
                    },
                  ),
                ),
                const Divider(),
              ],
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childCount: displayedBooks.length,
            itemBuilder: (context, index) {
              return _BookCard(book: displayedBooks[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;

  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ReaderScreen(book: book),
            ),
          ).then((_) {
             if (!context.mounted) return;
             context.read<LibraryController>().loadBooks();
          });
        },
        onLongPress: () => _showAddToCollectionDialog(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image or placeholder
            _buildCover(context),
            if (book.progress > 0)
              LinearProgressIndicator(
                value: book.progress,
                minHeight: 4,
                backgroundColor: Colors.transparent,
                color: Theme.of(context).colorScheme.primary,
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Show extension format
                      Text(
                        book.format.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}%",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
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
  
  Future<void> _showAddToCollectionDialog(BuildContext context) async {
    final collectionRepo = context.read<CollectionRepository>();
    final collections = collectionRepo.getAllCollections();
    
    if (collections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No collections created yet')),
      );
      return;
    }
    
    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to Collection'),
        children: collections.map((collection) {
          final isInCollection = collection.bookIds.contains(book.id);
          return SimpleDialogOption(
            onPressed: () async {
              if (isInCollection) {
                // Already added
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
            child: Row(
              children: [
                Icon(isInCollection ? Icons.check_box : Icons.check_box_outline_blank),
                const SizedBox(width: 8),
                Text(collection.name),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildCover(BuildContext context) {
    if (book.coverPath != null && book.coverPath!.isNotEmpty) {
      final file = File(book.coverPath!);
      if (file.existsSync()) {
        return SizedBox(
          height: 200,
          width: double.infinity,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
          ),
        );
      }
    }
    return _buildPlaceholder();
  }
  
  Widget _buildPlaceholder() {
    return Container(
      height: 200,
      color: Colors.grey.shade800,
      child: Center(
        child: Icon(
          _getFormatIcon(book.format),
          size: 48, 
          color: Colors.white54,
        ),
      ),
    );
  }
  
  IconData _getFormatIcon(String format) {
    switch (format.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.auto_stories;
      case 'cbz':
      case 'cbr':
        return Icons.collections_bookmark;
      case 'docx':
        return Icons.description;
      default:
        return Icons.book;
    }
  }
}
