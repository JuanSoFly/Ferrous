import 'package:flutter/material.dart';
import 'package:reader_app/core/models/library_location.dart';

class RemoveLocationDecision {
  final bool confirmed;
  final bool removeAssociatedBooks;

  const RemoveLocationDecision({
    required this.confirmed,
    required this.removeAssociatedBooks,
  });
}

class RemoveLocationDialog extends StatefulWidget {
  final LibraryLocation location;

  const RemoveLocationDialog({
    super.key,
    required this.location,
  });

  static Future<RemoveLocationDecision?> show(
    BuildContext context,
    LibraryLocation location,
  ) {
    return showDialog<RemoveLocationDecision>(
      context: context,
      builder: (context) => RemoveLocationDialog(location: location),
    );
  }

  @override
  State<RemoveLocationDialog> createState() => _RemoveLocationDialogState();
}

class _RemoveLocationDialogState extends State<RemoveLocationDialog> {
  late bool _removeAssociatedBooks;

  @override
  void initState() {
    super.initState();
    _removeAssociatedBooks = widget.location.bookCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookCount = widget.location.bookCount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Remove Folder',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: 'Are you sure you want to remove ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text: widget.location.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const TextSpan(text: ' from your library locations?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.location.readablePath,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (bookCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _removeAssociatedBooks
                        ? Colors.red.withValues(alpha: 0.4)
                        : theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  color: _removeAssociatedBooks
                      ? Colors.red.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
                child: CheckboxListTile(
                  value: _removeAssociatedBooks,
                  onChanged: (val) {
                    setState(() => _removeAssociatedBooks = val ?? false);
                  },
                  activeColor: Colors.redAccent,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    'Also delete $bookCount book${bookCount == 1 ? '' : 's'} from library',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    _removeAssociatedBooks
                        ? 'Removes reading history, progress, and entries for these books.'
                        : 'Books will remain listed in your library, but may become unreadable if permission is revoked.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: () {
            Navigator.of(context).pop(
              RemoveLocationDecision(
                confirmed: true,
                removeAssociatedBooks: _removeAssociatedBooks,
              ),
            );
          },
          child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
