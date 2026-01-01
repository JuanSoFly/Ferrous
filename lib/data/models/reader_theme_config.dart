import 'package:hive/hive.dart';

part 'reader_theme_config.g.dart';

// Hive typeIds must be unique. Collection is 2.
@HiveType(typeId: 3)
class ReaderThemeConfig {
  @HiveField(0)
  final double fontSize;

  @HiveField(1)
  final String fontFamily;

  @HiveField(2)
  final double lineHeight;

  @HiveField(3)
  final double paragraphSpacing;

  @HiveField(4)
  final String textAlign;

  @HiveField(5)
  final bool pageMargins;

  @HiveField(6)
  final bool pageFlip;

  @HiveField(7)
  final double wordSpacing;

  @HiveField(8)
  final bool paragraphIndent;

  @HiveField(9)
  final bool hyphenation;

  @HiveField(10)
  final int fontWeight;

  const ReaderThemeConfig({
    this.fontSize = 20.0,
    this.fontFamily = 'Roboto',
    this.lineHeight = 1.5,
    this.paragraphSpacing = 10.0,
    this.textAlign = 'justify',
    this.pageMargins = true,
    this.pageFlip = false,
    this.wordSpacing = 0.0,
    this.paragraphIndent = false,
    this.hyphenation = false,
    this.fontWeight = 400,
  });

  ReaderThemeConfig copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    double? paragraphSpacing,
    String? textAlign,
    bool? pageMargins,
    bool? pageFlip,
    double? wordSpacing,
    bool? paragraphIndent,
    bool? hyphenation,
    int? fontWeight,
  }) {
    return ReaderThemeConfig(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textAlign: textAlign ?? this.textAlign,
      pageMargins: pageMargins ?? this.pageMargins,
      pageFlip: pageFlip ?? this.pageFlip,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      paragraphIndent: paragraphIndent ?? this.paragraphIndent,
      hyphenation: hyphenation ?? this.hyphenation,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }
}
