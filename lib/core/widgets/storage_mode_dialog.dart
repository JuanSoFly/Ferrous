import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/constants/app_constants.dart';
import 'package:ferrous/data/services/saf_service.dart';
import 'package:ferrous/features/settings/app_themes.dart';

/// Target type for storage mode selection.
enum StorageTargetType {
  books,
  folder,
}

/// A theme-aware, accessible dialog for choosing between Linked and Imported storage modes.
///
/// Fully supports E-Ink (monochrome, high-contrast, Roboto Slab, sharp borders)
/// as well as standard themes (Ferrous, Console, Sepia, Light, Dark).
class StorageModeDialog extends StatefulWidget {
  final StorageTargetType targetType;

  const StorageModeDialog({
    super.key,
    required this.targetType,
  });

  /// Displays the storage mode dialog and returns the selected [SafStorageMode],
  /// or null if the user cancelled.
  static Future<SafStorageMode?> show(
    BuildContext context, {
    required StorageTargetType targetType,
  }) {
    final currentTheme = context.read<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    return showDialog<SafStorageMode>(
      context: context,
      barrierColor: isEInk ? const Color(0xFF1A1A18).withValues(alpha: 0.14) : null,
      builder: (dialogContext) => StorageModeDialog(targetType: targetType),
    );
  }

  @override
  State<StorageModeDialog> createState() => _StorageModeDialogState();
}

class _StorageModeDialogState extends State<StorageModeDialog> {
  SafStorageMode _selectedMode = SafStorageMode.linked;

  bool get _isBooks => widget.targetType == StorageTargetType.books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;
    final isConsole = currentTheme == AppTheme.console;

    if (isEInk) {
      return _buildEInkDialog(context);
    }

