import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reader_app/core/services/update_service.dart';

/// Shows update dialog and returns true if user chose to update
Future<bool> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(updateInfo: updateInfo),
  );
  return result ?? false;
}

class _UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;

  const _UpdateDialog({required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Update Available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VersionRow(
            label: 'Current version',
            version: updateInfo.currentVersion,
          ),
          const SizedBox(height: 8),
          _VersionRow(
            label: 'New version',
            version: updateInfo.latestVersion,
            highlight: true,
          ),
          const SizedBox(height: 16),
          Text(
            'A new version of Ferrous is available. Update now to get the latest features and improvements.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final url = updateInfo.downloadUrl.isNotEmpty 
                ? updateInfo.downloadUrl 
                : updateInfo.htmlUrl;
            
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
            }
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          icon: const Icon(Icons.download),
          label: const Text('Update'),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String version;
  final bool highlight;

  const _VersionRow({
    required this.label,
    required this.version,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: highlight 
                ? theme.colorScheme.primaryContainer 
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'v$version',
            style: theme.textTheme.labelMedium?.copyWith(
              color: highlight
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
