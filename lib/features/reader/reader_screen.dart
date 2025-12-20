import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/reader/pdf_reader.dart';
import 'package:reader_app/features/reader/epub_reader.dart';
import 'package:reader_app/features/reader/cbz_reader.dart';
import 'package:reader_app/features/reader/docx_reader.dart';
import 'package:reader_app/features/reader/mobi_reader.dart';

class ReaderScreen extends StatelessWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final bookRepository = context.read<BookRepository>();
    final path = book.path.toLowerCase();

    if (path.endsWith('.pdf')) {
      return PdfReaderScreen(book: book, repository: bookRepository);
    } else if (path.endsWith('.epub')) {
      return EpubReaderScreen(book: book, repository: bookRepository);
    } else if (path.endsWith('.cbz') || path.endsWith('.cbr')) {
      return CbzReaderScreen(book: book, repository: bookRepository);
    } else if (path.endsWith('.docx')) {
      return DocxReaderScreen(book: book, repository: bookRepository);
    } else if (path.endsWith('.mobi') || path.endsWith('.azw3') || path.endsWith('.azw')) {
      return MobiReaderScreen(book: book, repository: bookRepository);
    } else {
      return _buildUnsupportedScreen(context, 'Unknown');
    }
  }

  Widget _buildUnsupportedScreen(BuildContext context, String format) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                '$format format not yet supported',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'File: ${book.path}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
