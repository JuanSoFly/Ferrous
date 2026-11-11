import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/core/constants/dimension_tokens.dart';
import 'package:reader_app/features/settings/dimension_controller.dart';
import 'package:reader_app/features/library/widgets/dimension_book_views.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/features/collections/collections_tab.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/features/library/widgets/book_cover_shimmer.dart';
import 'package:reader_app/data/services/saf_service.dart';
import 'package:reader_app/core/models/book_format.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/features/library/widgets/book_view_items.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StateNotifierProvider<LibraryController, LibraryState>(
      create: (context) => LibraryController(
        context.read<BookRepository>(),
        collectionRepository: context.read<CollectionRepository>(),
        annotationRepository: context.read<AnnotationRepository>(),
      ),
      child: const _LibraryView(),
    );
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LibraryState>();
    final controller = context.read<LibraryController>();
    final theme = Theme.of(context);
    final dimensionState = context.watch<DimensionState>();
    final dimensionConfig = dimensionState.config;
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    // Sync search controller if cleared externally
    if (state.searchQuery.isEmpty && _searchController.text.isNotEmpty) {
      _searchController.clear();
    }

    final hasActiveSearch = _searchController.text.isNotEmpty || state.searchQuery.isNotEmpty;

    final searchRadius = isEInk
        ? BorderRadius.circular(2)
        : (dimensionConfig.cardRadius <= 0
            ? BorderRadius.zero
            : BorderRadius.circular(dimensionConfig.cardRadius.clamp(4.0, 24.0)));

    final searchHint = isEInk
        ? 'Search library...'
        : (dimensionConfig.isMonospace
            ? '> search library_'
            : (dimensionConfig.isSerif ? 'Search catalog...' : 'Search library...'));

    return PopScope(
      canPop: !hasActiveSearch,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _searchController.clear();
          controller.setSearchQuery('');
          FocusScope.of(context).unfocus();
          setState(() {});
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Container(
            height: 44,
            decoration: BoxDecoration(
              color: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainer,
              borderRadius: searchRadius,
              border: Border.all(
                color: isEInk
                    ? const Color(0xFF1A1A18)
                    : (dimensionConfig.cardBorderWidth > 1
                        ? theme.colorScheme.primary.withValues(alpha: 0.35)
                        : (theme.brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05))),
                width: isEInk ? 1.5 : (dimensionConfig.cardBorderWidth > 1 ? 1.5 : 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  DimensionIcons.search(dimensionConfig.iconStyle),
                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: searchHint,
                      hintStyle: isEInk
                          ? GoogleFonts.robotoSlab(
                              color: const Color(0xFF1A1A18).withValues(alpha: 0.7),
                              fontSize: 14,
                            )
                          : (dimensionConfig.isMonospace
                              ? GoogleFonts.firaCode(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  fontSize: 13,
                                )
                              : TextStyle(
                                  fontFamily: dimensionConfig.isSerif ? 'serif' : null,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  fontSize: 14,
                                )),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: isEInk
                        ? GoogleFonts.robotoSlab(fontSize: 14, color: const Color(0xFF1A1A18))
                        : (dimensionConfig.isMonospace
                            ? GoogleFonts.firaCode(fontSize: 13)
                            : TextStyle(
                                fontFamily: dimensionConfig.isSerif ? 'serif' : null,
                                fontSize: 14,
                              )),
                    onChanged: (value) => controller.setSearchQuery(value),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      controller.setSearchQuery('');
                      setState(() {});
                    },
                    child: Icon(
                      CupertinoIcons.clear_thick_circled,
                      color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(DimensionIcons.refresh(dimensionConfig.iconStyle)),
              onPressed: state.isLoading
                  ? null
                  : () => controller.rescanFolders(),
              tooltip: "Rescan Folders",
            ),
            IconButton(
              icon: Icon(DimensionIcons.addFolder(dimensionConfig.iconStyle)),
              onPressed: state.isLoading
                  ? null
                  : () async {
                      final mode = await _promptStorageMode(context);
                      if (mode != null && context.mounted) {
                        controller.pickAndScanDirectory(mode);
                      }
                    },
              tooltip: "Add Folder",
            ),
            const SizedBox(width: 6),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                height: 36,
                padding: isEInk ? EdgeInsets.zero : const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainer,
                  borderRadius: isEInk
                      ? BorderRadius.circular(2)
                      : (dimensionConfig.cardRadius <= 0
                          ? BorderRadius.zero
                          : BorderRadius.circular(AppRadius.sm)),
                  border: isEInk
                      ? Border.all(color: const Color(0xFF1A1A18), width: 1.5)
                      : null,
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                    borderRadius: isEInk
                        ? BorderRadius.zero
                        : (dimensionConfig.cardRadius <= 0
                            ? BorderRadius.zero
                            : BorderRadius.circular(AppRadius.xs)),
                  ),
                  labelColor: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.onPrimary,
                  unselectedLabelColor: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant,
                  labelStyle: isEInk
                      ? GoogleFonts.robotoSlab(fontWeight: FontWeight.bold, fontSize: 13)
                      : (dimensionConfig.isMonospace
                          ? GoogleFonts.firaCode(fontWeight: FontWeight.bold, fontSize: 12)
                          : TextStyle(
                              fontFamily: dimensionConfig.isSerif ? 'serif' : null,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            )),
                  unselectedLabelStyle: isEInk
                      ? GoogleFonts.robotoSlab(fontWeight: FontWeight.w500, fontSize: 13)
                      : (dimensionConfig.isMonospace
                          ? GoogleFonts.firaCode(fontWeight: FontWeight.w500, fontSize: 12)
                          : TextStyle(
                              fontFamily: dimensionConfig.isSerif ? 'serif' : null,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            )),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: isEInk ? "Books" : (dimensionConfig.isMonospace ? "[BOOKS]" : "Books")),
                    Tab(text: isEInk ? "Collections" : (dimensionConfig.isMonospace ? "[COLLECTIONS]" : "Collections")),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildBooksTab(context, state, controller),
            const CollectionsTab(),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildBooksTab(BuildContext context, LibraryState state, LibraryController controller) {
    final theme = Theme.of(context);
    final dimensionConfig = context.watch<DimensionState>().config;
    if (state.isLoading) {
      return _buildLoadingSkeleton(context, state);
    }
    
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Error: ${state.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }
    
    if (state.books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories,
                size: 80, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            Text(
              'Your Library is Empty',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a folder to scan for supported books.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text("Select Folder"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final mode = await _promptStorageMode(context);
                if (mode != null && context.mounted) {
                  controller.pickAndScanDirectory(mode);
                }
              },
            )
          ],
        ),
      );
    }
    
    final displayedBooks = state.filteredBooks;
    final continueReadingBooks = state.searchQuery.isEmpty && state.selectedFormats.isEmpty
        ? state.books.where((b) => b.isInProgress).toList()
        : state.searchQuery.isEmpty && state.selectedFormats.isNotEmpty
            ? state.books.where((b) => b.isInProgress && state.selectedFormats.contains(b.format.toLowerCase())).toList()
            : <Book>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildSortFilterBar(context, state, controller),
        ),
        if (state.isGeneratingCovers)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Generating covers…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (continueReadingBooks.isNotEmpty && dimensionConfig.cardStyle != DimensionCardStyle.bentoShowcase)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Text(
                    dimensionConfig.isMonospace
                        ? "> BUFFER // ACTIVE_READS"
                        : (dimensionConfig.isSerif ? "Current Folios" : "Continue Reading"),
                    style: dimensionConfig.isMonospace
                        ? GoogleFonts.firaCode(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: theme.colorScheme.primary,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            fontFamily: dimensionConfig.isSerif ? 'serif' : null,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                  ),
                ),
                SizedBox(
                  height: 310,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: continueReadingBooks.length,
                    itemBuilder: (context, index) {
                      final book = continueReadingBooks[index];
                      return SizedBox(
                        width: 156,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: BookLargeCard(book: book),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Divider(height: 1, thickness: 1),
                ),
              ],
            ),
          ),
        _buildBooksSliver(context, state, controller, displayedBooks),
      ],
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context, LibraryState state) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        if (state.statusMessage != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.statusMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: 6,
            itemBuilder: (context, index) {
              return _buildBookCardSkeleton(theme, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookCardSkeleton(ThemeData theme, int index) {
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCoverShimmer(
            title: 'Skeleton Placeholder $index',
            height: 180,
            width: double.infinity,
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 90,
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 16,
                  width: 44,
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<SafStorageMode?> _promptStorageMode(BuildContext context) {
    final theme = Theme.of(context);
    return showDialog<SafStorageMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('Add Folder'),
          content: const Text(
            'Choose how to add books from this folder. '
            'Link keeps files in place and saves storage.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: () => Navigator.of(context).pop(SafStorageMode.imported),
                  child: const Text('Import'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(SafStorageMode.linked),
                  child: const Text('Link'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSortFilterBar(BuildContext context, LibraryState state, LibraryController controller) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;
    
    // Check if any filters are active
    final hasActiveFilters = state.selectedFormats.isNotEmpty ||
        state.filterNoAuthor ||
        state.filterNoCollection ||
        state.filterUnread;

    return Padding(
      padding: EdgeInsets.fromLTRB(isEInk ? 12 : 16, 8, isEInk ? 12 : 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: EdgeInsets.only(right: isEInk ? 6 : 0),
                child: Row(
                  children: [
                    // Sort Trigger
                    InkWell(
                      onTap: () => _showSortBottomSheet(context, state, controller),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isEInk ? 8 : 12, vertical: isEInk ? 5 : 6),
                        decoration: BoxDecoration(
                          color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                          border: Border.all(
                            color: isEInk
                                ? const Color(0xFF1A1A18)
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sort,
                              size: 16,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            ),
                            SizedBox(width: isEInk ? 4 : 6),
                            Text(
                              _getSortLabel(state.sortBy),
                              style: isEInk
                                  ? GoogleFonts.robotoSlab(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1A1A18),
                                      fontSize: 13,
                                    )
                                  : theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                            ),
                            SizedBox(width: isEInk ? 3 : 4),
                            Icon(
                              state.sortOrder == SortOrder.ascending 
                                  ? Icons.arrow_upward 
                                  : Icons.arrow_downward,
                              size: 12,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isEInk ? 6 : 8),
                    // Filter Trigger (Matches Photo Modal launcher)
                    InkWell(
                      onTap: () => _showFilterDialog(context, state, controller),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isEInk ? 8 : 12, vertical: isEInk ? 5 : 6),
                        decoration: BoxDecoration(
                          color: isEInk
                              ? const Color(0xFFEAE6DF)
                              : (hasActiveFilters 
                                  ? theme.colorScheme.primary.withValues(alpha: 0.15) 
                                  : theme.colorScheme.surfaceContainerLow),
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                          border: Border.all(
                            color: isEInk
                                ? const Color(0xFF1A1A18)
                                : (hasActiveFilters 
                                    ? theme.colorScheme.primary 
                                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_alt,
                              size: 16,
                              color: isEInk
                                  ? const Color(0xFF1A1A18)
                                  : (hasActiveFilters ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                            ),
                            SizedBox(width: isEInk ? 4 : 6),
                            Text(
                              'Filter',
                              style: isEInk
                                  ? GoogleFonts.robotoSlab(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1A1A18),
                                      fontSize: 13,
                                    )
                                  : theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: hasActiveFilters ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                    ),
                            ),
                            if (hasActiveFilters) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                                  shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                                  borderRadius: isEInk ? BorderRadius.circular(2) : null,
                                ),
                                child: Text(
                                  '${(state.selectedFormats.length + (state.filterNoAuthor ? 1 : 0) + (state.filterNoCollection ? 1 : 0) + (state.filterUnread ? 1 : 0))}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isEInk ? 6 : 8),
                    // View Trigger
                    InkWell(
                      onTap: () => _showViewModeBottomSheet(context, state, controller),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isEInk ? 8 : 12, vertical: isEInk ? 5 : 6),
                        decoration: BoxDecoration(
                          color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 20),
                          border: Border.all(
                            color: isEInk
                                ? const Color(0xFF1A1A18)
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              state.viewMode.icon,
                              size: 16,
                              color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                            ),
                            SizedBox(width: isEInk ? 4 : 6),
                            Text(
                              'View',
                              style: isEInk
                                  ? GoogleFonts.robotoSlab(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1A1A18),
                                      fontSize: 13,
                                    )
                                  : theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: isEInk ? 6 : 8),
          Text(
            '${state.filteredBooks.length} books',
            style: isEInk
                ? GoogleFonts.robotoSlab(
                    color: const Color(0xFF3D3C38),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )
                : theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context, LibraryState state, LibraryController controller) {
    // Get all book IDs that are in collections
    final collectionRepo = context.read<CollectionRepository>();
    final collections = collectionRepo.getAllCollections();
    final bookIdsInCollections = collections.expand((c) => c.bookIds).toSet();

    final currentTheme = context.read<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    // Local temp states
    Set<String> tempSelectedFormats = Set<String>.from(state.selectedFormats);
    bool tempFilterNoAuthor = state.filterNoAuthor;
    bool tempFilterNoCollection = state.filterNoCollection;
    bool tempFilterUnread = state.filterUnread;

    // The format options based on what extensions the reading app uses
    final formats = BookFormat.values
        .where((f) => f != BookFormat.unknown)
        .map((f) => f.formatString)
        .toList();

    showDialog(
      context: context,
      barrierColor: isEInk ? const Color(0x331A1A18) : null,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Dynamic calculation of matching book count
            final tempFilteredList = state.books.where((book) {
              if (tempSelectedFormats.isNotEmpty && !tempSelectedFormats.contains(book.format.toLowerCase())) {
                return false;
              }
              if (tempFilterNoAuthor && !(book.author.isEmpty || book.author.toLowerCase() == 'unknown author')) {
                return false;
              }
              if (tempFilterNoCollection && bookIdsInCollections.contains(book.id)) {
                return false;
              }
              if (tempFilterUnread && book.progress != 0.0) {
                return false;
              }
              return true;
            }).toList();
            final matchCount = tempFilteredList.length;

            // Color palette dynamically resolved from current theme to support Ferrous, Console, Sepia, and Light modes
            final dialogBgColor = theme.colorScheme.surface;
            final buttonUnselectedColor = theme.colorScheme.surfaceContainerHigh;
            final buttonSelectedColor = theme.colorScheme.primaryContainer;
            final actionTextColor = theme.colorScheme.primary;
            final onSurface = theme.colorScheme.onSurface;
            final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
            final onPrimaryContainer = theme.colorScheme.onPrimaryContainer;

            Widget formatButton(String label, String formatValue) {
              final isSelected = tempSelectedFormats.contains(formatValue);
              if (isEInk) {
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setModalState(() {
                      if (isSelected) {
                        tempSelectedFormats.remove(formatValue);
                      } else {
                        tempSelectedFormats.add(formatValue);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFFE0DCD3),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: const Color(0xFF1A1A18),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: GoogleFonts.robotoSlab(
                        color: isSelected ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }

              return InkWell(
                onTap: () {
                  setModalState(() {
                    if (isSelected) {
                      tempSelectedFormats.remove(formatValue);
                    } else {
                      tempSelectedFormats.add(formatValue);
                    }
                  });
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? buttonSelectedColor : buttonUnselectedColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: isSelected ? actionTextColor : onSurface.withValues(alpha: 0.08),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? onPrimaryContainer : onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }

            Widget otherFilterButton(String label, bool isSelected, VoidCallback onTap) {
              if (isEInk) {
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1A1A18) : const Color(0xFFE0DCD3),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: const Color(0xFF1A1A18),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.robotoSlab(
                        color: isSelected ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }

              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? buttonSelectedColor : buttonUnselectedColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: isSelected ? actionTextColor : onSurface.withValues(alpha: 0.08),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? onPrimaryContainer : onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              backgroundColor: isEInk ? Colors.transparent : dialogBgColor,
              elevation: isEInk ? 0 : 24,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: isEInk
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Container(
                decoration: isEInk
                    ? const BoxDecoration(
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
                          BorderSide(color: Color(0xFF1A1A18), width: 2.0),
                        ),
                      )
                    : null,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filter',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              color: const Color(0xFF1A1A18),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            )
                          : TextStyle(
                              color: onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                    ),
                    const SizedBox(height: 14),
                    Divider(
                      color: isEInk ? const Color(0xFF1A1A18) : onSurface.withValues(alpha: 0.12),
                      height: 1,
                      thickness: isEInk ? 1.5 : 1,
                    ),
                    const SizedBox(height: 16),
                    
                    // Formats Grid
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 3,
                      childAspectRatio: 2.3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: formats.map((f) => formatButton(f, f)).toList(),
                    ),

                    const SizedBox(height: 18),
                    Divider(
                      color: isEInk ? const Color(0xFF9E9A90) : onSurface.withValues(alpha: 0.12),
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 18),

                    // Other Filters (No author, No collection, Unread)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        otherFilterButton(
                          'No author',
                          tempFilterNoAuthor,
                          () => setModalState(() => tempFilterNoAuthor = !tempFilterNoAuthor),
                        ),
                        otherFilterButton(
                          'No collection',
                          tempFilterNoCollection,
                          () => setModalState(() => tempFilterNoCollection = !tempFilterNoCollection),
                        ),
                        otherFilterButton(
                          'Unread',
                          tempFilterUnread,
                          () => setModalState(() => tempFilterUnread = !tempFilterUnread),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    Divider(
                      color: isEInk ? const Color(0xFF9E9A90) : onSurface.withValues(alpha: 0.12),
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 16),

                    // Bottom Action Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$matchCount ${matchCount == 1 ? 'match' : 'matches'}',
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  color: const Color(0xFF1A1A18),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                )
                              : TextStyle(
                                  color: onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                        ),
                        Row(
                          children: [
                            if (isEInk) ...[
                              InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAE6DF),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
                                  ),
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.robotoSlab(
                                      color: const Color(0xFF1A1A18),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  controller.applyFilters(
                                    selectedFormats: tempSelectedFormats,
                                    filterNoAuthor: tempFilterNoAuthor,
                                    filterNoCollection: tempFilterNoCollection,
                                    filterUnread: tempFilterUnread,
                                    bookIdsInCollections: bookIdsInCollections,
                                  );
                                  Navigator.pop(context);
                                },
                                borderRadius: BorderRadius.circular(2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A18),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
                                  ),
                                  child: Text(
                                    'Apply',
                                    style: GoogleFonts.robotoSlab(
                                      color: const Color(0xFFEAE6DF),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                                ),
                                onPressed: () {
                                  controller.applyFilters(
                                    selectedFormats: tempSelectedFormats,
                                    filterNoAuthor: tempFilterNoAuthor,
                                    filterNoCollection: tempFilterNoCollection,
                                    filterUnread: tempFilterUnread,
                                    bookIdsInCollections: bookIdsInCollections,
                                  );
                                  Navigator.pop(context);
                                },
                                child: const Text('Apply'),
                              ),
                            ],
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSortBottomSheet(BuildContext context, LibraryState state, LibraryController controller) {
    final theme = Theme.of(context);
    final currentTheme = context.read<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    showModalBottomSheet(
      context: context,
      backgroundColor: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface,
      elevation: isEInk ? 0 : 4,
      showDragHandle: !isEInk,
      barrierColor: isEInk ? const Color(0x331A1A18) : null,
      clipBehavior: isEInk ? Clip.antiAlias : Clip.none,
      shape: isEInk
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFF1A1A18), width: 2.0),
            )
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.fromLTRB(isEInk ? 16 : 20, isEInk ? 12 : 4, isEInk ? 16 : 12, isEInk ? 12 : 8),
                    decoration: isEInk
                        ? const BoxDecoration(
                            color: Color(0xFFEAE6DF),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                            ),
                          )
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sort by',
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: const Color(0xFF1A1A18),
                                )
                              : theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                        ),
                        if (isEInk)
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final nextOrder = state.sortOrder == SortOrder.ascending
                                  ? SortOrder.descending
                                  : SortOrder.ascending;
                              controller.setSortOrder(nextOrder);
                              setModalState(() {});
                            },
                            borderRadius: BorderRadius.circular(2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0DCD3),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    state.sortOrder == SortOrder.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                                    size: 14,
                                    color: const Color(0xFF1A1A18),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    state.sortOrder == SortOrder.ascending ? 'Ascending' : 'Descending',
                                    style: GoogleFonts.robotoSlab(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: const Color(0xFF1A1A18),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          TextButton.icon(
                            icon: Icon(
                              state.sortOrder == SortOrder.ascending 
                                  ? Icons.arrow_upward 
                                  : Icons.arrow_downward,
                              size: 16,
                            ),
                            label: Text(
                              state.sortOrder == SortOrder.ascending ? 'Ascending' : 'Descending',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              final nextOrder = state.sortOrder == SortOrder.ascending
                                  ? SortOrder.descending
                                  : SortOrder.ascending;
                              controller.setSortOrder(nextOrder);
                              setModalState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  if (!isEInk) const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      physics: isEInk ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                      children: SortType.values.map((type) {
                        final isSelected = state.sortBy == type;
                        if (isEInk) {
                          return _KindleSheetOptionRow(
                            icon: _getSortIcon(type),
                            label: _getSortLabel(type),
                            isSelected: isSelected,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              controller.setSortBy(type);
                              Navigator.pop(ctx);
                            },
                          );
                        }
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? theme.colorScheme.primary.withValues(alpha: 0.15) 
                                  : theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _getSortIcon(type),
                              size: 18,
                              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            _getSortLabel(type),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            ),
                          ),
                          trailing: isSelected 
                              ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20) 
                              : null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            controller.setSortBy(type);
                            Navigator.pop(ctx);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(height: isEInk ? 8 : 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getSortLabel(SortType type) {
    switch (type) {
      case SortType.name:
        return 'Name';
      case SortType.fileName:
        return 'File Name';
      case SortType.fileFormat:
        return 'File Format';
      case SortType.fileSize:
        return 'File Size';
      case SortType.modifiedTime:
        return 'Modified Time';
      case SortType.dateRead:
        return 'Date Read';
    }
  }

  IconData _getSortIcon(SortType type) {
    switch (type) {
      case SortType.name:
        return Icons.title;
      case SortType.fileName:
        return Icons.description;
      case SortType.fileFormat:
        return Icons.extension;
      case SortType.fileSize:
        return Icons.insert_drive_file;
      case SortType.modifiedTime:
        return Icons.update;
      case SortType.dateRead:
        return Icons.history;
    }
  }

  void _showViewModeBottomSheet(BuildContext context, LibraryState state, LibraryController controller) {
    final theme = Theme.of(context);
    final currentTheme = context.read<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    showModalBottomSheet(
      context: context,
      backgroundColor: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface,
      elevation: isEInk ? 0 : 4,
      showDragHandle: !isEInk,
      barrierColor: isEInk ? const Color(0x331A1A18) : null,
      clipBehavior: isEInk ? Clip.antiAlias : Clip.none,
      shape: isEInk
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xFF1A1A18), width: 2.0),
            )
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(isEInk ? 16 : 20, isEInk ? 12 : 4, isEInk ? 16 : 12, isEInk ? 12 : 8),
                decoration: isEInk
                    ? const BoxDecoration(
                        color: Color(0xFFEAE6DF),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                        ),
                      )
                    : null,
                child: Row(
                  children: [
                    Text(
                      'View',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: const Color(0xFF1A1A18),
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                    ),
                  ],
                ),
              ),
              if (!isEInk) const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: isEInk ? const ClampingScrollPhysics() : null,
                  children: BookViewMode.values.map((mode) {
                    final isSelected = state.viewMode == mode;
                    if (isEInk) {
                      return _KindleSheetOptionRow(
                        icon: mode.icon,
                        label: mode.label,
                        isSelected: isSelected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.setViewMode(mode);
                          Navigator.pop(ctx);
                        },
                      );
                    }
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? theme.colorScheme.primary.withValues(alpha: 0.15) 
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          mode.icon,
                          size: 18,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        mode.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        ),
                      ),
                      trailing: isSelected 
                          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20) 
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.setViewMode(mode);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: isEInk ? 8 : 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBooksSliver(BuildContext context, LibraryState state, LibraryController controller, List<Book> displayedBooks) {
    final dimensionState = context.watch<DimensionState>();
    final config = dimensionState.config;

    // Specialized dimension presentation when in default largeIcons mode
    if (state.viewMode == BookViewMode.largeIcons) {
      if (config.cardStyle == DimensionCardStyle.terminalTelemetry) {
        return DimensionBookView(
          books: displayedBooks,
          config: config,
          splitPendingBook: state.splitPendingBook,
          onTap: (book) => BookItemActionHandler.handleTap(context, book, controller),
          onLongPress: (book) => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        );
      }
      if (config.cardStyle == DimensionCardStyle.bentoShowcase) {
        return DimensionBookView(
          books: displayedBooks,
          config: config,
          splitPendingBook: state.splitPendingBook,
          onTap: (book) => BookItemActionHandler.handleTap(context, book, controller),
          onLongPress: (book) => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        );
      }
      if (config.cardStyle == DimensionCardStyle.indexSpines) {
        return DimensionBookView(
          books: displayedBooks,
          config: config,
          splitPendingBook: state.splitPendingBook,
          onTap: (book) => BookItemActionHandler.handleTap(context, book, controller),
          onLongPress: (book) => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        );
      }
      if (config.cardStyle == DimensionCardStyle.compactList) {
        return DimensionBookView(
          books: displayedBooks,
          config: config,
          splitPendingBook: state.splitPendingBook,
          onTap: (book) => BookItemActionHandler.handleTap(context, book, controller),
          onLongPress: (book) => BookItemActionHandler.showBookOptionsMenu(context, book, controller),
        );
      }
    }

    switch (state.viewMode) {
      case BookViewMode.extraLargeIcons:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: 395,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookExtraLargeCard(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
      case BookViewMode.largeIcons:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: displayedBooks.length,
            itemBuilder: (context, index) {
              return BookLargeCard(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              );
            },
          ),
        );
      case BookViewMode.mediumIcons:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 225,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookMediumCard(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
      case BookViewMode.smallIcons:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 95,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 125,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookSmallCard(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
      case BookViewMode.list:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookListItem(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
      case BookViewMode.details:
        return SliverMainAxisGroup(
          slivers: [
            const SliverToBoxAdapter(child: BookDetailsHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => BookDetailsItem(
                    key: ValueKey(displayedBooks[index].id),
                    book: displayedBooks[index],
                  ),
                  childCount: displayedBooks.length,
                ),
              ),
            ),
          ],
        );
      case BookViewMode.tiles:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 80,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookTileItem(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
      case BookViewMode.content:
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => BookContentItem(
                key: ValueKey(displayedBooks[index].id),
                book: displayedBooks[index],
              ),
              childCount: displayedBooks.length,
            ),
          ),
        );
    }
  }
}

/// Instantaneous (0ms) inverting ledger option row for Kindle Carta sheets.
class _KindleSheetOptionRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _KindleSheetOptionRow({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_KindleSheetOptionRow> createState() => _KindleSheetOptionRowState();
}

class _KindleSheetOptionRowState extends State<_KindleSheetOptionRow> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final invert = _isPressed;
    final rowBg = invert
        ? const Color(0xFF1A1A18)
        : (widget.isSelected ? const Color(0xFFE0DCD3) : Colors.transparent);
    final fgColor = invert ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);
    final iconBoxBg = invert ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF);
    final iconBoxBorder = invert ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(
              left: BorderSide(
                color: widget.isSelected ? const Color(0xFF1A1A18) : Colors.transparent,
                width: 4.0,
              ),
              bottom: const BorderSide(color: Color(0xFF9E9A90), width: 1.0),
            ),
          ),
          child: Row(
            children: [
              // Sharp 2px square ink frame behind icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBoxBg,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: iconBoxBorder, width: 1.0),
                ),
                child: Icon(widget.icon, size: 18, color: fgColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.robotoSlab(
                    fontSize: 14.5,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ),
              if (widget.isSelected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: invert ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: invert ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 15,
                    color: invert ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
