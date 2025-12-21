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
    final format = book.format.toLowerCase();

    if (format == 'pdf') {
      return PdfReaderScreen(book: book, repository: bookRepository);
    } else if (format == 'epub') {
      return EpubReaderScreen(book: book, repository: bookRepository);
    } else if (format == 'cbz' || format == 'cbr') {
      return CbzReaderScreen(book: book, repository: bookRepository);
    } else if (format == 'docx') {
      return DocxReaderScreen(book: book, repository: bookRepository);
    } else if (format == 'mobi' || format == 'azw3' || format == 'azw') {
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
                'Location: ${book.sourceType == BookSourceType.imported ? book.filePath : (book.sourceUri ?? 'Unknown')}',
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
