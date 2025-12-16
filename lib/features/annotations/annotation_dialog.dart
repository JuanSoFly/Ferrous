import 'package:flutter/material.dart';

class AnnotationDialog extends StatefulWidget {
  final String selectedText;

  const AnnotationDialog({super.key, required this.selectedText});

  @override
  State<AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<AnnotationDialog> {
  final TextEditingController _noteController = TextEditingController();
  int _selectedColor = 0xFFFFF176; // Default Yellow (Colors.yellow[300])

  final List<int> _colors = [
    0xFFFFF176, // Yellow
    0xFFFF8A80, // Red
    0xFF81C784, // Green
    0xFF64B5F6, // Blue
    0xFFBA68C8, // Purple
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Annotation'),
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
                          ? Border.all(color: Colors.black, width: 2)
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}