    return _buildStandardDialog(context, theme, isConsole);
  }

  // --- E-INK HIGH-CONTRAST DIALOG ---

  Widget _buildEInkDialog(BuildContext context) {
    final title = _isBooks ? 'Add Books' : 'Add Folder';
    final subtitle = _isBooks
        ? 'Choose how to store and manage selected books:'
        : 'Choose how books in this folder should be stored and managed:';
    final primaryButtonLabel = _isBooks ? 'Select Books' : 'Choose Folder';
    final primaryIcon = _isBooks ? Icons.note_add_outlined : Icons.folder_open_rounded;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: const BoxDecoration(
              color: Color(0xFFEAE6DF),
              borderRadius: BorderRadius.all(Radius.circular(2)),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF1A1A18),
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
              border: Border.fromBorderSide(
                BorderSide(color: Color(0xFF1A1A18), width: 1.5),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0DCD3),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
                      ),
                      child: Icon(
                        _isBooks ? Icons.menu_book_outlined : Icons.folder_open_outlined,
                        color: const Color(0xFF1A1A18),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.robotoSlab(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                          color: const Color(0xFF1A1A18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: GoogleFonts.robotoSlab(
                    fontSize: 12.5,
                    height: 1.35,
                    color: const Color(0xFF4A4945),
                  ),
                ),
                const SizedBox(height: 16),
                // Option 1: Link
                _buildEInkOptionCard(
                  mode: SafStorageMode.linked,
                  title: _isBooks ? 'Link Files (Recommended)' : 'Link Folder (Recommended)',
                  badge: 'ZERO EXTRA STORAGE',
                  description: _isBooks
                      ? 'Read books directly from their original location on your device. Changes stay in sync and no duplicate storage is used.'
                      : 'Stream books directly from this folder. Ideal for SD cards, downloads, and large libraries without duplicating files.',
                  icon: Icons.link_rounded,
                ),
                const SizedBox(height: 10),
                // Option 2: Import
                _buildEInkOptionCard(
                  mode: SafStorageMode.imported,
                  title: _isBooks ? 'Import Files' : 'Import Folder',
                  badge: 'PERSISTENT COPY',
                  description: _isBooks
                      ? 'Copy books into Ferrous internal storage. Files stay safe in your library even if original documents are moved or deleted.'
                      : 'Copy all books from this folder into Ferrous private storage for completely independent offline access.',
                  icon: Icons.file_download_outlined,
                ),
                const SizedBox(height: 20),
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        backgroundColor: const Color(0xFFEAE6DF),
                        foregroundColor: const Color(0xFF1A1A18),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A18),
                        foregroundColor: const Color(0xFFEAE6DF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      icon: Icon(primaryIcon, size: 18),
                      label: Text(
                        primaryButtonLabel,
                        style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(_selectedMode);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEInkOptionCard({
    required SafStorageMode mode,
    required String title,
    required String badge,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;

    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: () {
        if (_selectedMode != mode) {
          HapticFeedback.selectionClick();
          setState(() => _selectedMode = mode);
        }
      },
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0DCD3) : const Color(0xFFEAE6DF),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10, left: 2),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                  border: Border.all(
                    color: const Color(0xFF1A1A18),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Center(
                        child: SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFEAE6DF),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.robotoSlab(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                            color: const Color(0xFF1A1A18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1A1A18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.robotoSlab(
                        fontSize: 9.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: isSelected ? const Color(0xFFEAE6DF) : const Color(0xFF4A4945),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.robotoSlab(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFF4A4945),
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

  // --- STANDARD THEMES DIALOG (Ferrous, Console, Sepia, Light, Dark) ---

  Widget _buildStandardDialog(
    BuildContext context,
    ThemeData theme,
    bool isConsole,
  ) {
    final title = _isBooks ? 'Add Books' : 'Add Folder';
    final subtitle = _isBooks
        ? 'Choose how to store and manage selected books:'
        : 'Choose how books in this folder should be stored and managed:';
    final primaryButtonLabel = _isBooks ? 'Select Books' : 'Choose Folder';
    final primaryIcon = _isBooks ? Icons.note_add_outlined : Icons.folder_open_rounded;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              _isBooks ? Icons.menu_book_rounded : Icons.create_new_folder_outlined,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: isConsole
                  ? GoogleFonts.firaCode(fontSize: 18, fontWeight: FontWeight.bold)
                  : theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                    ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: isConsole
                  ? GoogleFonts.firaCode(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
            ),
            const SizedBox(height: 14),
            _buildStandardOptionCard(
              theme: theme,
              isConsole: isConsole,
              mode: SafStorageMode.linked,
              title: _isBooks ? 'Link Files (Recommended)' : 'Link Folder (Recommended)',
              badge: 'ZERO EXTRA STORAGE',
              badgeColor: const Color(0xFF10B981),
              description: _isBooks
                  ? 'Read books directly from their original location on your device. Changes stay in sync and no duplicate space is used.'
                  : 'Stream books directly from this folder. Ideal for SD cards, downloads, and large libraries without duplicating files.',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 10),
            _buildStandardOptionCard(
              theme: theme,
              isConsole: isConsole,
              mode: SafStorageMode.imported,
              title: _isBooks ? 'Import Files' : 'Import Folder',
              badge: 'PERSISTENT COPY',
              badgeColor: const Color(0xFF8B5CF6),
              description: _isBooks
                  ? 'Copy books into Ferrous internal storage. Files stay safe in your library even if original documents are moved or deleted.'
                  : 'Copy all books from this folder into Ferrous private storage for completely independent offline access.',
              icon: Icons.file_download_outlined,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Text(
            'Cancel',
            style: isConsole
                ? GoogleFonts.firaCode(fontWeight: FontWeight.w600)
                : const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: Icon(primaryIcon, size: 18),
          label: Text(
            primaryButtonLabel,
            style: isConsole
                ? GoogleFonts.firaCode(fontWeight: FontWeight.bold)
                : const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(_selectedMode);
          },
        ),
      ],
    );
  }

  Widget _buildStandardOptionCard({
    required ThemeData theme,
    required bool isConsole,
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
      onTap: () {
        if (_selectedMode != mode) {
          HapticFeedback.selectionClick();
          setState(() => _selectedMode = mode);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
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
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10, left: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : isDark
                            ? const Color(0xFF6B665E)
                            : const Color(0xFF9E9A90),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: isConsole
                              ? GoogleFonts.firaCode(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                )
                              : TextStyle(
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  fontSize: 14.5,
                                ),
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
                        color: badgeColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: isConsole
                          ? GoogleFonts.firaCode(
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: badgeColor,
                            )
                          : TextStyle(
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
                    style: isConsole
                        ? GoogleFonts.firaCode(
                            fontSize: 11.5,
                            height: 1.35,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                          )
                        : TextStyle(
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
