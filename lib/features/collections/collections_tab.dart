import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/collection.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/features/collections/collection_detail_screen.dart';

class CollectionsTab extends StatelessWidget {
  const CollectionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final collectionRepo = context.watch<CollectionRepository>();
    final collections = collectionRepo.getAllCollections();

    if (collections.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shelves,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No collections yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Organize your reading list into custom folders and series.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => _showCreateDialog(context),
                label: const Text('Create Collection'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
          itemCount: collections.length,
          itemBuilder: (context, index) {
            final collection = collections[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(collection.name),
                subtitle: Text('${collection.bookIds.length} books'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, collection),
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
              ),
            );
          },
        ),
        Positioned(
          bottom: 100,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: () {
              HapticFeedback.lightImpact();
              _showCreateDialog(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('New Collection'),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Collection'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<CollectionRepository>().createCollection(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Collection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection?'),
        content: Text('Delete "${collection.name}"? Books inside will not be deleted from library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        context.read<CollectionRepository>().deleteCollection(collection.id);
      }
    }
  }
}
