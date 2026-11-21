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

  @HiveField(11)
  final String paperTexture;

  @HiveField(12)
  final bool showBookSpine;

  @HiveField(13)
  final bool usePublisherStyles;

  const ReaderThemeConfig({
    this.fontSize = 12.0,
    this.fontFamily = 'Merriweather',
    this.lineHeight = 1.5,
    this.paragraphSpacing = 4.0,
    this.textAlign = 'justify',
    this.pageMargins = true,
    this.pageFlip = true,
    this.wordSpacing = 0.0,
    this.paragraphIndent = true,
    this.hyphenation = true,
    this.fontWeight = 400,
    this.paperTexture = 'natural',
    this.showBookSpine = true,
    this.usePublisherStyles = false,
  });

  static double sanitizeLineHeight(double? h) {
    if (h == null || h < 1.0) return 1.4;
    return h.clamp(1.0, 2.2);
  }

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
    String? paperTexture,
    bool? showBookSpine,
    bool? usePublisherStyles,
  }) {
    return ReaderThemeConfig(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight != null ? sanitizeLineHeight(lineHeight) : this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textAlign: textAlign ?? this.textAlign,
      pageMargins: pageMargins ?? this.pageMargins,
      pageFlip: pageFlip ?? this.pageFlip,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      paragraphIndent: paragraphIndent ?? this.paragraphIndent,
      hyphenation: hyphenation ?? this.hyphenation,
      fontWeight: fontWeight ?? this.fontWeight,
      paperTexture: paperTexture ?? this.paperTexture,
      showBookSpine: showBookSpine ?? this.showBookSpine,
      usePublisherStyles: usePublisherStyles ?? this.usePublisherStyles,
    );
  }
}
