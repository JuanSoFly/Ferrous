import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/html_reader_screen.dart';
import 'package:reader_app/src/rust/api/txt.dart';

class TxtReaderScreen extends HtmlReaderScreen {
  const TxtReaderScreen({
    super.key,
    required super.book,
    required super.repository,
  });

  @override
  State<TxtReaderScreen> createState() => _TxtReaderScreenState();
}

class _TxtReaderScreenState extends HtmlReaderScreenState<TxtReaderScreen> {
  @override
  HtmlReaderConfig get config => HtmlReaderConfig.mobi; // Reuse MOBI layout configuration values

  @override
  Future<String> loadContent(String path) async {
    return await readTxtToHtml(path: path);
  }
}
