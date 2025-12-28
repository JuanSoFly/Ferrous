import 'package:flutter/material.dart';

/// A minimal overlay widget for confirming a tap-to-start TTS selection.
/// Shows the selected word with confirm (✓) and cancel (✗) buttons.
class TapSelectionOverlay extends StatelessWidget {
  final String word;
  final Offset position;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const TapSelectionOverlay({
    super.key,
    required this.word,
    required this.position,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Truncate long words for display
    final displayWord = word.length > 20 ? '${word.substring(0, 17)}...' : word;

    return Positioned(
      left: position.dx - 60, // Center the overlay roughly
      top: position.dy - 70, // Position above the tap
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: isDark ? Colors.grey.shade800 : Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 200),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selected word display
              Flexible(
                child: Text(
                  '"$displayWord"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Confirm button
              _ActionButton(
                icon: Icons.check,
                color: Colors.green,
                onTap: onConfirm,
                tooltip: 'Start here',
              ),
              const SizedBox(width: 4),
              // Cancel button
              _ActionButton(
                icon: Icons.close,
                color: Colors.red,
                onTap: onCancel,
                tooltip: 'Cancel',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }
}
