import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/html_reader_screen.dart';
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;
import 'package:reader_app/core/utils/performance.dart';

/// MOBI reader using the shared HTML reader infrastructure.
/// 
/// The only format-specific part is the Rust API call to extract MOBI content.
/// Note: The Rust API is synchronous, so we wrap it in a Future.
class MobiReaderScreen extends HtmlReaderScreen {
  const MobiReaderScreen({
    super.key,
    required super.book,
    required super.repository,
  });

  @override
  State<MobiReaderScreen> createState() => _MobiReaderScreenState();
}

class _MobiReaderScreenState extends HtmlReaderScreenState<MobiReaderScreen> {
  @override
  HtmlReaderConfig get config => HtmlReaderConfig.mobi;

  @override
  Future<String> loadContent(String path) async {
    // Note: getMobiContent is synchronous, wrap in async for measureAsync
    return await measureAsync('load_mobi_content', () async {
      return rust_mobi.getMobiContent(path: path);
    });
  }
}
