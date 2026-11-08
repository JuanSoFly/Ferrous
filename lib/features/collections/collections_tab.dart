import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/models/collection.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/features/collections/collection_detail_screen.dart';
import 'package:reader_app/features/settings/app_themes.dart';

// ==========================================
// KINDLE MECHANICAL ACTION BUTTON
// ==========================================

class _KindleActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _KindleActionButton({
    required this.onPressed,
    required this.label,
    this.icon = Icons.add,
  });

  @override
  State<_KindleActionButton> createState() => _KindleActionButtonState();
}

class _KindleActionButtonState extends State<_KindleActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _isPressed ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);
    final fgColor = _isPressed ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, size: 16, color: fgColor),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: GoogleFonts.robotoSlab(
                color: fgColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// COLLECTIONS TAB
// ==========================================

class CollectionsTab extends StatelessWidget {
  const CollectionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final collectionRepo = context.watch<CollectionRepository>();
    final collections = collectionRepo.getAllCollections();
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    if (collections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary.withValues(alpha: 0.08),
                  shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isEInk ? BorderRadius.circular(2) : null,
                  border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.5) : null,
                ),
                child: Icon(
                  Icons.shelves,
                  size: 40,
                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No collections yet',
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: const Color(0xFF1A1A18),
                      )
                    : theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                'Organize your reading list into custom folders and series.',
                textAlign: TextAlign.center,
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        color: const Color(0xFF4A4945),
                        fontSize: 13,
                      )
                    : theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(height: 20),
              if (isEInk)
                _KindleActionButton(
                  label: 'Create Collection',
                  onPressed: () => _showCreateDialog(context, isEInk: true),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _showCreateDialog(context, isEInk: false),
                  label: const Text('Create Collection'),
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${collections.length} ${collections.length == 1 ? 'collection' : 'collections'}',
                style: isEInk
                    ? GoogleFonts.robotoSlab(
                        color: const Color(0xFF4A4945),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      )
                    : theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
              ),
              if (isEInk)
                _KindleActionButton(
                  label: 'New Collection',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _showCreateDialog(context, isEInk: true);
                  },
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _showCreateDialog(context, isEInk: false);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Collection'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isEInk
                ? const Color(0xFFE0DCD3)
                : (theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow),
            borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
            border: Border.all(
              color: isEInk
                  ? const Color(0xFF1A1A18)
                  : (theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04)),
              width: isEInk ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: collections.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: isEInk ? 1 : 0.5,
              indent: 56,
              color: isEInk
                  ? const Color(0xFF9E9A90)
                  : (theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04)),
            ),
            itemBuilder: (context, index) {
              final collection = collections[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isEInk
                        ? const Color(0xFFEAE6DF)
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
                    border: isEInk
                        ? Border.all(color: const Color(0xFF1A1A18), width: 1)
                        : null,
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  collection.name,
                  style: TextStyle(
                    fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 15,
                    color: isEInk ? const Color(0xFF1A1A18) : null,
                  ),
                ),
                subtitle: Text(
                  '${collection.bookIds.length} ${collection.bookIds.length == 1 ? 'book' : 'books'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isEInk ? FontWeight.w500 : FontWeight.normal,
                    color: isEInk
                        ? const Color(0xFF4A4945)
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: isEInk
                            ? const Color(0xFF1A1A18)
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      tooltip: 'Delete Collection',
                      onPressed: () => _confirmDelete(context, collection, isEInk: isEInk),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: isEInk
                          ? const Color(0xFF1A1A18)
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ],
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CollectionDetailScreen(collection: collection),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context, {bool isEInk = false}) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
            side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
          ),
          backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
          title: Text(
            'New Collection',
            style: isEInk
                ? GoogleFonts.robotoSlab(color: const Color(0xFF1A1A18), fontWeight: FontWeight.bold)
                : null,
          ),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Collection Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: isEInk ? const TextStyle(color: Color(0xFF4A4945)) : null,
              ),
            ),
            if (isEInk)
              _KindleActionButton(
                label: 'Create',
                icon: Icons.check,
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    context.read<CollectionRepository>().createCollection(controller.text.trim());
                    Navigator.pop(context);
                  }
                },
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    context.read<CollectionRepository>().createCollection(controller.text.trim());
                    Navigator.pop(context);
                  }
                },
                child: const Text('Create'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Collection collection, {bool isEInk = false}) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.lg),
          side: isEInk ? const BorderSide(color: Color(0xFF1A1A18), width: 1.5) : BorderSide.none,
        ),
        backgroundColor: isEInk ? const Color(0xFFEAE6DF) : null,
        title: Text(
          'Delete Collection?',
          style: isEInk
              ? GoogleFonts.robotoSlab(color: const Color(0xFF1A1A18), fontWeight: FontWeight.bold)
              : null,
        ),
        content: Text(
          'Delete "${collection.name}"? Books inside will remain in your library.',
          style: isEInk ? const TextStyle(color: Color(0xFF3D3C38)) : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: isEInk ? const TextStyle(color: Color(0xFF4A4945)) : null,
            ),
          ),
          if (isEInk)
            _KindleActionButton(
              label: 'Delete',
              icon: Icons.delete_outline,
              onPressed: () => Navigator.pop(context, true),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<CollectionRepository>().deleteCollection(collection.id);
    }
  }
}
