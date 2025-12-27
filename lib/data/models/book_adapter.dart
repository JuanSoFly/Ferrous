import 'package:hive/hive.dart';
import 'package:reader_app/core/models/book.dart';

class BookAdapter extends TypeAdapter<Book> {
  @override
  final int typeId = 0;

  @override
  Book read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Book(
      id: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      filePath: fields[3] as String? ?? '',
      format: fields[4] as String,
      currentPage: fields[5] as int,
      totalPages: fields[6] as int,
      lastOpened: fields[7] as DateTime?,
      addedAt: fields[8] as DateTime?,
      sectionIndex: fields[9] as int? ?? 0,
      scrollPosition: fields[10] as double? ?? 0.0,
      coverPath: fields[11] as String?,
      sourceType: parseBookSourceType(fields[12] as String?),
      sourceUri: fields[13] as String?,
      readingMode: parseReadingMode(fields[14] as String?),
      lastReadingSentenceStart: fields[15] as int? ?? -1,
      lastReadingSentenceEnd: fields[16] as int? ?? -1,
      lastTtsSentenceStart: fields[17] as int? ?? -1,
      lastTtsSentenceEnd: fields[18] as int? ?? -1,
      lastTtsPage: fields[19] as int? ?? 0,
      lastTtsSection: fields[20] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, Book obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.filePath)
      ..writeByte(4)
      ..write(obj.format)
      ..writeByte(5)
      ..write(obj.currentPage)
      ..writeByte(6)
      ..write(obj.totalPages)
      ..writeByte(7)
      ..write(obj.lastOpened)
      ..writeByte(8)
      ..write(obj.addedAt)
      ..writeByte(9)
      ..write(obj.sectionIndex)
      ..writeByte(10)
      ..write(obj.scrollPosition)
      ..writeByte(11)
      ..write(obj.coverPath)
      ..writeByte(12)
      ..write(obj.sourceType.name)
      ..writeByte(13)
      ..write(obj.sourceUri)
      ..writeByte(14)
      ..write(obj.readingMode.name)
      ..writeByte(15)
      ..write(obj.lastReadingSentenceStart)
      ..writeByte(16)
      ..write(obj.lastReadingSentenceEnd)
      ..writeByte(17)
      ..write(obj.lastTtsSentenceStart)
      ..writeByte(18)
      ..write(obj.lastTtsSentenceEnd)
      ..writeByte(19)
      ..write(obj.lastTtsPage)
      ..writeByte(20)
      ..write(obj.lastTtsSection);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
