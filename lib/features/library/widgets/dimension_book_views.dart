import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';
import 'package:reader_app/features/settings/app_themes.dart';

typedef BookCallback = void Function(Book book);

/// Dispatches the appropriate layout presentation based on DimensionCardStyle.
class DimensionBookView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const DimensionBookView({
    super.key,
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    switch (config.cardStyle) {
      case DimensionCardStyle.bentoShowcase:
        return _BentoShowcaseView(
          books: books,
          config: config,
          splitPendingBook: splitPendingBook,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      case DimensionCardStyle.terminalTelemetry:
        return _TerminalTelemetryView(
          books: books,
          config: config,
          splitPendingBook: splitPendingBook,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      case DimensionCardStyle.indexSpines:
        return _IndexSpinesView(
          books: books,
          config: config,
          splitPendingBook: splitPendingBook,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      case DimensionCardStyle.compactList:
        return _CompactListView(
          books: books,
          config: config,
          splitPendingBook: splitPendingBook,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      case DimensionCardStyle.masonryGrid:
        return _ModernMasonryGridView(
          books: books,
          config: config,
          splitPendingBook: splitPendingBook,
          onTap: onTap,
          onLongPress: onLongPress,
        );
    }
  }
}

// ==========================================
// 1. MODERN MASONRY GRID (Default Modernist)
// ==========================================
class _ModernMasonryGridView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const _ModernMasonryGridView({
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 40),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          final isPending = splitPendingBook?.id == book.id;
          return _StandardBookCard(
            book: book,
            config: config,
            isPending: isPending,
            onTap: () => onTap(book),
            onLongPress: () => onLongPress(book),
          );
        },
      ),
    );
  }
}

