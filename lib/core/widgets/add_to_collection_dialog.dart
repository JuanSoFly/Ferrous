import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/constants/app_constants.dart';
import 'package:ferrous/data/repositories/collection_repository.dart';
import 'package:ferrous/features/settings/app_themes.dart';

/// Shows a dialog to add one or multiple books to a collection.
///
/// If no collections exist yet, this directly prompts the user to create a new
/// collection on the fly (with a Cancel button) rather than displaying a dead-end message.
///
/// If collections already exist, this displays the collection picker with a
/// prominent `+` button in the header so the user can easily create a new collection
/// without navigating away or losing selection state.
Future<void> showAddToCollectionDialog(
  BuildContext context, {
  required Iterable<String> bookIds,
  VoidCallback? onCompleted,
}) async {
  final idList = bookIds.toList();
  if (idList.isEmpty) return;

  final collectionRepo = context.read<CollectionRepository>();
  final collections = collectionRepo.getAllCollections();
  final currentTheme = context.read<AppTheme>();
  final isEInk = currentTheme == AppTheme.eInk;

  // Case 1: No collections created yet -> prompt immediately to create one!
  if (collections.isEmpty) {
    final name = await promptCreateCollection(context, isEInk: isEInk);
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      final newCol = await collectionRepo.createCollection(name.trim());
      await collectionRepo.addBooksToCollection(newCol.id, idList);
      if (context.mounted) {
        final message = idList.length == 1
            ? 'Added to "${newCol.name}"'
            : 'Added ${idList.length} books to "${newCol.name}"';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        onCompleted?.call();
      }
    }
    return;
  }

  // Case 2: Collections already exist -> show picker with `+` icon in title.
  final theme = Theme.of(context);

  await showDialog<void>(
    context: context,
    barrierColor: isEInk ? const Color(0xFF1A1A18).withValues(alpha: 0.14) : null,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
          side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
        ),
        backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Add to Collection',
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: const Color(0xFF1A1A18),
                      )
                    : const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New Collection',
              onPressed: () async {
                final name = await promptCreateCollection(context, isEInk: isEInk);
                if (name != null && name.trim().isNotEmpty && context.mounted) {
                  final newCol = await collectionRepo.createCollection(name.trim());
                  final added = await collectionRepo.addBooksToCollection(newCol.id, idList);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  if (context.mounted) {
                    final message = idList.length == 1
                        ? 'Added to "${newCol.name}"'
                        : 'Added $added books to "${newCol.name}"';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    onCompleted?.call();
                  }
                }
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: collections.length,
            separatorBuilder: (_, __) => isEInk
                ? const Divider(height: 1, thickness: 1, color: Color(0xFF9E9A90))
                : const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, index) {
              final collection = collections[index];
              final allContained = idList.every((id) => collection.bookIds.contains(id));
              final anyContained = idList.any((id) => collection.bookIds.contains(id));
              final isPartiallyContained = anyContained && !allContained;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                dense: true,
                leading: isEInk
                    ? Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: allContained ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
                        ),
                        child: allContained
                            ? const Icon(Icons.check, size: 14, color: Color(0xFFEAE6DF))
                            : (isPartiallyContained
                                ? const Center(
                                    child: SizedBox(
                                      width: 8,
                                      height: 2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(color: Color(0xFF1A1A18)),
                                      ),
                                    ),
                                  )
                                : null),
                      )
                    : Icon(
                        allContained
                            ? Icons.check_box
                            : (isPartiallyContained ? Icons.indeterminate_check_box : Icons.check_box_outline_blank),
                        color: allContained || isPartiallyContained
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                title: Text(
                  collection.name,
                  style: isEInk
                      ? GoogleFonts.robotoSlab(
                          fontSize: 14,
                          fontWeight: allContained ? FontWeight.bold : FontWeight.w500,
                          color: const Color(0xFF1A1A18),
                        )
                      : TextStyle(
                          fontWeight: allContained ? FontWeight.bold : FontWeight.normal,
                        ),
                ),
                subtitle: Text(
                  '${collection.bookIds.length} ${collection.bookIds.length == 1 ? 'book' : 'books'}',
                  style: isEInk
                      ? GoogleFonts.robotoSlab(fontSize: 11, color: const Color(0xFF4A4945))
                      : theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                onTap: () async {
                  final added = await collectionRepo.addBooksToCollection(collection.id, idList);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  if (context.mounted) {
                    final message = added > 0
                        ? (idList.length == 1
                            ? 'Added to "${collection.name}"'
                            : 'Added $added books to "${collection.name}"')
                        : 'Already in "${collection.name}"';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    onCompleted?.call();
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: isEInk
                  ? GoogleFonts.robotoSlab(color: const Color(0xFF4A4945), fontWeight: FontWeight.bold)
                  : TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    },
  );
}

/// Displays an inline prompt dialog to create a new collection with a name input field and Cancel button.
Future<String?> promptCreateCollection(
  BuildContext context, {
  required bool isEInk,
}) async {
  final controller = TextEditingController();
  final theme = Theme.of(context);

  return showDialog<String>(
    context: context,
    barrierColor: isEInk ? const Color(0xFF1A1A18).withValues(alpha: 0.14) : null,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
          side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
        ),
        backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
        title: Text(
          'New Collection',
          style: isEInk
              ? GoogleFonts.robotoSlab(
                  color: const Color(0xFF1A1A18),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                )
              : const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Collection Name',
            border: isEInk
                ? const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                    borderSide: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                  )
                : null,
          ),
          autofocus: true,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) {
              Navigator.of(dialogContext).pop(trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: isEInk
                  ? GoogleFonts.robotoSlab(color: const Color(0xFF4A4945), fontWeight: FontWeight.bold)
                  : TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (isEInk)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                backgroundColor: const Color(0xFF1A1A18),
                foregroundColor: const Color(0xFFEAE6DF),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(dialogContext).pop(trimmed);
                }
              },
              child: Text(
                'Create',
                style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold),
              ),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(dialogContext).pop(trimmed);
                }
              },
              child: const Text('Create'),
            ),
        ],
      );
    },
  );
}
