import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.isLoading
                ? null
                : () => controller.pickAndScanDirectory(),
            tooltip: "Rescan",
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: state.isLoading
                ? null
                : () => controller.pickAndScanDirectory(),
            tooltip: "Open Folder",
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('Error: ${state.error}'))
              : state.books.isEmpty
                  ? Center(
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
                    )
                  : CustomScrollView(
                      slivers: [
                        if (state.books.any((b) => b.progress > 0))
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
                                    itemCount: state.books
                                        .where((b) => b.progress > 0)
                                        .length,
                                    itemBuilder: (context, index) {
                                      final book = state.books
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
                            childCount: state.books.length,
                            itemBuilder: (context, index) {
                              return _BookCard(book: state.books[index]);
                            },
                          ),
                        ),
                      ],
                    ),
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
             // Refresh library when returning from reader to update progress UI
             // This is a bit hacky, but works for now. 
             // Ideally we'd watch the specific book stream.
             // But LibraryController reloads on init, so we might need a manual refresh method exposed.
             // For now, let's assume the user can pull to refresh or just state updates.
             // Actually, since we are using Hive, we should watch the box.
             // But for MVP phase 1, let's just trigger a reload if possible.
             // A better way is to have the controller listen to the repository stream.
             // For now, let's leave it as is, the progress bar might not update instantly on back without a state refresh.
             // We can fix this by reloading in the Controller.
             // Let's modify LibraryController to expose a reload method and call it.
             // But we don't have access to the controller easily here without context.read.
             // Let's just push and await.
             // Actually, the ReaderScreen updates the repository. The LibraryController loads from repository.
             // We should add a listener to the repository in the controller, but that's advanced.
             // Let's just simply rely on the fact that next time the library builds it might catch it?
             // No, StateNotifier holds the list. We need to tell it to reload.
             if (!context.mounted) return;
             context.read<LibraryController>().loadBooks();
          });
        },
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