// ==========================================
// 2. BENTO SHOWCASE (Floating Island Mode)
// ==========================================
class _BentoShowcaseView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const _BentoShowcaseView({
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final inProgressBooks = books.where((b) => b.progress > 0).toList();
    final heroBook = inProgressBooks.isNotEmpty ? inProgressBooks.first : (books.isNotEmpty ? books.first : null);
    final remainingBooks = heroBook != null ? books.where((b) => b.id != heroBook.id).toList() : books;

    return SliverMainAxisGroup(
      slivers: [
        if (heroBook != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _BentoHeroCard(
                book: heroBook,
                config: config,
                onTap: () => onTap(heroBook),
                onLongPress: () => onLongPress(heroBook),
              ),
            ),
          ),
        if (remainingBooks.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final book = remainingBooks[index];
                  final isPending = splitPendingBook?.id == book.id;
                  return _BentoGridCard(
                    book: book,
                    config: config,
                    isPending: isPending,
                    onTap: () => onTap(book),
                    onLongPress: () => onLongPress(book),
                  );
                },
                childCount: remainingBooks.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _BentoHeroCard extends StatelessWidget {
  final Book book;
  final DimensionConfig config;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BentoHeroCard({
    required this.book,
    required this.config,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              primary.withValues(alpha: 0.18),
              theme.colorScheme.surfaceContainerHigh,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: primary.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 110,
                height: double.infinity,
                child: BookCoverCard(book: book),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'CURRENT READ',
                      style: TextStyle(
                        color: primary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${(book.progress * 100).toInt()}% completed",
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: theme.colorScheme.onPrimary, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              'Resume',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: book.progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: primary.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
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

class _BentoGridCard extends StatelessWidget {
  final Book book;
  final DimensionConfig config;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BentoGridCard({
    required this.book,
    required this.config,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPending ? primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
            width: isPending ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCoverCard(book: book),
                  if (book.progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: book.progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(primary),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        book.format.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 10,
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

// ==========================================
// 3. TERMINAL TELEMETRY VIEW (Cyber Terminal)
// ==========================================
class _TerminalTelemetryView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const _TerminalTelemetryView({
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final book = books[index];
            final isPending = splitPendingBook?.id == book.id;
            return _TerminalTelemetryRow(
              index: index,
              book: book,
              config: config,
              isPending: isPending,
              onTap: () => onTap(book),
              onLongPress: () => onLongPress(book),
            );
          },
          childCount: books.length,
        ),
      ),
    );
  }
}

class _TerminalTelemetryRow extends StatelessWidget {
  final int index;
  final Book book;
  final DimensionConfig config;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TerminalTelemetryRow({
    required this.index,
    required this.book,
    required this.config,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
  });

  String _formatAsciiMeter(double progress) {
    const totalBars = 8;
    final filledBars = (progress * totalBars).round().clamp(0, totalBars);
    final emptyBars = totalBars - filledBars;
    return '[${'■' * filledBars}${'□' * emptyBars} ${(progress * 100).toInt()}%]';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final addrHex = (index + 1).toRadixString(16).padLeft(2, '0').toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.zero,
        child: Container(
          decoration: BoxDecoration(
            color: isPending ? primary.withValues(alpha: 0.12) : theme.colorScheme.surface,
            border: Border.all(
              color: isPending ? primary : primary.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '0x$addrHex',
                    style: GoogleFonts.firaCode(
                      color: primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    color: primary.withValues(alpha: 0.18),
                    child: Text(
                      book.format.toUpperCase(),
                      style: GoogleFonts.firaCode(
                        color: primary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                        color: onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'AUTHOR: ${book.author.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                        color: onSurface.withValues(alpha: 0.55),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Text(
                    _formatAsciiMeter(book.progress),
                    style: GoogleFonts.firaCode(
                      color: primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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

// ==========================================
// 4. INDEX SPINES VIEW (Athenaeum Mode)
// ==========================================
class _IndexSpinesView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const _IndexSpinesView({
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final book = books[index];
            final isPending = splitPendingBook?.id == book.id;
            return _IndexCatalogCard(
              book: book,
              config: config,
              isPending: isPending,
              onTap: () => onTap(book),
              onLongPress: () => onLongPress(book),
            );
          },
          childCount: books.length,
        ),
      ),
    );
  }
}

class _IndexCatalogCard extends StatelessWidget {
  final Book book;
  final DimensionConfig config;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _IndexCatalogCard({
    required this.book,
    required this.config,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPending ? primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: isPending ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Book spine simulator
              Container(
                width: 5,
                height: 64,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: BookCoverCard(book: book),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'serif',
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: primary.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      book.format.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        color: primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.progress > 0 ? '${(book.progress * 100).toInt()}%' : 'Unread',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primary,
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

// ==========================================
// 5. COMPACT LIST VIEW (Compact Slate Mode)
// ==========================================
class _CompactListView extends StatelessWidget {
  final List<Book> books;
  final DimensionConfig config;
  final Book? splitPendingBook;
  final BookCallback onTap;
  final BookCallback onLongPress;

  const _CompactListView({
    required this.books,
    required this.config,
    this.splitPendingBook,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final book = books[index];
            final isPending = splitPendingBook?.id == book.id;
            return _CompactBookRow(
              book: book,
              config: config,
              isPending: isPending,
              onTap: () => onTap(book),
              onLongPress: () => onLongPress(book),
            );
          },
          childCount: books.length,
        ),
      ),
    );
  }
}

class _CompactBookRow extends StatelessWidget {
  final Book book;
  final DimensionConfig config;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CompactBookRow({
    required this.book,
    required this.config,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;
    final isCompactSlate = config.dimension == AppDimension.compactSlate;
    final effectiveRadius = (isEInk || isCompactSlate) ? 2.0 : 4.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(effectiveRadius),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isEInk
                ? (isPending ? const Color(0xFFD5D0C5) : const Color(0xFFE0DCD3))
                : (isPending ? primary.withValues(alpha: 0.12) : theme.colorScheme.surface),
            borderRadius: BorderRadius.circular(effectiveRadius),
            border: Border.all(
              color: isEInk
                  ? (isPending ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90))
                  : (isPending ? primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.25)),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isEInk ? 2 : 2),
                child: SizedBox(
                  width: 26,
                  height: 38,
                  child: BookCoverCard(book: book),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isEInk
                      ? GoogleFonts.robotoSlab(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A18),
                        )
                      : const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isEInk ? Colors.transparent : primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(isEInk ? 2 : 3),
                  border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                ),
                child: Text(
                  book.format.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: isEInk ? 0.5 : 0,
                    color: isEInk ? const Color(0xFF1A1A18) : primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                child: Text(
                  book.progress > 0 ? '${(book.progress * 100).toInt()}%' : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isEInk ? FontWeight.w600 : FontWeight.w500,
                    color: isEInk
                        ? const Color(0xFF1A1A18)
                        : (book.progress > 0 ? primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// STANDARD CARD FALLBACK
// ==========================================
class _StandardBookCard extends StatelessWidget {
  final Book book;
  final DimensionConfig config;
  final bool isPending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StandardBookCard({
    required this.book,
    required this.config,
    required this.isPending,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;
    final effectiveRadius = isEInk ? 2.0 : config.cardRadius;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isEInk ? const Color(0xFFE0DCD3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(effectiveRadius),
        side: isEInk
            ? BorderSide(color: isPending ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90), width: 1.0)
            : (isPending
                ? BorderSide(color: primary, width: 2)
                : BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(effectiveRadius > 1 ? effectiveRadius - 1 : 0)),
                  child: BookCoverCard(book: book),
                ),
                if (book.progress > 0)
                  Container(
                    height: isEInk ? 3 : 4,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isEInk ? const Color(0xFFEAE6DF) : primary.withValues(alpha: 0.2),
                      border: isEInk ? const Border(top: BorderSide(color: Color(0xFF1A1A18), width: 1.0)) : null,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: book.progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: isEInk ? BorderRadius.zero : const BorderRadius.horizontal(right: Radius.circular(2)),
                            color: isEInk ? const Color(0xFF1A1A18) : primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: isEInk
                        ? GoogleFonts.robotoSlab(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A18),
                          )
                        : const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isEInk ? Colors.transparent : primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(isEInk ? 2 : 4),
                          border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                        ),
                        child: Text(
                          book.format.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: isEInk ? 0.5 : 0,
                            color: isEInk ? const Color(0xFF1A1A18) : primary,
                          ),
                        ),
                      ),
                      if (book.progress > 0)
                        Text(
                          "${(book.progress * 100).toInt()}% read",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isEInk ? FontWeight.w600 : FontWeight.normal,
                            color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
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
