import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Annotation' : 'Add Annotation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                border: Border(left: BorderSide(color: Color(_selectedColor), width: 4)),
              ),
              child: Text(
                widget.selectedText,
                style: const TextStyle(fontStyle: FontStyle.italic),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Note (Optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'Enter your thoughts...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _colors.map((color) {
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
                      shape: BoxShape.circle,
                      border: _selectedColor == color
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
                          : null,
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'note': _noteController.text.trim(),
              'color': _selectedColor,
            });
          },
          child: Text(_isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}
