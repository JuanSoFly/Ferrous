import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/library_location.dart';
import 'package:reader_app/data/repositories/library_location_repository.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:reader_app/features/reader/widgets/kindle_popup_menu.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/library_locations/widgets/add_location_dialog.dart';
import 'package:reader_app/features/settings/library_locations/widgets/location_books_sheet.dart';
import 'package:reader_app/features/settings/library_locations/widgets/location_card.dart';
import 'package:reader_app/features/settings/library_locations/widgets/location_details_sheet.dart';
import 'package:reader_app/features/settings/library_locations/widgets/remove_location_dialog.dart';

class LibraryLocationsScreen extends StatelessWidget {
  const LibraryLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;
    final repo = context.watch<LibraryLocationRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Library Locations',
          style: isEInk ? GoogleFonts.robotoSlab(fontWeight: FontWeight.bold) : null,
        ),
        actions: [
          // Rescan All Button
          if (repo.isScanningAll)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.sync_rounded, color: isEInk ? const Color(0xFF1A1A18) : null),
              tooltip: 'Rescan All Locations',
              onPressed: repo.isLoading
                  ? null
                  : () => _handleRescanAll(context, repo),
            ),
          // More Options
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: isEInk ? const Color(0xFF1A1A18) : null),
            shape: isEInk
                ? const KindlePopupShape()
                : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: isEInk ? Colors.transparent : null,
            elevation: isEInk ? 0 : 4,
            onSelected: (val) {
              if (val == 'cleanup') {
                _handleCleanupStale(context, repo);
              } else if (val == 'formats') {
                _showSupportedFormatsDialog(context);
              }
            },
            itemBuilder: (context) => isEInk
                ? [
                    const PopupMenuItem(
                      value: 'cleanup',
                      padding: EdgeInsets.zero,
                      height: 42,
                      child: KindlePopupItem(
                        icon: Icons.cleaning_services_outlined,
                        label: 'Clean Up Stale Locations',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'formats',
                      padding: EdgeInsets.zero,
                      height: 42,
                      child: KindlePopupItem(
                        icon: Icons.description_outlined,
                        label: 'Supported Formats',
                      ),
                    ),
                  ]
                : [
                    const PopupMenuItem(
                      value: 'cleanup',
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services_outlined, size: 18),
                          SizedBox(width: 12),
                          Text('Clean Up Stale Locations'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'formats',
                      child: Row(
                        children: [
                          Icon(Icons.description_outlined, size: 18),
                          SizedBox(width: 12),
                          Text('Supported Formats'),
                        ],
                      ),
                    ),
                  ],
          ),
        ],
      ),
      floatingActionButton: isEInk
          ? Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF9E9A90),
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: const Color(0xFF1A1A18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                  side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(2),
                  splashColor: Colors.transparent,
                  highlightColor: const Color(0xFF3D3C38),
                  onTap: () => _handleAddLocation(context, repo),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 20, color: Color(0xFFEAE6DF)),
                        const SizedBox(width: 8),
                        Text(
                          'Add Folder',
                          style: GoogleFonts.robotoSlab(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: const Color(0xFFEAE6DF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : FloatingActionButton.extended(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Folder',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _handleAddLocation(context, repo),
            ),
      body: RefreshIndicator(
        onRefresh: () => repo.refreshLocations(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, isEInk ? 120 : 96),
          children: [
            // Summary Header Card
            _buildSummaryHeader(context, theme, repo, isEInk: isEInk),
            const SizedBox(height: 20),
            // Section Header
            _buildSectionHeader(theme, 'CONFIGURED FOLDERS', count: repo.locations.length, isEInk: isEInk),
            const SizedBox(height: 10),
            // Locations List or Empty State
            if (repo.isLoading && repo.locations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (repo.locations.isEmpty)
              _buildEmptyState(context, theme, repo, isEInk: isEInk)
            else
              ...repo.locations.map(
                (loc) => LocationCard(
                  key: ValueKey(loc.id),
                  location: loc,
                  onTap: () => _openDetails(context, repo, loc),
                  onRescan: () => _handleRescanSingle(context, repo, loc),
                  onViewBooks: () => _openBooks(context, repo, loc),
                  onDetails: () => _openDetails(context, repo, loc),
                  onModeChanged: (newMode) => _handleModeChange(context, repo, loc, newMode),
                  onRemove: () => _handleRemoveLocation(context, repo, loc),
                ),
              ),
            const SizedBox(height: 24),
            // Storage Modes & Help Card
            _buildHelpCard(context, theme, isEInk: isEInk),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(
    BuildContext context,
    ThemeData theme,
    LibraryLocationRepository repo, {
    bool isEInk = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final totalBooks = repo.totalBooksInLocations;
    final totalSize = LibraryLocation.formatBytes(repo.totalStorageBytes);
    final totalFolders = repo.locations.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEInk
            ? const Color(0xFFE0DCD3)
            : (isDark ? const Color(0xFF1E1C19) : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        border: Border.all(
          color: isEInk
              ? const Color(0xFF1A1A18)
              : (isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED)),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.storage_rounded,
                size: 20,
                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Library Storage Overview',
                style: isEInk
                    ? GoogleFonts.robotoSlab(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A18))
                    : const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildMetricTile(
                theme: theme,
                label: 'FOLDERS',
                value: '$totalFolders',
                icon: Icons.folder_outlined,
                isEInk: isEInk,
              ),
              _buildMetricDivider(theme, isEInk: isEInk),
              _buildMetricTile(
                theme: theme,
                label: 'BOOKS LINKED',
                value: '$totalBooks',
                icon: Icons.auto_stories_outlined,
                isEInk: isEInk,
              ),
              _buildMetricDivider(theme, isEInk: isEInk),
              _buildMetricTile(
                theme: theme,
                label: 'TOTAL SIZE',
                value: totalSize,
                icon: Icons.data_usage_rounded,
                isEInk: isEInk,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
    bool isEInk = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: isEInk
                ? GoogleFonts.robotoSlab(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A18),
                  )
                : const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: isEInk
                ? GoogleFonts.robotoSlab(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: const Color(0xFF4A4945),
                  )
                : TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDivider(ThemeData theme, {bool isEInk = false}) {
    return Container(
      width: 1,
      height: 32,
      color: isEInk
          ? const Color(0xFF9E9A90)
          : (theme.brightness == Brightness.dark
              ? const Color(0xFF2B2824)
              : const Color(0xFFE2E7ED)),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, {int? count, bool isEInk = false}) {
    return Row(
      children: [
        Text(
          title,
          style: isEInk
              ? GoogleFonts.robotoSlab(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: const Color(0xFF1A1A18),
                )
              : TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.primary,
                ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(isEInk ? 2 : 10),
              border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
            ),
            child: Text(
              '$count',
              style: isEInk
                  ? GoogleFonts.robotoSlab(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A18),
                    )
                  : TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    LibraryLocationRepository repo, {
    bool isEInk = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFE0DCD3) : (isDark ? const Color(0xFF1E1C19) : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        border: Border.all(
          color: isEInk ? const Color(0xFF1A1A18) : (isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED)),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEInk
                  ? const Color(0xFFEAE6DF)
                  : theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isEInk ? BorderRadius.circular(2) : null,
              border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
            ),
            child: Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Library Locations',
            style: isEInk
                ? GoogleFonts.robotoSlab(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A18),
                  )
                : const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add folders from your device to scan for eBooks. You can link them directly to save storage or import books to app storage.',
            textAlign: TextAlign.center,
            style: isEInk
                ? GoogleFonts.robotoSlab(
                    fontSize: 13,
                    height: 1.4,
                    color: const Color(0xFF4A4945),
                  )
                : TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
          ),
          const SizedBox(height: 20),
          if (isEInk)
            Material(
              color: const Color(0xFF1A1A18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
                side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(2),
                onTap: () => _handleAddLocation(context, repo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 20, color: Color(0xFFEAE6DF)),
                      const SizedBox(width: 8),
                      Text(
                        'Add Your First Folder',
                        style: GoogleFonts.robotoSlab(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFEAE6DF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add Your First Folder',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _handleAddLocation(context, repo),
            ),
        ],
      ),
    );
  }

  Widget _buildHelpCard(BuildContext context, ThemeData theme, {bool isEInk = false}) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEInk ? const Color(0xFFE0DCD3) : (isDark ? const Color(0xFF1E1C19) : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        border: Border.all(
          color: isEInk ? const Color(0xFF1A1A18) : (isDark ? const Color(0xFF2B2824) : const Color(0xFFE2E7ED)),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'About Library Storage Modes',
                style: isEInk
                    ? GoogleFonts.robotoSlab(fontSize: 13.5, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A18))
                    : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHelpBullet(
            theme: theme,
            title: 'Linked Storage:',
            desc:
                'Keeps original files in place on your device. Zero extra storage consumed. Ideal for SD cards and large collections.',
            badgeColor: const Color(0xFF10B981),
            isEInk: isEInk,
            isImported: false,
          ),
          const SizedBox(height: 8),
          _buildHelpBullet(
            theme: theme,
            title: 'Imported Storage:',
            desc:
                'Copies files into Ferrous private sandbox. Safe from accidental external deletion or cleanup apps.',
            badgeColor: const Color(0xFF8B5CF6),
            isEInk: isEInk,
            isImported: true,
          ),
          const SizedBox(height: 14),
          Text(
            'SUPPORTED FORMATS',
            style: isEInk
                ? GoogleFonts.robotoSlab(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: const Color(0xFF1A1A18))
                : const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FormatChip(ext: 'EPUB', isEInk: isEInk),
              _FormatChip(ext: 'PDF', isEInk: isEInk),
              _FormatChip(ext: 'CBZ', isEInk: isEInk),
              _FormatChip(ext: 'MOBI', isEInk: isEInk),
              _FormatChip(ext: 'AZW', isEInk: isEInk),
              _FormatChip(ext: 'AZW3', isEInk: isEInk),
              _FormatChip(ext: 'DOCX', isEInk: isEInk),
              _FormatChip(ext: 'TXT', isEInk: isEInk),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHelpBullet({
    required ThemeData theme,
    required String title,
    required String desc,
    required Color badgeColor,
    bool isEInk = false,
    bool isImported = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEInk)
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isImported ? const Color(0xFFE0DCD3) : const Color(0xFF1A1A18),
              borderRadius: BorderRadius.circular(1),
              border: Border.all(
                color: const Color(0xFF1A1A18),
                width: 1.5,
              ),
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$title ',
              style: isEInk
                  ? GoogleFonts.robotoSlab(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF1A1A18))
                  : const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              children: [
                TextSpan(
                  text: desc,
                  style: isEInk
                      ? GoogleFonts.robotoSlab(
                          fontWeight: FontWeight.normal,
                          fontSize: 12,
                          color: const Color(0xFF4A4945),
                        )
                      : TextStyle(
                          fontWeight: FontWeight.normal,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAddLocation(
    BuildContext context,
    LibraryLocationRepository repo,
  ) async {
    final mode = await AddLocationDialog.show(context);
    if (mode == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await repo.addLocation(mode: mode);

    if (!context.mounted) return;

    if (result.isSuccess) {
      if (result.addedCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Added ${result.addedCount} new books to your library!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result.totalScanned > 0) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Folder added. All found books were already in your library.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (result.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${result.errorMessage}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRescanSingle(
    BuildContext context,
    LibraryLocationRepository repo,
    LibraryLocation location,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await repo.rescanLocation(location);

    if (!context.mounted) return;

    if (result.isSuccess) {
      final msg = result.addedCount > 0
          ? 'Found and added ${result.addedCount} new books from ${location.displayName}.'
          : '${location.displayName} is up to date (no new books found).';
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to rescan: ${result.errorMessage}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRescanAll(
    BuildContext context,
    LibraryLocationRepository repo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await repo.rescanAllLocations();

    if (!context.mounted) return;

    if (result.isSuccess) {
      final msg = result.addedCount > 0
          ? 'Rescan complete: Added ${result.addedCount} new books.'
          : 'All locations are up to date.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Rescan failed: ${result.errorMessage}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRemoveLocation(
    BuildContext context,
    LibraryLocationRepository repo,
    LibraryLocation location,
  ) async {
    final decision = await RemoveLocationDialog.show(context, location);
    if (decision == null || !decision.confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await repo.removeLocation(
      location,
      removeAssociatedBooks: decision.removeAssociatedBooks,
    );

    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Removed "${location.displayName}"${decision.removeAssociatedBooks ? ' and associated books' : ''}.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleModeChange(
    BuildContext context,
    LibraryLocationRepository repo,
    LibraryLocation location,
    SafStorageMode newMode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await repo.updateLocationMode(location, newMode);

    if (!context.mounted) return;

    final modeLabel = newMode == SafStorageMode.linked ? 'Linked' : 'Imported';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Updated "${location.displayName}" to $modeLabel storage.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCleanupStale(
    BuildContext context,
    LibraryLocationRepository repo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final removed = await repo.cleanupStaleLocations();

    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removed > 0
              ? 'Cleaned up $removed stale or inaccessible locations.'
              : 'All configured locations have valid permissions.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openBooks(
    BuildContext context,
    LibraryLocationRepository repo,
    LibraryLocation location,
  ) {
    final books = repo.getBooksForLocation(location);
    LocationBooksSheet.show(context, location: location, books: books);
  }

  void _openDetails(
    BuildContext context,
    LibraryLocationRepository repo,
    LibraryLocation location,
  ) {
    final books = repo.getBooksForLocation(location);
    LocationDetailsSheet.show(
      context,
      location: location,
      books: books,
      onRescan: () => _handleRescanSingle(context, repo, location),
      onViewBooks: () => _openBooks(context, repo, location),
      onModeChanged: (newMode) => _handleModeChange(context, repo, location, newMode),
      onRemove: () => _handleRemoveLocation(context, repo, location),
    );
  }

  void _showSupportedFormatsDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supported eBook Formats'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ferrous automatically scans folders for the following eBook and document file types:',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const _FormatInfoRow(fmt: 'EPUB (.epub)', desc: 'Standard electronic publication with reflowable layout.'),
            const _FormatInfoRow(fmt: 'PDF (.pdf)', desc: 'Portable document format with fixed-page rendering.'),
            const _FormatInfoRow(fmt: 'CBZ (.cbz, .cbr)', desc: 'Comic book zip archive with image viewer.'),
            const _FormatInfoRow(fmt: 'MOBI / AZW (.mobi, .azw, .azw3)', desc: 'Amazon Kindle ebook formats.'),
            const _FormatInfoRow(fmt: 'DOCX (.docx)', desc: 'Microsoft Word document format.'),
            const _FormatInfoRow(fmt: 'TXT (.txt)', desc: 'Plain text documents with continuous reading.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String ext;
  final bool isEInk;
  const _FormatChip({required this.ext, this.isEInk = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isEInk) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFEAE6DF),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: const Color(0xFF1A1A18),
            width: 1.0,
          ),
        ),
        child: Text(
          '.$ext',
          style: GoogleFonts.robotoSlab(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A18),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        '.$ext',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _FormatInfoRow extends StatelessWidget {
  final String fmt;
  final String desc;
  const _FormatInfoRow({required this.fmt, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fmt,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 1),
          Text(
            desc,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
