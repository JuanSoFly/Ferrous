import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/models/book_format.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/reader/pdf_reader.dart';
import 'package:reader_app/features/reader/epub_reader.dart';
import 'package:reader_app/features/reader/cbz_reader.dart';
import 'package:reader_app/features/reader/docx_reader.dart';
import 'package:reader_app/features/reader/mobi_reader.dart';

/// Reader builder function type.
typedef ReaderBuilder = Widget Function(Book book, BookRepository repository);

/// Registry of reader widgets by format.
final Map<BookFormat, ReaderBuilder> _readerBuilders = {
  BookFormat.pdf: (book, repo) => PdfReaderScreen(book: book, repository: repo),
  BookFormat.epub: (book, repo) => EpubReaderScreen(book: book, repository: repo),
  BookFormat.cbz: (book, repo) => CbzReaderScreen(book: book, repository: repo),
  BookFormat.cbr: (book, repo) => CbzReaderScreen(book: book, repository: repo),
  BookFormat.docx: (book, repo) => DocxReaderScreen(book: book, repository: repo),
  BookFormat.mobi: (book, repo) => MobiReaderScreen(book: book, repository: repo),
  BookFormat.azw: (book, repo) => MobiReaderScreen(book: book, repository: repo),
  BookFormat.azw3: (book, repo) => MobiReaderScreen(book: book, repository: repo),
};

class ReaderScreen extends StatelessWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final bookRepository = context.read<BookRepository>();
    final format = BookFormat.fromString(book.format);

    final builder = _readerBuilders[format];
    if (builder != null) {
      return builder(book, bookRepository);
    }

    return _buildUnsupportedScreen(context, book.format);
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
