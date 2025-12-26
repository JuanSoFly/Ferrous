import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/data/models/book.dart';

/// Shared widget for displaying book covers consistently across the app.
/// 
/// Handles cover loading from file path with proper error fallback to placeholder.
/// Used in library_screen, collection_detail_screen, and annotations_hub_screen.
class BookCover extends StatelessWidget {
  final Book book;
  final double? height;
  final double? width;
  final BoxFit fit;

  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    
    if (coverPath != null && coverPath.isNotEmpty) {
      return SizedBox(
        height: height,
        width: width,
        child: Image.file(
          File(coverPath),
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
          cacheHeight: height != null ? (height! * 2).toInt() : null,
        ),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          _getFormatIcon(book.format),
          size: (height ?? 200) * 0.24,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140),
        ),
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
    return BookCover(
      book: book,
      height: 60,
      width: 40,
      fit: BoxFit.cover,
    );
  }
}

/// Default card variant for library grid (200 height, full width)
class BookCoverCard extends StatelessWidget {
  final Book book;
  
  const BookCoverCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return BookCover(
      book: book,
      height: 200,
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }
}
