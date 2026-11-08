import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/models/book.dart';

/// Subtle monochrome halftone dot pattern overlay scrim for Kindle Carta display.
class HalftoneScrimPainter extends CustomPainter {
  const HalftoneScrimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Light matte paper tint base (preserves underlying reflective paper tone)
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1A1A18).withValues(alpha: 0.12),
    );

    // 2. Monochrome halftone dot matrix
    final dotPaint = Paint()..color = const Color(0xFF1A1A18).withValues(alpha: 0.18);
    const double spacing = 4.0;
    const double dotRadius = 0.75;

    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kindle Paperwhite mechanical action sheet with zero blur, hard offset shadows,
/// recessed header, and 0ms instant inversion.
class KindleBookActionSheet extends StatelessWidget {
  final Book book;
  final VoidCallback onSplitView;
  final VoidCallback onAddToCollection;
  final VoidCallback onDeleteBook;
  final VoidCallback onCancel;

  const KindleBookActionSheet({
    super.key,
    required this.book,
    required this.onSplitView,
    required this.onAddToCollection,
    required this.onDeleteBook,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Kindle Menu Container
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFEAE6DF),
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF1A1A18),
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFF1A1A18), width: 2.0),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Recessed High-Contrast Printed Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0DCD3),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.robotoSlab(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A18),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            book.author.isNotEmpty ? book.author : 'Unknown Author',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.robotoSlab(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF3D3C38),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Action 1: Open in Split View
                    _KindleSheetRow(
                      icon: Icons.vertical_split_outlined,
                      label: 'Open in Split View',
                      onTap: onSplitView,
                    ),

                    const Divider(height: 1, thickness: 1, color: Color(0xFF9E9A90)),

                    // Action 2: Add to Collection
                    _KindleSheetRow(
                      icon: Icons.bookmark_add_outlined,
                      label: 'Add to Collection',
                      onTap: onAddToCollection,
                    ),

                    const Divider(height: 1, thickness: 1, color: Color(0xFF9E9A90)),

                    // Action 3: Delete Book (Strictly monochrome carbon ink, NO red!)
                    _KindleSheetRow(
                      icon: Icons.delete_outline,
                      label: 'Delete Book',
                      isDestructive: true,
                      onTap: onDeleteBook,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Stacked Mechanical Cancel Button with tight 8px gap
              Container(
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF1A1A18),
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: _KindleCancelRow(onTap: onCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindleSheetRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _KindleSheetRow({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  State<_KindleSheetRow> createState() => _KindleSheetRowState();
}

class _KindleSheetRowState extends State<_KindleSheetRow> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _isPressed || _isHovered;
    final fgColor = active ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);
    final bgColor = active
        ? const Color(0xFF1A1A18)
        : (widget.isDestructive ? const Color(0xFFE0DCD3) : const Color(0xFFEAE6DF));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: fgColor),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: GoogleFonts.robotoSlab(
                    fontSize: 14.5,
                    fontWeight: widget.isDestructive ? FontWeight.w700 : FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindleCancelRow extends StatefulWidget {
  final VoidCallback onTap;

  const _KindleCancelRow({required this.onTap});

  @override
  State<_KindleCancelRow> createState() => _KindleCancelRowState();
}

class _KindleCancelRowState extends State<_KindleCancelRow> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _isPressed || _isHovered;
    final fgColor = active ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);
    final bgColor = active ? const Color(0xFF1A1A18) : const Color(0xFFE0DCD3);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(2),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            child: Text(
              'Cancel',
              style: GoogleFonts.robotoSlab(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
