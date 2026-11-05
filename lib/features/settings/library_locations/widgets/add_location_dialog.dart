import 'package:flutter/material.dart';
import 'package:reader_app/data/services/saf_service.dart';

class AddLocationDialog extends StatefulWidget {
  const AddLocationDialog({super.key});

  static Future<SafStorageMode?> show(BuildContext context) {
    return showDialog<SafStorageMode>(
      context: context,
      builder: (context) => const AddLocationDialog(),
    );
  }

  @override
  State<AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<AddLocationDialog> {
  SafStorageMode _selectedMode = SafStorageMode.linked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.create_new_folder_outlined,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add Library Folder',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: RadioGroup<SafStorageMode>(
          groupValue: _selectedMode,
          onChanged: (val) {
            if (val != null) setState(() => _selectedMode = val);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose how books in this folder should be stored and managed:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildOptionCard(
                context: context,
                theme: theme,
                mode: SafStorageMode.linked,
                title: 'Link Files (Recommended)',
                badge: 'ZERO EXTRA STORAGE',
                badgeColor: const Color(0xFF10B981),
                description:
                    'Keep files in place on your device. Books are streamed directly from their folder. Ideal for SD cards and large libraries.',
                icon: Icons.link_rounded,
              ),
              const SizedBox(height: 12),
              _buildOptionCard(
                context: context,
                theme: theme,
                mode: SafStorageMode.imported,
                title: 'Import Files',
                badge: 'PERSISTENT COPY',
                badgeColor: const Color(0xFF8B5CF6),
                description:
                    'Copy files into Ferrous internal storage. Books remain safe and accessible even if the source folder is deleted.',
                icon: Icons.file_download_outlined,
              ),
            ],
          ),
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
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('Choose Folder', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => Navigator.of(context).pop(_selectedMode),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required ThemeData theme,
    required SafStorageMode mode,
    required String title,
    required String badge,
    required Color badgeColor,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : isDark
                    ? const Color(0xFF2B2824)
                    : const Color(0xFFE2E7ED),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<SafStorageMode>(
              value: mode,
              activeColor: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
