import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/models/collection.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'dart:io';

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
                  leading: _buildCover(book),
                  title: Text(book.title),
                  subtitle: Text(book.author),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      context.read<CollectionRepository>().removeBookFromCollection(collection.id, book.id);
                      setState(() {});
                    },
                  ),
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

  Widget _buildCover(Book book) {
    if (book.coverPath != null) {
      return Image.file(
        File(book.coverPath!),
        width: 40,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.book),
      );
    }
    return const Icon(Icons.book);
  }
}
