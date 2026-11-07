import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class AnnotationDialog extends StatefulWidget {
  final String selectedText;
  final String? initialNote;
  final int? initialColor;

  const AnnotationDialog({
    super.key,
    required this.selectedText,
    this.initialNote,
    this.initialColor,
  });

  @override
  State<AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<AnnotationDialog> {
  late final TextEditingController _noteController;
  late int _selectedColor;

  final List<int> _colors = const [
    0xFFFFF176, // Yellow
    0xFFFF8A80, // Red
    0xFF81C784, // Green
    0xFF64B5F6, // Blue
    0xFFBA68C8, // Purple
  ];

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote ?? '');
    _selectedColor = widget.initialColor ?? _colors.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.initialNote != null || widget.initialColor != null;

  @override
  Widget build(BuildContext context) {
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    final colorOptions = isEInk
        ? const [
            0xFFD5D0C5, // Halftone Highlight
            0xFFE0DCD3, // Secondary Paper
            0xFFC2BEB4, // Leader Line
            0xFF9E9A90, // Hairline
            0xFF1A1A18, // Carbon Ink
          ]
        : _colors;

    final activeColor = isEInk && !_colors.contains(_selectedColor) && !colorOptions.contains(_selectedColor)
        ? 0xFFD5D0C5
        : _selectedColor;

    return AlertDialog(
      backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
      ),
      title: Text(
        _isEditing ? 'Edit Annotation' : 'Add Annotation',
        style: isEInk
            ? GoogleFonts.robotoSlab(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A18),
              )
            : null,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isEInk ? const Color(0xFFE0DCD3) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isEInk ? 2 : 0),
                border: isEInk
                    ? const Border(
                        left: BorderSide(color: Color(0xFF1A1A18), width: 3),
                        top: BorderSide(color: Color(0xFF9E9A90), width: 1),
                        right: BorderSide(color: Color(0xFF9E9A90), width: 1),
                        bottom: BorderSide(color: Color(0xFF9E9A90), width: 1),
                      )
                    : Border(left: BorderSide(color: Color(activeColor), width: 4)),
              ),
              child: Text(
                widget.selectedText,
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF1A1A18),
                      )
                    : const TextStyle(fontStyle: FontStyle.italic),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Note (Optional)',
              style: isEInk ? const TextStyle(color: Color(0xFF1A1A18), fontWeight: FontWeight.bold) : null,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              style: isEInk ? const TextStyle(color: Color(0xFF1A1A18)) : null,
              decoration: InputDecoration(
                hintText: 'Enter your thoughts...',
                filled: isEInk,
                fillColor: isEInk ? const Color(0xFFE0DCD3) : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(isEInk ? 2 : 4),
                  borderSide: isEInk ? const BorderSide(color: Color(0xFF1A1A18)) : const BorderSide(),
                ),
                enabledBorder: isEInk
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2),
                        borderSide: const BorderSide(color: Color(0xFF1A1A18)),
                      )
                    : null,
                focusedBorder: isEInk
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2),
                        borderSide: const BorderSide(color: Color(0xFF1A1A18), width: 2),
                      )
                    : null,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Color',
              style: isEInk ? const TextStyle(color: Color(0xFF1A1A18), fontWeight: FontWeight.bold) : null,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: colorOptions.map((color) {
                final isSelected = activeColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(color),
                      borderRadius: isEInk ? BorderRadius.circular(2) : null,
                      shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? (isEInk ? const Color(0xFF1A1A18) : Theme.of(context).colorScheme.onSurface)
                            : (isEInk ? const Color(0xFF9E9A90) : Colors.transparent),
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: isEInk
              ? TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                )
              : null,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'note': _noteController.text.trim(),
              'color': activeColor,
            });
          },
          style: isEInk
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A18),
                  foregroundColor: const Color(0xFFEAE6DF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                )
              : null,
          child: Text(_isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}
