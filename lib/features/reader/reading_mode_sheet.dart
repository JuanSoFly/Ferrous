import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';

/// Format types that affect which reading modes are available
enum ReaderFormatType {
  /// PDF - single page rendering, only paged modes work
  pdf,
  /// EPUB/MOBI/DOCX - HTML content, only vertical scroll works
  text,
  /// CBZ/CBR - images, all modes supported
  image,
}

Future<ReadingMode?> showReadingModeSheet(
  BuildContext context, {
  required ReadingMode current,
  ReaderFormatType formatType = ReaderFormatType.image,
}) {
  return showModalBottomSheet<ReadingMode>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final modes = <Widget>[
        Text(
          'Reading mode',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
      ];

      switch (formatType) {
        case ReaderFormatType.pdf:
          // PDF only supports paged modes
          modes.addAll([
            _ModeTile(
              mode: ReadingMode.vertical,
              current: current,
              title: 'Vertical',
              description: 'Swipe up/down to change pages',
            ),
            _ModeTile(
              mode: ReadingMode.leftToRight,
              current: current,
              title: 'Left to right',
              description: 'Swipe left/right to change pages',
            ),
          ]);
          break;
        case ReaderFormatType.text:
          // Text formats only support vertical scrolling
          modes.addAll([
            _ModeTile(
              mode: ReadingMode.verticalContinuous,
              current: current,
              title: 'Vertical scroll',
              description: 'Scroll through content',
            ),
            _ModeTile(
              mode: ReadingMode.webtoon,
              current: current,
              title: 'Webtoon style',
              description: 'Scroll with extra spacing',
            ),
          ]);
          break;
        case ReaderFormatType.image:
          // Image formats support all modes
          modes.addAll([
            _ModeTile(
              mode: ReadingMode.vertical,
              current: current,
              title: 'Vertical paged',
              description: 'Swipe up/down to change pages',
            ),
            _ModeTile(
              mode: ReadingMode.leftToRight,
              current: current,
              title: 'Left to right paged',
              description: 'Swipe left/right to change pages',
            ),
            _ModeTile(
              mode: ReadingMode.verticalContinuous,
              current: current,
              title: 'Vertical continuous',
              description: 'Scroll through all pages vertically',
            ),
            _ModeTile(
              mode: ReadingMode.webtoon,
              current: current,
              title: 'Webtoon',
              description: 'Continuous with extra spacing',
            ),
            _ModeTile(
              mode: ReadingMode.horizontalContinuous,
              current: current,
              title: 'Horizontal continuous',
              description: 'Scroll through all pages horizontally',
            ),
          ]);
          break;
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: modes,
      );
    },
  );
}

class _ModeTile extends StatelessWidget {
  final ReadingMode mode;
  final ReadingMode current;
  final String title;
  final String description;

  const _ModeTile({
    required this.mode,
    required this.current,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final selected = mode == current;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(title),
      subtitle: Text(description),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () => Navigator.of(context).pop(mode),
    );
  }
}
