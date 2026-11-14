// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_theme_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReaderThemeConfigAdapter extends TypeAdapter<ReaderThemeConfig> {
  @override
  final typeId = 3;

  @override
  ReaderThemeConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReaderThemeConfig();
  }

  @override
  void write(BinaryWriter writer, ReaderThemeConfig obj) {
    writer.writeByte(0);
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
