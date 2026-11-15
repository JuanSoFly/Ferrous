import 'package:flutter/foundation.dart';

/// A chapter or outline entry extracted from a PDF document.
@immutable
class PdfChapter {
  final String title;
  final int pageIndex;
  final int depth;

  const PdfChapter({
    required this.title,
    required this.pageIndex,
    this.depth = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfChapter &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          pageIndex == other.pageIndex &&
          depth == other.depth;

  @override
  int get hashCode => title.hashCode ^ pageIndex.hashCode ^ depth.hashCode;

  @override
  String toString() => 'PdfChapter(title: $title, pageIndex: $pageIndex, depth: $depth)';
}
