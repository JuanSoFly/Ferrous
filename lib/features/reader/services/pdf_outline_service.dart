import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/pdf_chapter.dart';

class PdfOutlineService {
  PdfOutlineService._();

  /// Parse outline/bookmarks directly from a PDF file.
  /// Runs on a background isolate via [compute] if file size > 500KB.
  static Future<List<PdfChapter>> extractBookmarks(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];

      final bytes = await file.readAsBytes();
      if (bytes.length > 500 * 1024) {
        return await compute(_parsePdfBookmarksFromBytes, bytes);
      } else {
        return _parsePdfBookmarksFromBytes(bytes);
      }
    } catch (e) {
      debugPrint('PdfOutlineService: Error extracting bookmarks: $e');
      return const [];
    }
  }

  /// Internal synchronous parser executed on bytes.
  static List<PdfChapter> _parsePdfBookmarksFromBytes(List<int> byteList) {
    // Convert bytes to Latin-1 string to preserve 1:1 byte positions
    final latin1Str = latin1.decode(byteList);

    // 1. Build map of page object references to 0-based page index
    final pageMap = <int, int>{}; // objNum -> pageIndex
    final pageObjRegex = RegExp(r'(\d+)\s+0\s+obj\s*<<[^>]*?/Type\s*/Page\b');
    int pIndex = 0;
    for (final m in pageObjRegex.allMatches(latin1Str)) {
      final objNum = int.tryParse(m.group(1) ?? '');
      if (objNum != null) {
        pageMap[objNum] = pIndex++;
      }
    }

    // 2. Find all bookmark items with /Title and /Dest
    final items = <PdfChapter>[];
    final bookmarkRegex = RegExp(r'(\d+)\s+0\s+obj\s*<<(?<content>[\s\S]*?)>>\s*endobj');
    for (final m in bookmarkRegex.allMatches(latin1Str)) {
      final content = m.group(0) ?? '';
      if (!content.contains('/Title')) continue;
      if (!content.contains('/Parent') && !content.contains('/First') && !content.contains('/Dest')) continue;

      // Extract Title
      String? title;
      final titleMatch = RegExp(r'/Title\s*\((?<raw>.*?)\)(?=/|\s*>>)').firstMatch(content);
      if (titleMatch != null) {
        final raw = titleMatch.group(1) ?? '';
        title = _decodePdfString(raw);
      } else {
        final hexMatch = RegExp(r'/Title\s*<(?<hex>[0-9A-Fa-f]+)>').firstMatch(content);
        if (hexMatch != null) {
          title = _decodeHexString(hexMatch.group(1) ?? '');
        }
      }

      if (title == null || title.trim().isEmpty) continue;

      // Extract Dest page
      int? targetPage;
      final destObjMatch = RegExp(r'/Dest\s*\[\s*(\d+)\s+0\s+R').firstMatch(content);
      if (destObjMatch != null) {
        final destObj = int.tryParse(destObjMatch.group(1) ?? '');
        if (destObj != null && pageMap.containsKey(destObj)) {
          targetPage = pageMap[destObj];
        }
      }

      if (targetPage == null) {
        final destRefMatch = RegExp(r'/Dest\s*(\d+)\s+0\s+R').firstMatch(content);
        if (destRefMatch != null) {
          final destObjNum = int.tryParse(destRefMatch.group(1) ?? '');
          if (destObjNum != null) {
            final destObjRegex = RegExp('$destObjNum\\s+0\\s+obj\\s*\\[\\s*(\\d+)\\s+0\\s+R');
            final m2 = destObjRegex.firstMatch(latin1Str);
            if (m2 != null) {
              final pObj = int.tryParse(m2.group(1) ?? '');
              if (pObj != null && pageMap.containsKey(pObj)) {
                targetPage = pageMap[pObj];
              }
            }
          }
        }
      }

      if (targetPage != null) {
        items.add(PdfChapter(
          title: title.trim(),
          pageIndex: targetPage,
        ));
      }
    }

    if (items.isEmpty) return const [];

    // Filter duplicates and sort by page index
    final seen = <String>{};
    final deduped = <PdfChapter>[];
    for (final item in items) {
      final key = '${item.pageIndex}:${item.title.toLowerCase()}';
      if (seen.add(key)) {
        deduped.add(item);
      }
    }

    deduped.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return deduped;
  }

  static String _decodePdfString(String raw) {
    final bytes = raw.codeUnits;
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codeUnits = <int>[];
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }
    return raw;
  }

  static String _decodeHexString(String hex) {
    final bytes = <int>[];
    for (int i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codeUnits = <int>[];
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
