import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/annotation.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';

Future<void> showAnnotationDetailSheet(BuildContext context, Annotation annotation) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AnnotationDetailSheet(annotation: annotation),
  );
}

class _AnnotationDetailSheet extends StatefulWidget {
  final Annotation annotation;

  const _AnnotationDetailSheet({required this.annotation});

  @override
  State<_AnnotationDetailSheet> createState() => _AnnotationDetailSheetState();
}

class _AnnotationDetailSheetState extends State<_AnnotationDetailSheet> {
  late Annotation _annotation;

  @override
  void initState() {
    super.initState();
    _annotation = widget.annotation;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _handleEdit(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AnnotationDialog(
        selectedText: _annotation.selectedText,
        initialNote: _annotation.note,
        initialColor: _annotation.color,
      ),
    );

    if (result != null && mounted) {
      final updatedNote = (result['note'] as String?)?.trim();
      final updatedColor = result['color'] as int? ?? _annotation.color;

      final updatedAnnotation = _annotation.copyWith(
        note: updatedNote != null && updatedNote.isNotEmpty ? updatedNote : null,
        color: updatedColor,
      );

      final repo = context.read<AnnotationRepository>();
      await repo.updateAnnotation(updatedAnnotation);

      if (mounted) {
        setState(() {
          _annotation = updatedAnnotation;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Annotation updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final repo = context.read<AnnotationRepository>();
    await repo.deleteAnnotation(_annotation.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Annotation deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(_annotation.color);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outline, width: 1),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Annotation',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(_annotation.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Selected text preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: color, width: 4),
              ),
            ),
            child: Text(
              _annotation.selectedText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),

          // Note section
          if (_annotation.note != null && _annotation.note!.isNotEmpty) ...[
            Text(
              'Note',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _annotation.note!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No note attached.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _handleDelete(context),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                onPressed: () => _handleEdit(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
