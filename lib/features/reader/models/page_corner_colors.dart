import 'dart:math' as math;
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

  /// Multi-stop horizontal color profiles for seamless letterbox rendering
  /// across split-tone and graphic borders (e.g. Avengers credit page).
  final List<Color> topProfile;
  final List<Color> bottomProfile;

  /// True when the page is classified as monochrome/manga printed on white paper.
  final bool isMangaWhitePaper;

  const PageCornerColors({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.topColor,
    required this.bottomColor,
    required this.leftColor,
    required this.rightColor,
    required this.topProfile,
    required this.bottomProfile,
    this.isMangaWhitePaper = false,
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
      topProfile: List.filled(8, color),
      bottomProfile: List.filled(8, color),
      isMangaWhitePaper: false,
    );
  }

  /// Extracts dominant edge profiles and canvas colors from raw RGBA8888 byte buffer.
  ///
  /// Uses a 3-depth band sampling grid (3px, 7px, 12px) with exact-sum clustering
  /// to eliminate scanner crops, panel borders, and screentone noise while preserving
  /// true paper margins and full-bleed artwork.
  factory PageCornerColors.fromRgbaBytes(
    Uint8List bytes,
    int width,
    int height, {
    Color? fallbackColor,
  }) {
    final fallback = fallbackColor ?? const Color(0xFF18181A);
    if (bytes.isEmpty || width <= 0 || height <= 0 || bytes.length < width * height * 4) {
      return PageCornerColors.fallback(baseColor: fallback);
    }

    final minDim = math.min(width, height);
    final maxAllowedDepth = math.max(2, minDim ~/ 10);
    final depths = [
      3.clamp(1, maxAllowedDepth),
      7.clamp(1, maxAllowedDepth),
      12.clamp(1, maxAllowedDepth),
    ];

    const int numSteps = 32;
    final minX = (width * 0.05).round().clamp(0, width - 1);
    final maxX = (width * 0.95).round().clamp(minX + 1, width);
    final minY = (height * 0.05).round().clamp(0, height - 1);
    final maxY = (height * 0.95).round().clamp(minY + 1, height);

    // 1. Collect all perimeter samples for Page Classification
    int totalPerimeterSamples = 0;
    int whitePerimeterSamples = 0;
    int blackPerimeterSamples = 0;
    double totalSaturation = 0.0;

    int topWhiteSamples = 0;
    int bottomWhiteSamples = 0;
    int leftWhiteSamples = 0;
    int rightWhiteSamples = 0;

    // Top & Bottom 8-segment local collectors (4 horizontal steps x 3 depths = 12 samples per segment)
    final topSegments = List.generate(8, (_) => <Color>[]);
    final bottomSegments = List.generate(8, (_) => <Color>[]);

    // Sample Top edge
    for (int step = 0; step < numSteps; step++) {
      final x = (minX + (step + 0.5) * (maxX - minX) / numSteps).round().clamp(0, width - 1);
      final segmentIdx = (step * 8 ~/ numSteps).clamp(0, 7);

      for (final d in depths) {
        final y = d.clamp(0, height - 1);
        final color = _getPixelColor(bytes, width, x, y);
        if (color == null) continue;

        totalPerimeterSamples++;
        totalSaturation += _getSaturation(color);
        if (_isWhite(color)) {
          whitePerimeterSamples++;
          topWhiteSamples++;
        } else if (_isBlack(color)) {
          blackPerimeterSamples++;
        }
        topSegments[segmentIdx].add(color);
      }
    }

    // Sample Bottom edge
    for (int step = 0; step < numSteps; step++) {
      final x = (minX + (step + 0.5) * (maxX - minX) / numSteps).round().clamp(0, width - 1);
      final segmentIdx = (step * 8 ~/ numSteps).clamp(0, 7);

      for (final d in depths) {
        final y = (height - 1 - d).clamp(0, height - 1);
        final color = _getPixelColor(bytes, width, x, y);
        if (color == null) continue;

        totalPerimeterSamples++;
        totalSaturation += _getSaturation(color);
        if (_isWhite(color)) {
          whitePerimeterSamples++;
          bottomWhiteSamples++;
        } else if (_isBlack(color)) {
          blackPerimeterSamples++;
        }
        bottomSegments[segmentIdx].add(color);
      }
    }

    // Sample Left & Right edges
    final leftSamples = <Color>[];
    final rightSamples = <Color>[];

    for (int step = 0; step < numSteps; step++) {
      final y = (minY + (step + 0.5) * (maxY - minY) / numSteps).round().clamp(0, height - 1);

      for (final d in depths) {
        // Left
        final xl = d.clamp(0, width - 1);
        final cl = _getPixelColor(bytes, width, xl, y);
        if (cl != null) {
          totalPerimeterSamples++;
          totalSaturation += _getSaturation(cl);
          if (_isWhite(cl)) {
            whitePerimeterSamples++;
            leftWhiteSamples++;
          } else if (_isBlack(cl)) {
            blackPerimeterSamples++;
          }
          leftSamples.add(cl);
        }

        // Right
        final xr = (width - 1 - d).clamp(0, width - 1);
        final cr = _getPixelColor(bytes, width, xr, y);
        if (cr != null) {
          totalPerimeterSamples++;
          totalSaturation += _getSaturation(cr);
          if (_isWhite(cr)) {
            whitePerimeterSamples++;
            rightWhiteSamples++;
          } else if (_isBlack(cr)) {
            blackPerimeterSamples++;
          }
          rightSamples.add(cr);
        }
      }
    }

    if (totalPerimeterSamples == 0) {
      return PageCornerColors.fallback(baseColor: fallback);
    }

    final avgSaturation = totalSaturation / totalPerimeterSamples;
    final whiteRatio = whitePerimeterSamples / totalPerimeterSamples;
    final blackRatio = blackPerimeterSamples / totalPerimeterSamples;

    final topWhiteRatio = topSegments.expand((s) => s).isEmpty ? 0.0 : topWhiteSamples / (numSteps * depths.length);
    final bottomWhiteRatio = bottomSegments.expand((s) => s).isEmpty ? 0.0 : bottomWhiteSamples / (numSteps * depths.length);
    final leftWhiteRatio = leftSamples.isEmpty ? 0.0 : leftWhiteSamples / leftSamples.length;
    final rightWhiteRatio = rightSamples.isEmpty ? 0.0 : rightWhiteSamples / rightSamples.length;
    final anyEdgeWhite60 = topWhiteRatio >= 0.60 || bottomWhiteRatio >= 0.60 || leftWhiteRatio >= 0.60 || rightWhiteRatio >= 0.60;

    // 2. Manga Paper Lock:
    // If the page is monochrome (avgSaturation < 0.12) and has at least 25% white perimeter samples
    // (or any single margin >= 60% white) while not being an intentional night/black page (< 65% black),
    // force all letterbox edges and stops to pure #FFFFFF so bleed panels never turn bars gray.
    final isWhiteManga = avgSaturation < 0.12 && (whiteRatio >= 0.25 || anyEdgeWhite60) && blackRatio < 0.65;
    if (isWhiteManga) {
      const pureWhite = Color(0xFFFFFFFF);
      return PageCornerColors(
        topLeft: pureWhite,
        topRight: pureWhite,
        bottomLeft: pureWhite,
        bottomRight: pureWhite,
        topColor: pureWhite,
        bottomColor: pureWhite,
        leftColor: pureWhite,
        rightColor: pureWhite,
        topProfile: List.filled(8, pureWhite),
        bottomProfile: List.filled(8, pureWhite),
        isMangaWhitePaper: true,
      );
    }

    // Pure black night page check
    if (avgSaturation < 0.12 && blackRatio >= 0.85) {
      const pureBlack = Color(0xFF000000);
      return PageCornerColors(
        topLeft: pureBlack,
        topRight: pureBlack,
        bottomLeft: pureBlack,
        bottomRight: pureBlack,
        topColor: pureBlack,
        bottomColor: pureBlack,
        leftColor: pureBlack,
        rightColor: pureBlack,
        topProfile: List.filled(8, pureBlack),
        bottomProfile: List.filled(8, pureBlack),
        isMangaWhitePaper: false,
      );
    }

    // 3. Color Pages / Split-tone Profiles:
    // Analyze Top 8 segments
    final rawTopProfile = <Color>[];
    int topStableCount = 0;
    for (final seg in topSegments) {
      final result = _clusterDominantColor(seg, fallback);
      rawTopProfile.add(result.$1);
      if (result.$2 >= 0.55) topStableCount++;
    }

    // Analyze Bottom 8 segments
    final rawBottomProfile = <Color>[];
    int bottomStableCount = 0;
    for (final seg in bottomSegments) {
      final result = _clusterDominantColor(seg, fallback);
      rawBottomProfile.add(result.$1);
      if (result.$2 >= 0.55) bottomStableCount++;
    }

    // Despike isolated single-segment narrow spikes (chevron/slash)
    final despikedTop = _despikeProfile(rawTopProfile);
    final despikedBottom = _despikeProfile(rawBottomProfile);

    // If >= 6 of 8 segments are internally stable, it is a graphic / split-tone border.
    // Otherwise, it is chaotic artwork (skulls, embers) -> terminate in deep neutral black (#080808).
    const deepBlack = Color(0xFF080808);

    final List<Color> finalTopProfile;
    final Color finalTopColor;
    if (topStableCount >= 6) {
      finalTopProfile = despikedTop;
      finalTopColor = _findDominantInProfile(despikedTop);
    } else {
      finalTopProfile = List.filled(8, deepBlack);
      finalTopColor = deepBlack;
    }

    final List<Color> finalBottomProfile;
    final Color finalBottomColor;
    if (bottomStableCount >= 6) {
      finalBottomProfile = despikedBottom;
      finalBottomColor = _findDominantInProfile(despikedBottom);
    } else {
      finalBottomProfile = List.filled(8, deepBlack);
      finalBottomColor = deepBlack;
    }

    final finalLeftColor = _clusterDominantColor(leftSamples, fallback).$1;
    final finalRightColor = _clusterDominantColor(rightSamples, fallback).$1;

    return PageCornerColors(
      topLeft: finalTopProfile.first,
      topRight: finalTopProfile.last,
      bottomLeft: finalBottomProfile.first,
      bottomRight: finalBottomProfile.last,
      topColor: finalTopColor,
      bottomColor: finalBottomColor,
      leftColor: finalLeftColor,
      rightColor: finalRightColor,
      topProfile: finalTopProfile,
      bottomProfile: finalBottomProfile,
      isMangaWhitePaper: false,
    );
  }

  static Color? _getPixelColor(Uint8List bytes, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    if (offset + 3 >= bytes.length) return null;
    final a = bytes[offset + 3];
    if (a < 32) return null;
    return Color.fromARGB(255, bytes[offset], bytes[offset + 1], bytes[offset + 2]);
  }

  static double _getSaturation(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    if (max <= 0) return 0.0;
    return (max - min) / max;
  }

  static bool _isWhite(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return r >= 240 && g >= 240 && b >= 240;
  }

  static bool _isBlack(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return r <= 25 && g <= 25 && b <= 25;
  }

  /// Clusters colors into 16-step bins with adjacent L1 merging and exact-sum averaging.
  /// Returns the winning Color and the dominance percentage (0.0 to 1.0).
  static (Color, double) _clusterDominantColor(List<Color> samples, Color fallback) {
    if (samples.isEmpty) return (fallback, 0.0);

    final Map<int, _ColorBucket> buckets = {};

    for (final s in samples) {
      final r = (s.r * 255).round();
      final g = (s.g * 255).round();
      final b = (s.b * 255).round();

      final binR = (r ~/ 16).clamp(0, 15);
      final binG = (g ~/ 16).clamp(0, 15);
      final binB = (b ~/ 16).clamp(0, 15);
      final key = (binR << 8) | (binG << 4) | binB;

      buckets.putIfAbsent(key, _ColorBucket.new).add(r, g, b);
    }

    // Merge adjacent bins with Manhattan distance L1 <= 1
    _ColorBucket? bestBucket;
    int maxMergedCount = -1;

    for (final entry in buckets.entries) {
      final k = entry.key;
      final br = (k >> 8) & 0x0F;
      final bg = (k >> 4) & 0x0F;
      final bb = k & 0x0F;

      final merged = _ColorBucket();
      merged.mergeFrom(entry.value);

      // Check all 6 immediately adjacent neighbors
      const neighbors = [
        [-1, 0, 0], [1, 0, 0],
        [0, -1, 0], [0, 1, 0],
        [0, 0, -1], [0, 0, 1],
      ];

      for (final n in neighbors) {
        final nr = br + n[0];
        final ng = bg + n[1];
        final nb = bb + n[2];
        if (nr >= 0 && nr <= 15 && ng >= 0 && ng <= 15 && nb >= 0 && nb <= 15) {
          final nKey = (nr << 8) | (ng << 4) | nb;
          final neighborBucket = buckets[nKey];
          if (neighborBucket != null) {
            merged.mergeFrom(neighborBucket);
          }
        }
      }

      if (merged.count > maxMergedCount) {
        maxMergedCount = merged.count;
        bestBucket = merged;
      }
    }

    if (bestBucket == null || bestBucket.count == 0) {
      return (fallback, 0.0);
    }

    final dominance = (bestBucket.count / samples.length).clamp(0.0, 1.0);
    return (bestBucket.averageColor, dominance);
  }

  /// Despikes single-segment narrow spikes (e.g. white chevron in 6.png or black 'A' in 5.png).
  /// Also despikes endpoints k = 0 and k = 7 (User Guard 2).
  static List<Color> _despikeProfile(List<Color> profile) {
    if (profile.length != 8) return profile;
    final result = List<Color>.from(profile);

    // Despike interior segments k = 1..6
    for (int k = 1; k <= 6; k++) {
      final prev = result[k - 1];
      final curr = result[k];
      final next = result[k + 1];

      final dPrev = _colorDistance(curr, prev);
      final dNext = _colorDistance(curr, next);
      final dNeighbors = _colorDistance(prev, next);

      if (dPrev > 40.0 && dNext > 40.0 && dNeighbors < 30.0) {
        result[k] = _blendColors(prev, next);
      }
    }

    // Endpoint despike k = 0 (Guard 2)
    if (_colorDistance(result[0], result[1]) > 40.0 && _colorDistance(result[1], result[2]) < 25.0) {
      result[0] = result[1];
    }

    // Endpoint despike k = 7 (Guard 2)
    if (_colorDistance(result[7], result[6]) > 40.0 && _colorDistance(result[6], result[5]) < 25.0) {
      result[7] = result[6];
    }

    return result;
  }

  static double _colorDistance(Color c1, Color c2) {
    final dr = (c1.r * 255 - c2.r * 255);
    final dg = (c1.g * 255 - c2.g * 255);
    final db = (c1.b * 255 - c2.b * 255);
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  static Color _findDominantInProfile(List<Color> profile) {
    if (profile.isEmpty) return const Color(0xFF18181A);
    // Return midpoint of profile as representative color
    return profile[profile.length ~/ 2];
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

    final lerpedTopProfile = List.generate(8, (i) {
      final ca = i < a.topProfile.length ? a.topProfile[i] : a.topColor;
      final cb = i < b.topProfile.length ? b.topProfile[i] : b.topColor;
      return Color.lerp(ca, cb, t) ?? cb;
    });

    final lerpedBottomProfile = List.generate(8, (i) {
      final ca = i < a.bottomProfile.length ? a.bottomProfile[i] : a.bottomColor;
      final cb = i < b.bottomProfile.length ? b.bottomProfile[i] : b.bottomColor;
      return Color.lerp(ca, cb, t) ?? cb;
    });

    return PageCornerColors(
      topLeft: Color.lerp(a.topLeft, b.topLeft, t) ?? b.topLeft,
      topRight: Color.lerp(a.topRight, b.topRight, t) ?? b.topRight,
      bottomLeft: Color.lerp(a.bottomLeft, b.bottomLeft, t) ?? b.bottomLeft,
      bottomRight: Color.lerp(a.bottomRight, b.bottomRight, t) ?? b.bottomRight,
      topColor: Color.lerp(a.topColor, b.topColor, t) ?? b.topColor,
      bottomColor: Color.lerp(a.bottomColor, b.bottomColor, t) ?? b.bottomColor,
      leftColor: Color.lerp(a.leftColor, b.leftColor, t) ?? b.leftColor,
      rightColor: Color.lerp(a.rightColor, b.rightColor, t) ?? b.rightColor,
      topProfile: lerpedTopProfile,
      bottomProfile: lerpedBottomProfile,
      isMangaWhitePaper: t < 0.5 ? a.isMangaWhitePaper : b.isMangaWhitePaper,
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
          bottomRight == other.bottomRight &&
          isMangaWhitePaper == other.isMangaWhitePaper;

  @override
  int get hashCode =>
      topColor.hashCode ^
      bottomColor.hashCode ^
      leftColor.hashCode ^
      rightColor.hashCode ^
      topLeft.hashCode ^
      topRight.hashCode ^
      bottomLeft.hashCode ^
      bottomRight.hashCode ^
      isMangaWhitePaper.hashCode;
}

class _ColorBucket {
  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;

  void add(int r, int g, int b) {
    count++;
    sumR += r;
    sumG += g;
    sumB += b;
  }

  void mergeFrom(_ColorBucket other) {
    count += other.count;
    sumR += other.sumR;
    sumG += other.sumG;
    sumB += other.sumB;
  }

  Color get averageColor {
    if (count == 0) return const Color(0xFF18181A);
    final r = (sumR / count).round().clamp(0, 255);
    final g = (sumG / count).round().clamp(0, 255);
    final b = (sumB / count).round().clamp(0, 255);

    // Snap pure white (eliminates JPEG compression ringing on manga margins)
    if (r >= 248 && g >= 248 && b >= 248) {
      return const Color(0xFFFFFFFF);
    }
    // Snap deep black
    if (r <= 8 && g <= 8 && b <= 8) {
      return const Color(0xFF000000);
    }
    return Color.fromARGB(255, r, g, b);
  }
}
