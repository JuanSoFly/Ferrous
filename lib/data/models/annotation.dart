import 'package:hive/hive.dart';

@HiveType(typeId: 1)
class Annotation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String bookId;

  @HiveField(2)
  final String selectedText;

  @HiveField(3)
  final String? note;

  @HiveField(4)
  final int chapterIndex;

  @HiveField(5)
  final int startOffset;

  @HiveField(6)
  final int endOffset;

  @HiveField(7)
  final int color; // ARGB int

  @HiveField(8)
  final DateTime createdAt;

  Annotation({
    required this.id,
    required this.bookId,
    required this.selectedText,
    this.note,
    required this.chapterIndex,
    required this.startOffset,
    required this.endOffset,
    required this.color,
    required this.createdAt,
  });

  Annotation copyWith({
    String? id,
    String? bookId,
    String? selectedText,
    String? note,
    int? chapterIndex,
    int? startOffset,
    int? endOffset,
    int? color,
    DateTime? createdAt,
  }) {
    return Annotation(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      selectedText: selectedText ?? this.selectedText,
      note: note ?? this.note,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
