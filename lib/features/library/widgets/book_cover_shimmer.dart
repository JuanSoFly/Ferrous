import 'package:flutter/material.dart';

/// Animated shimmer skeleton placeholder for book covers.
/// Shows a sweeping light band over the cover gradient while content loads.
class BookCoverShimmer extends StatefulWidget {
  final String title;
  final String format;
  final double? height;
  final double? width;

  const BookCoverShimmer({
    super.key,
    required this.title,
    this.format = '',
    this.height,
    this.width,
  });

  @override
  State<BookCoverShimmer> createState() => _BookCoverShimmerState();
}

class _BookCoverShimmerState extends State<BookCoverShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static final List<List<Color>> _presetGradients = [
    [const Color(0xFFE0623A), const Color(0xFF8C1D18)],
    [const Color(0xFF2B5C8F), const Color(0xFF132F50)],
    [const Color(0xFF6B4A8F), const Color(0xFF381A5C)],
    [const Color(0xFF3B8253), const Color(0xFF144D2B)],
    [const Color(0xFFD68A3E), const Color(0xFF8F4D0E)],
    [const Color(0xFFD14D72), const Color(0xFF70132B)],
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _getColorGradient(String title) {
    if (title.isEmpty) return _presetGradients[0];
    final hash = title.hashCode.abs();
    return _presetGradients[hash % _presetGradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColorGradient(widget.title);
    final displayHeight = widget.height ?? 200;
    final isCompact = displayHeight < 100;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Shimmer highlight color adapts to theme brightness
    final shimmerHighlight =
        isDark ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.45);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors[0],
                colors[1],
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  shimmerHighlight,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(-2.0 + value * 4.0, 0),
                end: Alignment(-1.0 + value * 4.0, 0),
              ),
            ),
            child: isCompact
                ? _buildCompactSkeleton(displayHeight)
                : _buildFullSkeleton(displayHeight, isDark),
          ),
        );
      },
    );
  }

  /// Compact skeleton for small covers (< 100px) — just a centered icon placeholder.
  Widget _buildCompactSkeleton(double displayHeight) {
    return Center(
      child: Container(
        width: displayHeight * 0.35,
        height: displayHeight * 0.35,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Full skeleton with placeholder bars for badge, title, and author.
  Widget _buildFullSkeleton(double displayHeight, bool isDark) {
    final barColor = Colors.white.withValues(alpha: 0.12);
    final barRadius = BorderRadius.circular(4);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Format badge placeholder (top-right)
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 32,
              height: 14,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: barRadius,
              ),
            ),
          ),
          const Spacer(),
          // Title placeholder — two lines
          Container(
            width: double.infinity,
            height: 12,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: barRadius,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 80,
            height: 12,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: barRadius,
            ),
          ),
          const SizedBox(height: 8),
          // Author placeholder — one line
          Container(
            width: 60,
            height: 10,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: barRadius,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
