import 'package:hive/hive.dart';
import 'package:reader_app/core/models/annotation.dart';

class AnnotationAdapter extends TypeAdapter<Annotation> {
  @override
  final int typeId = 1;

  @override
  Annotation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Annotation(
      id: fields[0] as String,
      bookId: fields[1] as String,
      selectedText: fields[2] as String,
      note: fields[3] as String?,
      chapterIndex: fields[4] as int,
      startOffset: fields[5] as int,
      endOffset: fields[6] as int,
      color: fields[7] as int,
      createdAt: fields[8] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Annotation obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.bookId)
      ..writeByte(2)
      ..write(obj.selectedText)
      ..writeByte(3)
      ..write(obj.note)
      ..writeByte(4)
      ..write(obj.chapterIndex)
      ..writeByte(5)
      ..write(obj.startOffset)
      ..writeByte(6)
      ..write(obj.endOffset)
      ..writeByte(7)
      ..write(obj.color)
      ..writeByte(8)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnotationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
