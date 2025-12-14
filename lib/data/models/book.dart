import 'package:hive/hive.dart';


@HiveType(typeId: 0)
class Book extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String path;

  @HiveField(4)
  final String format; // pdf, epub, cbz, docx

  @HiveField(5)
  int currentPage;

  @HiveField(6)
  int totalPages;

  @HiveField(7)
  DateTime lastOpened;

  @HiveField(8)
  DateTime addedAt;

  @HiveField(9)
  int sectionIndex; // For EPUB chapter/section index

  @HiveField(10)
  double scrollPosition; // For EPUB scroll offset

  @HiveField(11)
  final String? coverPath;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.path,
    required this.format,
    this.currentPage = 0,
    this.totalPages = 0,
    this.sectionIndex = 0,
    this.scrollPosition = 0.0,
    this.coverPath,
    DateTime? lastOpened,
    DateTime? addedAt,
  })  : lastOpened = lastOpened ?? DateTime.now(),
        addedAt = addedAt ?? DateTime.now();

  double get progress {
    if (format == 'epub' && totalPages > 0) {
      // Rough estimate for EPUB based on chapter index
      return sectionIndex / totalPages;
    }
    return totalPages > 0 ? currentPage / totalPages : 0.0;
  }

  Book copyWith({
    String? title,
    String? author,
    int? currentPage,
    int? totalPages,
    int? sectionIndex,
    double? scrollPosition,
    String? coverPath,
    DateTime? lastOpened,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      path: path,
      format: format,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      sectionIndex: sectionIndex ?? this.sectionIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      coverPath: coverPath ?? this.coverPath,
      lastOpened: lastOpened ?? this.lastOpened,
      addedAt: addedAt,
    );
  }
}
