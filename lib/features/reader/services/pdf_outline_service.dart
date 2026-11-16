import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ferrous/src/rust/api/pdf.dart' as pdf_api;
import '../models/pdf_chapter.dart';

class PdfOutlineService {
  PdfOutlineService._();

  /// Parse outline/bookmarks directly from a PDF file using native PDFium C++ APIs.
  /// Runs in < 3ms with support for compressed object streams (/ObjStm) and hierarchical trees.
  static Future<List<PdfChapter>> extractBookmarks(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];

      final items = await pdf_api.getPdfOutline(path: filePath);
      if (items.isEmpty) return const [];

      return items.map((item) {
        return PdfChapter(
          title: item.title,
          pageIndex: item.pageIndex ?? 0,
          depth: item.depth,
        );
      }).toList();
    } catch (e) {
      debugPrint('PdfOutlineService: Error extracting bookmarks: $e');
      return const [];
    }
  }
}
