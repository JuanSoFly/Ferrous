import 'package:hive/hive.dart';
import 'package:reader_app/data/models/book.dart';

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
      path: fields[3] as String,
      format: fields[4] as String,
      currentPage: fields[5] as int,
      totalPages: fields[6] as int,
      lastOpened: fields[7] as DateTime?,
      addedAt: fields[8] as DateTime?,
      sectionIndex: fields[9] as int? ?? 0,
      scrollPosition: fields[10] as double? ?? 0.0,
      coverPath: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Book obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.path)
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
      ..write(obj.coverPath);
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
