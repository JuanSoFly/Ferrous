import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/library_location.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:reader_app/features/reader/widgets/kindle_popup_menu.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class LocationCard extends StatelessWidget {
  final LibraryLocation location;
  final VoidCallback onTap;
  final VoidCallback onRescan;
  final VoidCallback onViewBooks;
  final VoidCallback onDetails;
  final ValueChanged<SafStorageMode> onModeChanged;
  final VoidCallback onRemove;

  const LocationCard({
    super.key,
    required this.location,
    required this.onTap,
    required this.onRescan,
    required this.onViewBooks,
    required this.onDetails,
    required this.onModeChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;
    final isDark = theme.brightness == Brightness.dark;
    final isLinked = location.storageMode == SafStorageMode.linked;

    return Card(
      elevation: 0,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        side: BorderSide(
          color: isEInk
              ? const Color(0xFF1A1A18)
              : (location.isValid
                  ? (isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED))
                  : Colors.redAccent.withValues(alpha: 0.5)),
          width: isEInk ? 1.0 : (location.isValid ? 1.0 : 1.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Folder Icon with status indicator
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isEInk
                              ? const Color(0xFFEAE6DF)
                              : theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 12),
                          border: isEInk
                              ? Border.all(color: const Color(0xFF1A1A18), width: 1.0)
                              : null,
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isEInk
                                ? const Color(0xFF1A1A18)
                                : (location.isValid
                                    ? const Color(0xFF10B981)
                                    : Colors.redAccent),
                            border: Border.all(
                              color: isEInk ? const Color(0xFFEAE6DF) : theme.cardColor,
                              width: isEInk ? 1.5 : 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Name and readable path
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.displayName,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A18),
                                )
                              : const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          location.readablePath,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 12,
                                  color: const Color(0xFF4A4945),
                                )
                              : TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Rescan button or spinner
                  if (location.isScanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.sync_rounded, color: isEInk ? const Color(0xFF1A1A18) : null),
                      tooltip: 'Rescan Folder',
                      onPressed: onRescan,
                    ),
                  // Overflow menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: isEInk ? const Color(0xFF1A1A18) : null),
                    shape: isEInk
                        ? const KindlePopupShape()
                        : RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                    color: isEInk ? const Color(0xFFEAE6DF) : null,
                    elevation: isEInk ? 0 : 4,
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          onViewBooks();
                          break;
                        case 'details':
                          onDetails();
                          break;
                        case 'toggle_mode':
                          final newMode = isLinked
                              ? SafStorageMode.imported
                              : SafStorageMode.linked;
                          onModeChanged(newMode);
                          break;
                        case 'remove':
                          onRemove();
                          break;
                      }
                    },
                    itemBuilder: (context) => isEInk
                        ? [
                            const PopupMenuItem(
                              value: 'view',
                              padding: EdgeInsets.zero,
                              height: 42,
                              child: KindlePopupItem(
                                icon: Icons.auto_stories_outlined,
                                label: 'View Books',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'details',
                              padding: EdgeInsets.zero,
                              height: 42,
                              child: KindlePopupItem(
                                icon: Icons.info_outline_rounded,
                                label: 'Folder Details',
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle_mode',
                              padding: EdgeInsets.zero,
                              height: 42,
                              child: KindlePopupItem(
                                icon: Icons.swap_horiz_rounded,
                                label: isLinked ? 'Switch to Imported' : 'Switch to Linked',
                              ),
                            ),
                            const KindlePopupDivider(),
                            const PopupMenuItem(
                              value: 'remove',
                              padding: EdgeInsets.zero,
                              height: 42,
                              child: KindlePopupItem(
                                icon: Icons.delete_outline_rounded,
                                label: 'Remove Location',
                                isDestructive: true,
                              ),
                            ),
                          ]
                        : [
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.auto_stories_outlined, size: 18),
                                  SizedBox(width: 12),
                                  Text('View Books'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 18),
                                  SizedBox(width: 12),
                                  Text('Folder Details'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle_mode',
                              child: Row(
                                children: [
                                  const Icon(Icons.swap_horiz_rounded, size: 18),
                                  const SizedBox(width: 12),
                                  Text(isLinked ? 'Switch to Imported' : 'Switch to Linked'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                  SizedBox(width: 12),
                                  Text('Remove Location', style: TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                          ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Badges row
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Mode badge
                  if (isEInk)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isLinked ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: const Color(0xFF1A1A18),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLinked ? Icons.link_rounded : Icons.file_download_outlined,
                            size: 11,
                            color: isLinked ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLinked ? 'LINKED' : 'IMPORTED',
                            style: GoogleFonts.robotoSlab(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: isLinked ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isLinked ? const Color(0xFF10B981) : const Color(0xFF8B5CF6))
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isLinked ? const Color(0xFF10B981) : const Color(0xFF8B5CF6))
                              .withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLinked ? Icons.link_rounded : Icons.file_download_outlined,
                            size: 11,
                            color: isLinked ? const Color(0xFF34D399) : const Color(0xFFA78BFA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLinked ? 'LINKED' : 'IMPORTED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: isLinked ? const Color(0xFF34D399) : const Color(0xFFA78BFA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Book count badge
                  if (isEInk)
                    InkWell(
                      onTap: onViewBooks,
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAE6DF),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: const Color(0xFF1A1A18),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_stories_outlined,
                              size: 11,
                              color: Color(0xFF1A1A18),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${location.bookCount} book${location.bookCount == 1 ? '' : 's'}',
                              style: GoogleFonts.robotoSlab(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A1A18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: onViewBooks,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_stories_outlined,
                              size: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${location.bookCount} book${location.bookCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Total size
                  if (location.totalSizeBytes > 0)
                    if (isEInk)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAE6DF),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: const Color(0xFF1A1A18),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          LibraryLocation.formatBytes(location.totalSizeBytes),
                          style: GoogleFonts.robotoSlab(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A18),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          LibraryLocation.formatBytes(location.totalSizeBytes),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  // Permission warning badge if revoked
                  if (!location.isValid)
                    if (isEInk)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAE6DF),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: const Color(0xFF1A1A18),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFF1A1A18)),
                            const SizedBox(width: 4),
                            Text(
                              'PERMISSION REVOKED',
                              style: GoogleFonts.robotoSlab(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: const Color(0xFF1A1A18),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 11, color: Colors.redAccent),
                            SizedBox(width: 4),
                            Text(
                              'PERMISSION REVOKED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
