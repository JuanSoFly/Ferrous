import 'package:hive/hive.dart';

enum BookSourceType { imported, linked }

enum ReadingMode {
  vertical,
  leftToRight,
  verticalContinuous,
  webtoon,
  horizontalContinuous,
}

ReadingMode parseReadingMode(String? value) {
  if (value == null || value.isEmpty) return ReadingMode.verticalContinuous;
  for (final mode in ReadingMode.values) {
    if (mode.name == value) return mode;
  }
  return ReadingMode.verticalContinuous;
}

BookSourceType parseBookSourceType(String? value) {
  if (value == null) return BookSourceType.imported;
  switch (value) {
    case 'linked':
    case 'link':
      return BookSourceType.linked;
    case 'imported':
    case 'import':
      return BookSourceType.imported;
  }
  for (final type in BookSourceType.values) {
    if (type.name == value) return type;
  }
  return BookSourceType.imported;
}

@HiveType(typeId: 0)
class Book extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String filePath;

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

  @HiveField(12)
  final BookSourceType sourceType;

  @HiveField(13)
  final String? sourceUri;

  @HiveField(14)
  final ReadingMode readingMode;

  @HiveField(15)
  int lastReadingSentenceStart;

  @HiveField(16)
  int lastReadingSentenceEnd;

  @HiveField(17)
  int lastTtsSentenceStart;

  @HiveField(18)
  int lastTtsSentenceEnd;

  @HiveField(19)
  int lastTtsPage;

  @HiveField(20)
  int lastTtsSection;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.format,
    this.currentPage = 0,
    this.totalPages = 0,
    this.sectionIndex = 0,
    this.scrollPosition = 0.0,
    this.coverPath,
    this.sourceType = BookSourceType.imported,
    this.sourceUri,
    this.readingMode = ReadingMode.verticalContinuous,
    this.lastReadingSentenceStart = -1,
    this.lastReadingSentenceEnd = -1,
    this.lastTtsSentenceStart = -1,
    this.lastTtsSentenceEnd = -1,
    this.lastTtsPage = 0,
    this.lastTtsSection = 0,
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
    BookSourceType? sourceType,
    String? sourceUri,
    ReadingMode? readingMode,
    int? lastReadingSentenceStart,
    int? lastReadingSentenceEnd,
    int? lastTtsSentenceStart,
    int? lastTtsSentenceEnd,
    int? lastTtsPage,
    int? lastTtsSection,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath,
      format: format,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      sectionIndex: sectionIndex ?? this.sectionIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      coverPath: coverPath ?? this.coverPath,
      sourceType: sourceType ?? this.sourceType,
      sourceUri: sourceUri ?? this.sourceUri,
      readingMode: readingMode ?? this.readingMode,
      lastReadingSentenceStart:
          lastReadingSentenceStart ?? this.lastReadingSentenceStart,
      lastReadingSentenceEnd:
          lastReadingSentenceEnd ?? this.lastReadingSentenceEnd,
      lastTtsSentenceStart: lastTtsSentenceStart ?? this.lastTtsSentenceStart,
      lastTtsSentenceEnd: lastTtsSentenceEnd ?? this.lastTtsSentenceEnd,
      lastTtsPage: lastTtsPage ?? this.lastTtsPage,
      lastTtsSection: lastTtsSection ?? this.lastTtsSection,
      lastOpened: lastOpened ?? this.lastOpened,
      addedAt: addedAt,
    );
  }
}
