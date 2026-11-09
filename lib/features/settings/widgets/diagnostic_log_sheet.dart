import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/services/diagnostic_logger.dart';

/// Modal bottom sheet displaying recent in-memory diagnostic events.
/// Logs are rendered in reverse chronological order (newest first) using
/// [ListView.builder] for zero jank and lazy allocation.
class DiagnosticLogSheet extends StatefulWidget {
  final bool isEInk;

  const DiagnosticLogSheet({
    super.key,
    required this.isEInk,
  });

  /// Static helper to display the sheet with the correct E-Ink animation style.
  static Future<void> show(BuildContext context, {required bool isEInk}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: isEInk ? AnimationStyle.noAnimation : null,
      backgroundColor: isEInk ? const Color(0xFFEAE6DF) : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isEInk ? 2 : AppRadius.sheet),
        ),
        side: isEInk
            ? const BorderSide(color: Color(0xFF1A1A18), width: 1)
            : BorderSide.none,
      ),
      builder: (_) => DiagnosticLogSheet(isEInk: isEInk),
    );
  }

  @override
  State<DiagnosticLogSheet> createState() => _DiagnosticLogSheetState();
}

class _DiagnosticLogSheetState extends State<DiagnosticLogSheet> {
  bool _copied = false;

  void _handleCopyAll() async {
    HapticFeedback.lightImpact();
    final plainText = DiagnosticLogger.instance.formatPlainText(includeStack: true);
    await Clipboard.setData(ClipboardData(text: plainText));
    if (!mounted) return;
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Diagnostic logs copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _handleClear() {
    HapticFeedback.lightImpact();
    DiagnosticLogger.instance.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Diagnostic logs cleared'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = DiagnosticLogger.instance.getEntries();
    final isEInk = widget.isEInk;

    final Color primaryColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary;
    final Color textColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface;
    final Color subtitleColor = isEInk
        ? const Color(0xFF4A4945)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle / Notch
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnostics & Logs',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                            letterSpacing: -0.3,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entries.length} of ${DiagnosticLogger.maxCapacity} buffered events',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (entries.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Copy all logs',
                      onPressed: _handleCopyAll,
                      icon: Icon(
                        _copied ? Icons.check : Icons.copy_all_outlined,
                        size: 20,
                        color: primaryColor,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear logs',
                      onPressed: _handleClear,
                      icon: Icon(
                        Icons.delete_sweep_outlined,
                        size: 20,
                        color: isEInk ? primaryColor : theme.colorScheme.error,
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: textColor),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Log entries list
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No diagnostic events recorded.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isEInk ? FontWeight.w700 : FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Errors and key reader events will appear here.',
                            style: TextStyle(fontSize: 12, color: subtitleColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: entries.length,
                      // Reverse chronological order: newest entry (at end of buffer) displayed first
                      itemBuilder: (context, index) {
                        final entry = entries[entries.length - 1 - index];
                        return _buildLogEntryCard(entry, theme, isEInk);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogEntryCard(LogEntry entry, ThemeData theme, bool isEInk) {
    final timeStr = entry.timestamp.toIso8601String().substring(11, 23);
    final isError = entry.level == LogLevel.error;
    final isWarning = entry.level == LogLevel.warning;

    Color levelColor;
    if (isEInk) {
      levelColor = const Color(0xFF1A1A18);
    } else if (isError) {
      levelColor = theme.colorScheme.error;
    } else if (isWarning) {
      levelColor = Colors.orange;
    } else {
      levelColor = theme.colorScheme.primary;
    }

    final cardBorder = isEInk
        ? Border.all(color: const Color(0xFF1A1A18), width: 1)
        : Border.all(
            color: isError
                ? theme.colorScheme.error.withValues(alpha: 0.3)
                : (theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
            width: 1,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEInk
            ? const Color(0xFFE0DCD3)
            : (isError
                ? theme.colorScheme.error.withValues(alpha: 0.05)
                : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
        border: cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isEInk
                      ? const Color(0xFF1A1A18)
                      : levelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(isEInk ? 1 : 4),
                ),
                child: Text(
                  entry.level.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: isEInk ? const Color(0xFFEAE6DF) : levelColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '[${entry.tag}]',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: isEInk
                      ? const Color(0xFF4A4945)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // entry.message is already sanitized on ingestion in DiagnosticLogger
          SelectableText(
            entry.message,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface,
            ),
          ),
          if (entry.stackTrace != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isEInk
                    ? const Color(0xFFD6D1C6)
                    : (theme.brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(isEInk ? 2 : 4),
              ),
              child: SelectableText(
                DiagnosticLogger.sanitize(entry.stackTrace.toString().trimRight()),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: isEInk
                      ? const Color(0xFF1A1A18)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
