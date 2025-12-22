import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/reader/html_reader_screen.dart';
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;

/// MOBI reader using the shared HTML reader infrastructure.
/// 
/// The only format-specific part is the Rust API call to extract MOBI content.
/// Note: The Rust API is synchronous, so we wrap it in a Future.
class MobiReaderScreen extends HtmlReaderScreen {
  const MobiReaderScreen({
    super.key,
    required Book book,
    required BookRepository repository,
  }) : super(book: book, repository: repository);

  @override
  State<MobiReaderScreen> createState() => _MobiReaderScreenState();
}

class _MobiReaderScreenState extends HtmlReaderScreenState<MobiReaderScreen> {
  @override
  HtmlReaderConfig get config => HtmlReaderConfig.mobi;

  @override
  Future<String> loadContent(String path) async {
    // Note: getMobiContent is synchronous in the current API
    return rust_mobi.getMobiContent(path: path);
  }
}
