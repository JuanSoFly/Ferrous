import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/services/feedback_service.dart';

/// Modal bottom sheet presenting user feedback and issue reporting options.
/// Respects E-Ink display guidelines with instantaneous animations when [isEInk] is true.
class FeedbackOptionsSheet extends StatelessWidget {
  final bool isEInk;
  final String currentThemeName;

  const FeedbackOptionsSheet({
    super.key,
    required this.isEInk,
    required this.currentThemeName,
  });

  /// Static helper to display the sheet with the correct E-Ink animation style.
  static Future<void> show(
    BuildContext context, {
    required bool isEInk,
    required String currentThemeName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
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
      builder: (_) => FeedbackOptionsSheet(
        isEInk: isEInk,
        currentThemeName: currentThemeName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color textColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface;
    final Color subtitleColor = isEInk
        ? const Color(0xFF4A4945)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  color: isEInk
                      ? const Color(0xFF1A1A18)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Feedback & Community',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.3,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Help improve Ferrous or report rendering and reading problems.',
                style: TextStyle(fontSize: 13, color: subtitleColor),
              ),
            ),
            const SizedBox(height: 16),

            _buildOptionTile(
              context: context,
              theme: theme,
              icon: Icons.bug_report_outlined,
              title: 'Report a Problem',
              subtitle: 'Opens GitHub with your device info & copies logs to clipboard',
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                FeedbackService.openBugReport(currentTheme: currentThemeName);
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              context: context,
              theme: theme,
              icon: Icons.lightbulb_outline,
              title: 'Suggest an Improvement',
              subtitle: 'Propose a new feature, format, or visual polish',
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                FeedbackService.openFeatureRequest();
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              context: context,
              theme: theme,
              icon: Icons.code_outlined,
              title: 'GitHub Repository',
              subtitle: 'Browse source code, releases, and discussions',
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                FeedbackService.openRepository();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final border = isEInk
        ? Border.all(color: const Color(0xFF1A1A18), width: 1)
        : Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
          border: border,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEInk
                    ? const Color(0xFFEAE6DF)
                    : theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.xs),
                border: isEInk
                    ? Border.all(color: const Color(0xFF1A1A18), width: 1)
                    : null,
              ),
              child: Icon(
                icon,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                      color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isEInk
                          ? const Color(0xFF4A4945)
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isEInk
                  ? const Color(0xFF1A1A18)
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
