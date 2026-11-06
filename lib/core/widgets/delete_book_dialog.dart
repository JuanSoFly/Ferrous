import 'package:flutter/material.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/models/book.dart';

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
  final hasLocalFile = book.filePath.isNotEmpty;
  // For imported books, default to true since keeping orphaned copies in private app storage wastes space.
  // For linked books, default to false so external user files are safe by default.
  bool deletePhysicalFile = book.sourceType == BookSourceType.imported && hasLocalFile;

  return showDialog<DeleteBookResult>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
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
