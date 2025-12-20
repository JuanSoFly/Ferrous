import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/features/reader/reader_screen.dart';

class SplitReaderScreen extends StatefulWidget {
  final Book leftBook;
  final Book rightBook;

  const SplitReaderScreen({
    super.key,
    required this.leftBook,
    required this.rightBook,
  });

  @override
  State<SplitReaderScreen> createState() => _SplitReaderScreenState();
}

class _SplitReaderScreenState extends State<SplitReaderScreen> {
  double _dividerPosition = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split View'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () {
              // Swap books
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => SplitReaderScreen(
                    leftBook: widget.rightBook,
                    rightBook: widget.leftBook,
                  ),
                ),
              );
            },
            tooltip: 'Swap Positions',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final leftWidth = constraints.maxWidth * _dividerPosition;
          final rightWidth = constraints.maxWidth * (1 - _dividerPosition);

          return Row(
            children: [
              SizedBox(
                width: leftWidth - 4,
                child: ReaderScreen(book: widget.leftBook),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _dividerPosition += details.delta.dx / constraints.maxWidth;
                    _dividerPosition = _dividerPosition.clamp(0.2, 0.8);
                  });
                },
                child: Container(
                  width: 8,
                  color: Theme.of(context).dividerColor,
                  child: const Center(
                    child: Icon(Icons.drag_indicator, size: 16),
                  ),
                ),
              ),
              SizedBox(
                width: rightWidth - 4,
                child: ReaderScreen(book: widget.rightBook),
              ),
            ],
          );
        },
      ),
    );
  }
}
