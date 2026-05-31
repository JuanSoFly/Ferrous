import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/features/library/library_state.dart';
import 'package:reader_app/features/library/widgets/book_cover_shimmer.dart';

import 'package:google_fonts/google_fonts.dart';

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
    final coverPath = widget.book.coverPath;
    final fileExists = coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    if (fileExists && !_loadFailed) {
      return SizedBox(
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
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeIn,
              onEnd: () {
                if (_imageLoaded && mounted) {
                  setState(() {
                    _showShimmer = false;
                  });
                }
              },
              child: Image.file(
                File(coverPath),
                fit: widget.fit,
                cacheHeight:
                    widget.height != null ? (widget.height! * 2).toInt() : null,
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
                  return _buildPlaceholder(context);
                },
              ),
            ),
          ],
        ),
      );
    }

    if (widget.isGenerating) {
      return BookCoverShimmer(
        title: widget.book.title,
        format: widget.book.format,
        height: widget.height,
        width: widget.width,
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colors = _getColorGradient(widget.book.title);
    final displayHeight = widget.height ?? 200;

    final titleFontSize = (displayHeight * 0.08).clamp(11.0, 16.0);
    final authorFontSize = (displayHeight * 0.06).clamp(9.0, 12.0);
    final isCompact = displayHeight < 100;

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
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.1,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            widget.book.author,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: authorFontSize,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
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

    return BookCover(
      book: book,
      height: 60,
      width: 40,
      fit: BoxFit.cover,
      isGenerating: isGenerating,
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

    return BookCover(
      book: book,
      height: 200,
      width: double.infinity,
      fit: BoxFit.cover,
      isGenerating: isGenerating,
    );
  }
}
