import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/features/settings/app_themes.dart';

enum ReaderFormatType {
  pdf,
  text,
  image,
}

Future<ReadingMode?> showReadingModeSheet(
  BuildContext context, {
  required ReadingMode current,
  ReaderFormatType formatType = ReaderFormatType.image,
}) {
  final currentTheme = context.read<AppTheme>();
  final isEInk = currentTheme == AppTheme.eInk;

  return showModalBottomSheet<ReadingMode>(
    context: context,
    useSafeArea: true,
    showDragHandle: !isEInk,
    barrierColor: isEInk ? Colors.transparent : null,
    backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
    shape: isEInk
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
            side: BorderSide(color: Color(0xFF1A1A18), width: 2.0),
          )
        : null,
    builder: (context) {
      final modes = <Widget>[
        Text(
          'Reading mode',
          style: isEInk
              ? GoogleFonts.robotoSlab(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A18),
                )
              : Theme.of(context).textTheme.titleLarge,
        ),
        if (isEInk) ...[
          const SizedBox(height: 10),
          const Divider(height: 1.5, thickness: 1.5, color: Color(0xFF1A1A18)),
          const SizedBox(height: 4),
        ] else ...[
          const SizedBox(height: 8),
        ],
      ];

      final List<(ReadingMode, String, String)> rawTiles;
      switch (formatType) {
        case ReaderFormatType.pdf:
          rawTiles = const [
            (ReadingMode.vertical, 'Vertical paged', 'Swipe up/down to change pages'),
            (ReadingMode.leftToRight, 'Left to right paged', 'Swipe left/right to change pages'),
            (ReadingMode.verticalContinuous, 'Vertical continuous', 'Scroll through all pages vertically'),
            (ReadingMode.webtoon, 'Webtoon', 'Continuous with extra spacing'),
            (ReadingMode.horizontalContinuous, 'Horizontal continuous', 'Scroll through all pages horizontally'),
          ];
          break;
        case ReaderFormatType.text:
          rawTiles = const [
            (ReadingMode.vertical, 'Vertical paged', 'Swipe up/down to change chapters'),
            (ReadingMode.leftToRight, 'Left to right paged', 'Swipe left/right to change chapters'),
            (ReadingMode.verticalContinuous, 'Vertical scroll', 'Scroll through content'),
          ];
          break;
        case ReaderFormatType.image:
          rawTiles = const [
            (ReadingMode.vertical, 'Vertical paged', 'Swipe up/down to change pages'),
            (ReadingMode.leftToRight, 'Left to right paged', 'Swipe left/right to change pages'),
            (ReadingMode.verticalContinuous, 'Vertical continuous', 'Scroll through all pages vertically'),
            (ReadingMode.webtoon, 'Webtoon', 'Continuous with extra spacing'),
            (ReadingMode.horizontalContinuous, 'Horizontal continuous', 'Scroll through all pages horizontally'),
          ];
          break;
      }

      for (var i = 0; i < rawTiles.length; i++) {
        final item = rawTiles[i];
        modes.add(
          _ModeTile(
            mode: item.$1,
            current: current,
            title: item.$2,
            description: item.$3,
            isEInk: isEInk,
            isLast: i == rawTiles.length - 1,
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
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
  final bool isEInk;
  final bool isLast;

  const _ModeTile({
    required this.mode,
    required this.current,
    required this.title,
    required this.description,
    this.isEInk = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = mode == current;

    if (isEInk) {
      return InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(mode);
        },
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE0DCD3) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? const Color(0xFF1A1A18) : Colors.transparent,
                width: 3.5,
              ),
              bottom: isLast
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFF9E9A90), width: 1.0),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.robotoSlab(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: const Color(0xFF1A1A18),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.robotoSlab(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF4A4945),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A18),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
                  ),
                  child: const Icon(Icons.check, size: 16, color: Color(0xFFEAE6DF)),
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAE6DF),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFF9E9A90), width: 1.0),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(title),
      subtitle: Text(description),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(mode);
      },
    );
  }
}
