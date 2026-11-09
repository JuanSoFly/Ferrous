import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Central tokens and physics for Kindle Carta 1300 E-Ink Paper mode.
class EInkTokens {
  EInkTokens._();

  // 1. Primary Paper Surface (All Screen BGs, Reader BG, Nav Bars)
  // Warm matte Carta e-paper — never cold gray or pure #FFFFFF.
  static const Color paperSurface = Color(0xFFEAE6DF);

  // 2. Secondary Paper Surface (Cards, Search Input, Unselected Tabs)
  static const Color paperSecondary = Color(0xFFE0DCD3);

  // 3. Halftone Highlight Surface (Quotes & Text Highlights)
  // Warm halftone gray — strictly ban all yellow #FFF... marker colors.
  static const Color halftoneHighlight = Color(0xFFD5D0C5);

  // 4. Primary Carbon Ink (Text, Borders, Active Fills, Icons)
  // Dense matte ink, never #000000.
  static const Color carbonInk = Color(0xFF1A1A18);

  // 5. Secondary Ink (Subtitles, Author Names, Dates, Percentages)
  static const Color secondaryInk = Color(0xFF3D3C38);

  // 6. Structural Hairline Ink (Dividers & Card Borders)
  static const Color hairlineInk = Color(0xFF9E9A90);

  // Inactive Nav Ink
  static const Color inactiveNavInk = Color(0xFF4A4945);

  // Editorial leader lines
  static const Color leaderLine = Color(0xFFC2BEB4);

  /// Grayscale (100%), Contrast (125%), Brightness (95%) matrix for book cover images.
  /// Guarantees zero RGB color leaks through in E-Ink Paper mode.
  static const ColorFilter coverFilter = ColorFilter.matrix(<double>[
    0.2525, 0.8493, 0.0857, 0, -30.3,
    0.2525, 0.8493, 0.0857, 0, -30.3,
    0.2525, 0.8493, 0.0857, 0, -30.3,
    0,      0,      0,      1, 0,
  ]);

  /// Subtle physical carbon ink-bleed text shadow: 0 0 0.35px rgba(26, 26, 24, 0.25).
  static const Shadow inkBleed = Shadow(
    color: Color(0x401A1A18),
    offset: Offset.zero,
    blurRadius: 0.35,
  );
}

/// Full-viewport matte paper grain noise overlay.
/// Simulates physical Kindle Carta 1300 micro-texture with high-frequency fractal noise,
/// mix-blend-mode: multiply, and opacity: 0.045.
class EInkPaperNoiseOverlay extends StatefulWidget {
  const EInkPaperNoiseOverlay({super.key});

  @override
  State<EInkPaperNoiseOverlay> createState() => _EInkPaperNoiseOverlayState();
}

class _EInkPaperNoiseOverlayState extends State<EInkPaperNoiseOverlay> {
  static ui.Image? _cachedNoiseImage;
  static bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    if (_cachedNoiseImage == null && !_isGenerating) {
      _generateNoiseImage();
    }
  }

  void _generateNoiseImage() {
    _isGenerating = true;
    const int size = 128;
    final Uint8List pixels = Uint8List(size * size * 4);

    // 4-octave pseudo-random fractal noise generator with base frequency ~0.85
    int seed = 918273;
    double nextDouble() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    // Pre-fill a deterministic noise grid
    final grid = List.generate(
      size,
      (_) => List.generate(size, (_) => nextDouble()),
    );

    int idx = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        // Multi-octave accumulation
        double val = 0.0;
        double amp = 0.55;
        double totalAmp = 0.0;

        for (int oct = 0; oct < 4; oct++) {
          final int step = (1 << oct);
          final int nx = (x * step) % size;
          final int ny = (y * step) % size;
          val += grid[ny][nx] * amp;
          totalAmp += amp;
          amp *= 0.5;
        }

        val /= totalAmp;
        // Grayscale byte value (0 to 255)
        final int byteVal = (val * 255).clamp(0, 255).toInt();

        // RGBA: carbon dark specks
        pixels[idx] = byteVal;
        pixels[idx + 1] = byteVal;
        pixels[idx + 2] = byteVal;
        pixels[idx + 3] = 255;
        idx += 4;
      }
    }

    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedNoiseImage = image;
        _isGenerating = false;
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedNoiseImage == null) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _NoiseOverlayPainter(image: _cachedNoiseImage!),
        size: Size.infinite,
      ),
    );
  }
}

class _NoiseOverlayPainter extends CustomPainter {
  final ui.Image image;
  static final Paint _paint = Paint()
    ..filterQuality = FilterQuality.low
    ..color = Colors.black.withValues(alpha: 0.045);

  _NoiseOverlayPainter({required this.image}) {
    _paint.shader = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _NoiseOverlayPainter oldDelegate) =>
      oldDelegate.image != image;
}
