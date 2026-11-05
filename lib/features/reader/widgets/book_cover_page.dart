import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/book_textures.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/library/widgets/book_cover.dart';

/// Full-page or in-flow authentic book cover presentation.
///
/// Displayed as the first page (Page 0) in paged readers and at the head
/// of continuous readers so the book cover is naturally shown when the book
/// is opened for the first time.
class BookCoverPage extends StatelessWidget {
  final Book book;
  final bool isContinuous;
  final VoidCallback? onTurnPage;
  final VoidCallback? onToggleChrome;

  const BookCoverPage({
    super.key,
    required this.book,
    this.isContinuous = false,
    this.onTurnPage,
    this.onToggleChrome,
  });

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ReaderThemeRepository>();
    final themeConfig = themeRepo.config;
    final textureInfo = BookTextures.getById(themeConfig.paperTexture);
    final effectiveTextColor = themeConfig.paperTexture != BookTextures.none
        ? textureInfo.textColor
        : Theme.of(context).colorScheme.onSurface;

    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;

    if (isContinuous) {
      return _buildContinuousCover(context, size, themeConfig.fontFamily, effectiveTextColor);
    }

    return _buildPagedCover(context, size, themeConfig.fontFamily, effectiveTextColor);
  }

  Widget _buildPagedCover(
    BuildContext context,
    Size size,
    String fontFamily,
    Color? textColor,
  ) {
    // Elegant proportional cover sizing: up to 72% width and 65% height
    final maxCoverWidth = math.min(size.width * 0.72, 340.0);
    final maxCoverHeight = math.min(size.height * 0.62, 500.0);

    // Compute width/height maintaining 2:3 book aspect ratio
    double coverWidth = maxCoverWidth;
    double coverHeight = coverWidth * 1.5;
    if (coverHeight > maxCoverHeight) {
      coverHeight = maxCoverHeight;
      coverWidth = coverHeight / 1.5;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleChrome,
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 3D physical book presentation with spine depth and shadow
                _buildPhysicalBookCard(coverWidth, coverHeight),
                const SizedBox(height: 24),

                // Title
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: size.width * 0.85),
                  child: Text(
                    book.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _getGoogleStyle(
                      fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                ),

                if (book.author.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: size.width * 0.8),
                    child: Text(
                      book.author,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _getGoogleStyle(
                        fontFamily,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: textColor?.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Turn page hint
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Turn page to start reading',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.4,
                        color: textColor?.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 11,
                      color: textColor?.withValues(alpha: 0.5),
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

  Widget _buildContinuousCover(
    BuildContext context,
    Size size,
    String fontFamily,
    Color? textColor,
  ) {
    final coverWidth = math.min(size.width * 0.58, 240.0);
    final coverHeight = coverWidth * 1.5;

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 40.0, left: 16.0, right: 16.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPhysicalBookCard(coverWidth, coverHeight),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size.width * 0.85),
              child: Text(
                book.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _getGoogleStyle(
                  fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            if (book.author.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                book.author,
                textAlign: TextAlign.center,
                style: _getGoogleStyle(
                  fontFamily,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: textColor?.withValues(alpha: 0.75),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              width: 60,
              height: 1.5,
              decoration: BoxDecoration(
                color: textColor?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhysicalBookCard(double width, double height) {
    final hasValidCoverFile = book.coverPath != null &&
        book.coverPath!.isNotEmpty &&
        File(book.coverPath!).existsSync();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        boxShadow: [
          // Ambient soft drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(4, 10),
          ),
          // Sharp ground shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover artwork
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              bottomLeft: Radius.circular(3),
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: hasValidCoverFile
                ? Image.file(
                    File(book.coverPath!),
                    fit: BoxFit.cover,
                    width: width,
                    height: height,
                  )
                : BookCover(
                    book: book,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                  ),
          ),

          // Left physical book spine crease shadow
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 16,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.2, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Right page edge sheen
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _getGoogleStyle(
    String fontFamily, {
    required double fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    Color? color,
    double? height,
  }) {
    try {
      return GoogleFonts.getFont(
        fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: height,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: height,
      );
    }
  }
}
