import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Crisp physical Kindle Carta popup shape with hard zero-blur offset shadow.
class KindlePopupShape extends ShapeBorder {
  final double borderWidth;
  final Color borderColor;
  final Color shadowColor;
  final Offset shadowOffset;
  final double radius;

  const KindlePopupShape({
    this.borderWidth = 1.5,
    this.borderColor = const Color(0xFF1A1A18),
    this.shadowColor = const Color(0xFF1A1A18),
    this.shadowOffset = const Offset(3, 3),
    this.radius = 2.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderWidth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(borderWidth),
          Radius.circular(radius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // 1. Draw hard zero-blur offset print shadow
    final shadowRRect = RRect.fromRectAndRadius(
      rect.shift(shadowOffset),
      Radius.circular(radius),
    );
    canvas.drawRRect(shadowRRect, Paint()..color = shadowColor);

    // 2. Fill the main menu background with solid opaque paper color
    final mainRRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius),
    );
    canvas.drawRRect(mainRRect, Paint()..color = const Color(0xFFEAE6DF));

    // 3. Draw the crisp border stroke
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(mainRRect, borderPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}

/// Instantaneous (0ms) inverting menu item for Kindle Carta popup menus.
class KindlePopupItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final bool isHighlighted;

  const KindlePopupItem({
    super.key,
    required this.icon,
    required this.label,
    this.isDestructive = false,
    this.isHighlighted = false,
  });

  @override
  State<KindlePopupItem> createState() => _KindlePopupItemState();
}

class _KindlePopupItemState extends State<KindlePopupItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool invert = _isPressed;
    final fgColor = invert
        ? const Color(0xFFEAE6DF)
        : (widget.isDestructive
            ? const Color(0xFF1A1A18)
            : (widget.isHighlighted
                ? const Color(0xFF1A1A18)
                : const Color(0xFF1A1A18)));
    final bgColor = invert ? const Color(0xFF1A1A18) : Colors.transparent;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 20, color: fgColor),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: GoogleFonts.robotoSlab(
                color: fgColor,
                fontWeight: widget.isHighlighted ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crisp 1px #9E9A90 rule for Kindle Carta popup menus.
class KindlePopupDivider extends PopupMenuEntry<Never> {
  const KindlePopupDivider({super.key});

  @override
  final double height = 1;

  @override
  bool represents(void value) => false;

  @override
  State<KindlePopupDivider> createState() => _KindlePopupDividerState();
}

class _KindlePopupDividerState extends State<KindlePopupDivider> {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFF9E9A90),
    );
  }
}
