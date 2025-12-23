// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_theme_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReaderThemeConfigAdapter extends TypeAdapter<ReaderThemeConfig> {
  @override
  final int typeId = 2;

  @override
  ReaderThemeConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReaderThemeConfig(
      fontSize: fields[0] as double? ?? 20.0,
      fontFamily: fields[1] as String? ?? 'Roboto',
      lineHeight: fields[2] as double? ?? 1.5,
      paragraphSpacing: fields[3] as double? ?? 10.0,
      textAlign: fields[4] as String? ?? 'justify',
      pageMargins: fields[5] as bool? ?? true,
      pageFlip: fields[6] as bool? ?? false,
      wordSpacing: fields[7] as double? ?? 0.0,
      paragraphIndent: fields[8] as bool? ?? false,
      hyphenation: fields[9] as bool? ?? false,
      fontWeight: fields[10] as int? ?? 400,
    );
  }

  @override
  void write(BinaryWriter writer, ReaderThemeConfig obj) {
    writer
      ..writeByte(11) // number of fields
      ..writeByte(0)
      ..write(obj.fontSize)
      ..writeByte(1)
      ..write(obj.fontFamily)
      ..writeByte(2)
      ..write(obj.lineHeight)
      ..writeByte(3)
      ..write(obj.paragraphSpacing)
      ..writeByte(4)
      ..write(obj.textAlign)
      ..writeByte(5)
      ..write(obj.pageMargins)
      ..writeByte(6)
      ..write(obj.pageFlip)
      ..writeByte(7)
      ..write(obj.wordSpacing)
      ..writeByte(8)
      ..write(obj.paragraphIndent)
      ..writeByte(9)
      ..write(obj.hyphenation)
      ..writeByte(10)
      ..write(obj.fontWeight);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderThemeConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
