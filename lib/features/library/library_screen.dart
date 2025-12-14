import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/reader/reader_screen.dart';
import 'package:reader_app/src/rust/api/library.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StateNotifierProvider<LibraryController, LibraryState>(
      create: (_) => LibraryController(),
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
                  : MasonryGridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      padding: const EdgeInsets.all(8),
                      itemCount: state.books.length,
                      itemBuilder: (context, index) {
                        return _BookCard(book: state.books[index]);
                      },
                    ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final BookMetadata book;

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
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover placeholder
            Container(
              height: 200,
              color: Colors.grey.shade800,
              child: const Center(
                child: Icon(Icons.book, size: 48, color: Colors.white54),
              ),
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
                  // Show extension format
                  Text(
                    book.path.split('.').last.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold),
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
