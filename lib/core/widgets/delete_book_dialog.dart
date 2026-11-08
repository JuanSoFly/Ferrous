import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/features/settings/app_themes.dart';

/// Result returned by [showDeleteBookDialog].
class DeleteBookResult {
  final bool confirmed;
  final bool deletePhysicalFile;

  const DeleteBookResult({
    required this.confirmed,
    this.deletePhysicalFile = false,
  });
}

/// Shows a polished confirmation dialog for deleting a book.
///
/// Gives the user the option to also delete the physical file on disk
/// if a local path exists.
Future<DeleteBookResult?> showDeleteBookDialog({
  required BuildContext context,
  required Book book,
}) {
  final theme = Theme.of(context);
  final currentTheme = context.read<AppTheme>();
  final isEInk = currentTheme == AppTheme.eInk;
  final hasLocalFile = book.filePath.isNotEmpty;
  // For imported books, default to true since keeping orphaned copies in private app storage wastes space.
  // For linked books, default to false so external user files are safe by default.
  bool deletePhysicalFile = book.sourceType == BookSourceType.imported && hasLocalFile;

  return showDialog<DeleteBookResult>(
    context: context,
    barrierColor: isEInk ? const Color(0xFF1A1A18).withValues(alpha: 0.14) : null,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          if (isEInk) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
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
                        BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0DCD3),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFF1A1A18),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Delete Book',
                                style: GoogleFonts.robotoSlab(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: const Color(0xFF1A1A18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Body text
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.robotoSlab(
                              color: const Color(0xFF1A1A18),
                              fontSize: 14,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'Are you sure you want to delete '),
                              TextSpan(
                                text: '"${book.title}"',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const TextSpan(text: ' from your library?'),
                            ],
                          ),
                        ),
                        if (hasLocalFile) ...[
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: () {
                              setDialogState(() {
                                deletePhysicalFile = !deletePhysicalFile;
                              });
                            },
                            borderRadius: BorderRadius.circular(2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: deletePhysicalFile ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
                                    ),
                                    child: deletePhysicalFile
                                        ? const Icon(Icons.check, size: 15, color: Color(0xFFEAE6DF))
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Also delete file from device',
                                          style: GoogleFonts.robotoSlab(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: const Color(0xFF1A1A18),
                                          ),
                                        ),
                                        Text(
                                          book.sourceType == BookSourceType.imported
                                              ? 'Frees up space in app storage'
                                              : 'Permanently deletes source file',
                                          style: GoogleFonts.robotoSlab(
                                            color: const Color(0xFF4A4945),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (book.sourceType == BookSourceType.linked) ...[
                          const SizedBox(height: 12),
                          Text(
                            'The book will be removed from Ferrous. Your original file in the linked folder will remain untouched.',
                            style: GoogleFonts.robotoSlab(
                              color: const Color(0xFF4A4945),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Actions row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                backgroundColor: const Color(0xFFEAE6DF),
                                foregroundColor: const Color(0xFF1A1A18),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(dialogCtx).pop(
                                  const DeleteBookResult(confirmed: false),
                                );
                              },
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1A1A18),
                                foregroundColor: const Color(0xFFEAE6DF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(dialogCtx).pop(
                                  DeleteBookResult(
                                    confirmed: true,
                                    deletePhysicalFile: deletePhysicalFile,
                                  ),
                                );
                              },
                              child: Text(
                                'Delete',
                                style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Delete Book',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Are you sure you want to delete '),
                      TextSpan(
                        text: '"${book.title}"',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' from your library?'),
                    ],
                  ),
                ),
                if (hasLocalFile) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        deletePhysicalFile = !deletePhysicalFile;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: deletePhysicalFile,
                            activeColor: theme.colorScheme.error,
                            onChanged: (val) {
                              setDialogState(() {
                                deletePhysicalFile = val ?? false;
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Also delete file from device',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  book.sourceType == BookSourceType.imported
                                      ? 'Frees up space in app storage'
                                      : 'Permanently deletes source file',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (book.sourceType == BookSourceType.linked) ...[
                  const SizedBox(height: 12),
                  Text(
                    'The book will be removed from Ferrous. Your original file in the linked folder will remain untouched.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(
                  const DeleteBookResult(confirmed: false),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(
                  DeleteBookResult(
                    confirmed: true,
                    deletePhysicalFile: deletePhysicalFile,
                  ),
                ),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
    },
  );
}
