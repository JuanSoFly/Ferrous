import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/features/settings/app_themes.dart';

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

  String get _cleanWord {
    var trimmed = word.trim();
    trimmed = trimmed.replaceAll(RegExp(r'^[^\w\d]+|[^\w\d]+$', unicode: true), '');
    if (trimmed.isEmpty) return word.trim();
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final safeTop = mediaQuery.padding.top;
    final safeBottom = mediaQuery.padding.bottom;

    const overlayWidth = 230.0;
    const overlayHeight = 52.0;

    // Center horizontally over tap position, clamped within screen margins
    final left = (position.dx - (overlayWidth / 2)).clamp(16.0, (screenSize.width - overlayWidth - 16.0).clamp(16.0, double.infinity));

    // Position above the tap point by default; flip below if too close to the top
    final bool placeBelow = (position.dy - overlayHeight - 16.0) < (safeTop + 56.0);
    final top = (placeBelow
            ? position.dy + 20.0
            : position.dy - overlayHeight - 14.0)
        .clamp(safeTop + 8.0, (screenSize.height - safeBottom - overlayHeight - 8.0).clamp(safeTop + 8.0, double.infinity));

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onCancel,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Prevent taps on the card from triggering backdrop dismiss
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: isEInk ? 1.0 : 0.0, end: 1.0),
                  duration: isEInk ? Duration.zero : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, animVal, child) {
                    if (isEInk) return child!;
                    return Transform.scale(
                      scale: 0.88 + 0.12 * animVal,
                      alignment: placeBelow ? Alignment.topCenter : Alignment.bottomCenter,
                      child: Opacity(
                        opacity: animVal,
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: overlayWidth,
                      height: overlayHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isEInk
                            ? const Color(0xFFEAE6DF)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
                        border: Border.all(
                          color: isEInk
                              ? const Color(0xFF1A1A18)
                              : colorScheme.outlineVariant.withValues(alpha: 0.45),
                          width: isEInk ? 1.5 : 1.0,
                        ),
                        boxShadow: isEInk
                            ? const [
                                BoxShadow(
                                  color: Color(0xFF1A1A18),
                                  offset: Offset(3, 3),
                                  blurRadius: 0,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                  spreadRadius: -2,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          // Speech indicator badge / button
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isEInk
                                  ? const Color(0xFFE0DCD3)
                                  : colorScheme.primary.withValues(alpha: 0.14),
                              borderRadius: isEInk ? BorderRadius.circular(2) : null,
                              shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                              border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                            ),
                            child: Icon(
                              Icons.volume_up_rounded,
                              size: 16,
                              color: isEInk ? const Color(0xFF1A1A18) : colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Target word display
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'READ FROM',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: isEInk ? const Color(0xFF1A1A18) : colorScheme.primary,
                                  ),
                                ),
                                Text(
                                  '"$_cleanWord"',
                                  style: isEInk
                                      ? GoogleFonts.robotoSlab(
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF1A1A18),
                                          height: 1.2,
                                        )
                                      : theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                          height: 1.2,
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // Vertical divider
                          Container(
                            height: 22,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: isEInk ? const Color(0xFF9E9A90) : colorScheme.outlineVariant.withValues(alpha: 0.45),
                          ),

                          // Confirm button (Check)
                          Tooltip(
                            message: 'Start reading here',
                            child: InkWell(
                              onTap: onConfirm,
                              borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isEInk ? const Color(0xFF1A1A18) : colorScheme.primary,
                                  borderRadius: isEInk ? BorderRadius.circular(2) : null,
                                  shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                                  border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                                  boxShadow: isEInk
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: colorScheme.primary.withValues(alpha: 0.35),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: isEInk ? const Color(0xFFEAE6DF) : colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Cancel button (X)
                          Tooltip(
                            message: 'Cancel',
                            child: InkWell(
                              onTap: onCancel,
                              borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isEInk
                                      ? const Color(0xFFE0DCD3)
                                      : colorScheme.surfaceContainerHigh,
                                  borderRadius: isEInk ? BorderRadius.circular(2) : null,
                                  shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                                  border: Border.all(
                                    color: isEInk ? const Color(0xFF1A1A18) : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: isEInk ? const Color(0xFF1A1A18) : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
