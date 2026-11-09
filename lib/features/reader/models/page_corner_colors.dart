import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Holds the corner and edge colors extracted from a comic/manga page.
@immutable
class PageCornerColors {
  final Color topLeft;
  final Color topRight;
  final Color bottomLeft;
  final Color bottomRight;

  final Color topColor;
  final Color bottomColor;
  final Color leftColor;
  final Color rightColor;

  const PageCornerColors({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.topColor,
    required this.bottomColor,
    required this.leftColor,
    required this.rightColor,
  });

  /// Default fallback when colors cannot be extracted or page is loading.
  factory PageCornerColors.fallback({Color? baseColor}) {
    final color = baseColor ?? const Color(0xFF18181A);
    return PageCornerColors(
      topLeft: color,
      topRight: color,
      bottomLeft: color,
      bottomRight: color,
      topColor: color,
      bottomColor: color,
      leftColor: color,
      rightColor: color,
    );
  }

  /// Extracts corner and edge colors from raw RGBA8888 byte buffer.
  ///
  /// Insets sampling 1.5% from edges (clamped between 2 and 12 px)
  /// to eliminate scanner crop black borders, bleed marks, and digitized noise.
  factory PageCornerColors.fromRgbaBytes(
    Uint8List bytes,
    int width,
    int height, {
    Color? fallbackColor,
  }) {
    if (bytes.isEmpty || width <= 0 || height <= 0 || bytes.length < width * height * 4) {
      return PageCornerColors.fallback(baseColor: fallbackColor);
    }

    final insetX = (width * 0.015).round().clamp(2, 12);
    final insetY = (height * 0.015).round().clamp(2, 12);
    final patchW = (width * 0.02).round().clamp(4, 16);
    final patchH = (height * 0.02).round().clamp(4, 16);

    final tl = _samplePatch(
      bytes,
      width,
      height,
      startX: insetX,
      endX: (insetX + patchW).clamp(0, width),
      startY: insetY,
      endY: (insetY + patchH).clamp(0, height),
      fallback: fallbackColor,
    );

    final tr = _samplePatch(
      bytes,
      width,
      height,
      startX: (width - insetX - patchW).clamp(0, width),
      endX: (width - insetX).clamp(0, width),
      startY: insetY,
      endY: (insetY + patchH).clamp(0, height),
      fallback: fallbackColor,
    );

    final bl = _samplePatch(
      bytes,
      width,
      height,
      startX: insetX,
      endX: (insetX + patchW).clamp(0, width),
      startY: (height - insetY - patchH).clamp(0, height),
      endY: (height - insetY).clamp(0, height),
      fallback: fallbackColor,
    );

    final br = _samplePatch(
      bytes,
      width,
      height,
      startX: (width - insetX - patchW).clamp(0, width),
      endX: (width - insetX).clamp(0, width),
      startY: (height - insetY - patchH).clamp(0, height),
      endY: (height - insetY).clamp(0, height),
      fallback: fallbackColor,
    );

    return PageCornerColors(
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
      topColor: _blendColors(tl, tr),
      bottomColor: _blendColors(bl, br),
      leftColor: _blendColors(tl, bl),
      rightColor: _blendColors(tr, br),
    );
  }

  static Color _samplePatch(
    Uint8List bytes,
    int width,
    int height, {
    required int startX,
    required int endX,
    required int startY,
    required int endY,
    Color? fallback,
  }) {
    if (startX >= endX || startY >= endY) {
      return fallback ?? const Color(0xFF18181A);
    }

    int totalR = 0;
    int totalG = 0;
    int totalB = 0;
    int count = 0;

    for (int y = startY; y < endY; y++) {
      final rowOffset = y * width * 4;
      for (int x = startX; x < endX; x++) {
        final offset = rowOffset + (x * 4);
        if (offset + 3 >= bytes.length) continue;

        final r = bytes[offset];
        final g = bytes[offset + 1];
        final b = bytes[offset + 2];
        final a = bytes[offset + 3];

        // Skip fully or mostly transparent pixels
        if (a > 32) {
          totalR += r;
          totalG += g;
          totalB += b;
          count++;
        }
      }
    }

    if (count == 0) {
      return fallback ?? const Color(0xFF18181A);
    }

    return Color.fromARGB(
      255,
      totalR ~/ count,
      totalG ~/ count,
      totalB ~/ count,
    );
  }

  static Color _blendColors(Color c1, Color c2) {
    return Color.fromARGB(
      255,
      ((c1.r * 255 + c2.r * 255) / 2).round().clamp(0, 255),
      ((c1.g * 255 + c2.g * 255) / 2).round().clamp(0, 255),
      ((c1.b * 255 + c2.b * 255) / 2).round().clamp(0, 255),
    );
  }

  /// Linearly interpolate between two [PageCornerColors] instances.
  static PageCornerColors? lerp(PageCornerColors? a, PageCornerColors? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;

    return PageCornerColors(
      topLeft: Color.lerp(a.topLeft, b.topLeft, t) ?? b.topLeft,
      topRight: Color.lerp(a.topRight, b.topRight, t) ?? b.topRight,
      bottomLeft: Color.lerp(a.bottomLeft, b.bottomLeft, t) ?? b.bottomLeft,
      bottomRight: Color.lerp(a.bottomRight, b.bottomRight, t) ?? b.bottomRight,
      topColor: Color.lerp(a.topColor, b.topColor, t) ?? b.topColor,
      bottomColor: Color.lerp(a.bottomColor, b.bottomColor, t) ?? b.bottomColor,
      leftColor: Color.lerp(a.leftColor, b.leftColor, t) ?? b.leftColor,
      rightColor: Color.lerp(a.rightColor, b.rightColor, t) ?? b.rightColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageCornerColors &&
          runtimeType == other.runtimeType &&
          topColor == other.topColor &&
          bottomColor == other.bottomColor &&
          leftColor == other.leftColor &&
          rightColor == other.rightColor &&
          topLeft == other.topLeft &&
          topRight == other.topRight &&
          bottomLeft == other.bottomLeft &&
          bottomRight == other.bottomRight;

  @override
  int get hashCode =>
      topColor.hashCode ^
      bottomColor.hashCode ^
      leftColor.hashCode ^
      rightColor.hashCode ^
      topLeft.hashCode ^
      topRight.hashCode ^
      bottomLeft.hashCode ^
      bottomRight.hashCode;
}
