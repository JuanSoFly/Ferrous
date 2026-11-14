import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/features/library/library_state.dart';
import 'package:ferrous/features/library/widgets/book_cover_shimmer.dart';
import 'package:ferrous/core/constants/e_ink_tokens.dart';
import 'package:ferrous/features/settings/app_themes.dart';

/// Shared widget for displaying book covers consistently across the app.
///
/// Shows an animated shimmer skeleton while the cover image loads from disk,
/// then fades in the actual cover with a smooth 200ms transition.
class BookCover extends StatefulWidget {
  final Book book;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool isGenerating;

  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.isGenerating = false,
  });

  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  bool _imageLoaded = false;
  bool _showShimmer = true;
  bool _loadFailed = false;

  @override
  void didUpdateWidget(covariant BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset loading state when the cover path changes (e.g., after generation)
    if (oldWidget.book.coverPath != widget.book.coverPath) {
      _imageLoaded = false;
      _showShimmer = true;
      _loadFailed = false;
    }
  }

  static final List<List<Color>> _presetGradients = [
    [const Color(0xFFE0623A), const Color(0xFF8C1D18)], // Rust/Dark Red
    [const Color(0xFF2B5C8F), const Color(0xFF132F50)], // Blue/Navy
    [const Color(0xFF6B4A8F), const Color(0xFF381A5C)], // Purple/Indigo
    [const Color(0xFF3B8253), const Color(0xFF144D2B)], // Green/Emerald
    [const Color(0xFFD68A3E), const Color(0xFF8F4D0E)], // Amber/Warm Orange
    [const Color(0xFFD14D72), const Color(0xFF70132B)], // Crimson/Wine
  ];

  List<Color> _getColorGradient(String title) {
    if (title.isEmpty) return _presetGradients[0];
    final hash = title.hashCode.abs();
    return _presetGradients[hash % _presetGradients.length];
  }

  @override
  Widget build(BuildContext context) {
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    final coverPath = widget.book.coverPath;
    final hasCoverPath = coverPath != null && coverPath.isNotEmpty;

    Widget content;
    if (hasCoverPath && !_loadFailed) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      int? targetCacheWidth;
      int? targetCacheHeight;
      if (widget.height != null && widget.height!.isFinite && widget.height! > 0) {
        targetCacheHeight = (widget.height! * dpr).round();
      }
      if (widget.width != null && widget.width!.isFinite && widget.width! > 0) {
        targetCacheWidth = (widget.width! * dpr).round();
      } else if (targetCacheHeight != null) {
        // Standard book cover aspect ratio (~1:1.45)
        targetCacheWidth = (targetCacheHeight * 0.75).round();
      }

      final imageWidget = Image.file(
        File(coverPath),
        fit: widget.fit,
        cacheWidth: targetCacheWidth,
        cacheHeight: targetCacheHeight,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            if (!_imageLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _imageLoaded = true;
                    _showShimmer = false;
                  });
                }
              });
            }
            return child;
          }
          if (frame != null) {
            if (!_imageLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _imageLoaded = true);
                }
              });
            }
            return child;
          }
          // Still loading — hidden behind shimmer
          return const SizedBox.shrink();
        },
        errorBuilder: (context, error, stackTrace) {
          if (!_loadFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _loadFailed = true;
                  _showShimmer = false;
                });
              }
            });
          }
          return _buildPlaceholder(context, isEInk: isEInk);
        },
      );

      final filteredImage = isEInk
          ? RepaintBoundary(
              child: ColorFiltered(
                colorFilter: EInkTokens.coverFilter,
                child: imageWidget,
              ),
            )
          : imageWidget;

      content = SizedBox(
        height: widget.height,
        width: widget.width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shimmer skeleton — visible while image loads
            if (_showShimmer)
              BookCoverShimmer(
                title: widget.book.title,
                format: widget.book.format,
                height: widget.height,
                width: widget.width,
              ),
            // Image fades in on top when first frame is available
            AnimatedOpacity(
              opacity: _imageLoaded ? 1.0 : 0.0,
              duration: isEInk ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeIn,
              onEnd: () {
                if (_imageLoaded && mounted) {
                  setState(() {
                    _showShimmer = false;
                  });
                }
              },
              child: filteredImage,
            ),
          ],
        ),
      );
    } else if (widget.isGenerating) {
      content = BookCoverShimmer(
        title: widget.book.title,
        format: widget.book.format,
        height: widget.height,
        width: widget.width,
      );
    } else {
      content = _buildPlaceholder(context, isEInk: isEInk);
    }

    if (isEInk) {
      return Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
          borderRadius: BorderRadius.circular(0),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholder(BuildContext context, {bool isEInk = false}) {
    final theme = Theme.of(context);
    final colors = _getColorGradient(widget.book.title);
    final displayHeight = widget.height ?? 200;

    final titleFontSize = (displayHeight * 0.08).clamp(11.0, 16.0);
    final authorFontSize = (displayHeight * 0.06).clamp(9.0, 12.0);
    final isCompact = displayHeight < 100;

    if (isEInk) {
      return Container(
        height: widget.height,
        width: widget.width,
        color: const Color(0xFFE0DCD3),
        padding: const EdgeInsets.all(8),
        child: isCompact
            ? Center(
                child: Icon(
                  _getFormatIcon(widget.book.format),
                  size: displayHeight * 0.4,
                  color: const Color(0xFF1A1A18),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF1A1A18), width: 1.0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        widget.book.format.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF1A1A18),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.book.title,
                    style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                      color: const Color(0xFF1A1A18),
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.book.author,
                    style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                      color: const Color(0xFF3D3C38),
                      fontSize: authorFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      );
    }

    if (isCompact) {
      return Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            _getFormatIcon(widget.book.format),
            size: displayHeight * 0.4,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.book.format.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            widget.book.title,
            style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
              color: Colors.white,
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.1,
              shadows: const [
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            widget.book.author,
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: const Color(0xD9FFFFFF),
              fontSize: authorFontSize,
              fontWeight: FontWeight.w500,
              shadows: const [
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static IconData _getFormatIcon(String format) {
    switch (format.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.auto_stories;
      case 'cbz':
      case 'cbr':
        return Icons.collections_bookmark;
      case 'docx':
        return Icons.description;
      case 'mobi':
        return Icons.menu_book;
      default:
        return Icons.book;
    }
  }
}

/// Small variant for list items (40x60)
class BookCoverSmall extends StatelessWidget {
  final Book book;

  const BookCoverSmall({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    bool isGenerating = false;
    try {
      isGenerating = context.select<LibraryState, bool>((s) => s.isGeneratingCovers);
    } catch (_) {}

    return RepaintBoundary(
      child: BookCover(
        book: book,
        height: 60,
        width: 40,
        fit: BoxFit.cover,
        isGenerating: isGenerating,
      ),
    );
  }
}

/// Default card variant for library grid (200 height, full width)
class BookCoverCard extends StatelessWidget {
  final Book book;

  const BookCoverCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    bool isGenerating = false;
    try {
      isGenerating = context.select<LibraryState, bool>((s) => s.isGeneratingCovers);
    } catch (_) {}

    return RepaintBoundary(
      child: BookCover(
        book: book,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        isGenerating: isGenerating,
      ),
    );
  }
}
