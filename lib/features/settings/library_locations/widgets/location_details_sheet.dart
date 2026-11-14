import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/core/models/library_location.dart';
import 'package:ferrous/data/services/saf_service.dart';

class LocationDetailsSheet extends StatelessWidget {
  final LibraryLocation location;
  final List<Book> books;
  final VoidCallback onRescan;
  final VoidCallback onViewBooks;
  final ValueChanged<SafStorageMode> onModeChanged;
  final VoidCallback onRemove;

  const LocationDetailsSheet({
    super.key,
    required this.location,
    required this.books,
    required this.onRescan,
    required this.onViewBooks,
    required this.onModeChanged,
    required this.onRemove,
  });

  static void show(
    BuildContext context, {
    required LibraryLocation location,
    required List<Book> books,
    required VoidCallback onRescan,
    required VoidCallback onViewBooks,
    required ValueChanged<SafStorageMode> onModeChanged,
    required VoidCallback onRemove,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationDetailsSheet(
        location: location,
        books: books,
        onRescan: onRescan,
        onViewBooks: onViewBooks,
        onModeChanged: onModeChanged,
        onRemove: onRemove,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate format distribution
    final Map<String, int> formatCounts = {};
    for (final book in books) {
      final fmt = book.format.toUpperCase();
      formatCounts[fmt] = (formatCounts[fmt] ?? 0) + 1;
    }

    final isLinked = location.storageMode == SafStorageMode.linked;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location.readablePath,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Info summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1C19)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED),
              ),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  label: 'Storage Mode',
                  valueWidget: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isLinked ? const Color(0xFF10B981) : const Color(0xFF8B5CF6))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (isLinked ? const Color(0xFF10B981) : const Color(0xFF8B5CF6))
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      isLinked ? 'LINKED (In-Place)' : 'IMPORTED (Sandboxed)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: isLinked ? const Color(0xFF34D399) : const Color(0xFFA78BFA),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 16),
                _buildInfoRow(
                  label: 'Permission Status',
                  valueWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        location.isValid ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 16,
                        color: location.isValid ? const Color(0xFF10B981) : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        location.isValid ? 'Active & Accessible' : 'Permission Revoked',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: location.isValid ? const Color(0xFF10B981) : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                _buildInfoRow(
                  label: 'Books in Library',
                  value: '${books.length} book${books.length == 1 ? '' : 's'} (${LibraryLocation.formatBytes(location.totalSizeBytes)})',
                ),
                if (formatCounts.isNotEmpty) ...[
                  const Divider(height: 16),
                  _buildInfoRow(
                    label: 'Formats',
                    valueWidget: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: formatCounts.entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Raw URI / Path tile with copy
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: location.uri));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URI copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'URI / IDENTIFIER',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location.uri,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.copy_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Rescan Folder'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRescan();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories_rounded, size: 18),
                  label: Text('View Books (${books.length})'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onViewBooks();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Remove Location'),
              onPressed: () {
                Navigator.of(context).pop();
                onRemove();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (valueWidget != null)
          valueWidget
        else if (value != null)
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
