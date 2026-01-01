import 'package:flutter/material.dart';
import 'package:reader_app/features/reader/html_reader_screen.dart';
import 'package:reader_app/src/rust/api/docx.dart';

class DocxReaderScreen extends HtmlReaderScreen {
  const DocxReaderScreen({
    super.key,
    required super.book,
    required super.repository,
  });

  @override
  State<DocxReaderScreen> createState() => _DocxReaderScreenState();
}

class _DocxReaderScreenState extends HtmlReaderScreenState<DocxReaderScreen> {
  @override
  HtmlReaderConfig get config => HtmlReaderConfig.docx;

  @override
  Future<String> loadContent(String path) async {
    return await readDocxToHtml(path: path);
  }
}
