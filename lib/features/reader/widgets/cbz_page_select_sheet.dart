import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/e_ink_tokens.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/dimension_controller.dart';
import '../controllers/cbz_page_controller.dart';
import '../services/cbz_thumbnail_service.dart';

/// Helper to detect if Kindle Carta E-Ink Paper mode is active.
bool isEInkActive(BuildContext context) {
  try {
    final theme = Provider.of<AppTheme>(context, listen: false);
    if (theme == AppTheme.eInk) return true;
  } catch (_) {}
  try {
    final dimState = Provider.of<DimensionState>(context, listen: false);
    if (dimState.dimension == AppDimension.compactSlate) return true;
  } catch (_) {}
  final themeData = Theme.of(context);
  return themeData.scaffoldBackgroundColor == const Color(0xFFEAE6DF) &&
      themeData.colorScheme.primary == const Color(0xFF1A1A18);
}

/// Opens the dedicated Page Select Sheet / Modal for CBZ/CBR reader.
Future<void> showCbzPageSelectSheet(
  BuildContext context, {
  required CbzPageController pageController,
}) {
  final eInk = isEInkActive(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: !eInk,
    barrierColor: eInk ? const Color(0x331A1A18) : Colors.black54,
    backgroundColor: eInk ? const Color(0xFFEAE6DF) : Theme.of(context).colorScheme.surface,
    elevation: 0,
    shape: eInk
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
            side: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
          )
        : const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
    builder: (ctx) => CbzPageSelectSheet(
      pageController: pageController,
      isEInk: eInk,
    ),
  );
}

/// Dedicated Page Select Sheet / Modal with Direct Page Number Input and
/// Visual Page Thumbnail Grid.
class CbzPageSelectSheet extends StatefulWidget {
  final CbzPageController pageController;
  final bool isEInk;

  const CbzPageSelectSheet({
    super.key,
    required this.pageController,
    required this.isEInk,
  });

  @override
  State<CbzPageSelectSheet> createState() => _CbzPageSelectSheetState();
}

class _CbzPageSelectSheetState extends State<CbzPageSelectSheet> {
  late final TextEditingController _inputController;
  late final ScrollController _gridScrollController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: '${widget.pageController.pageIndex + 1}');
    _gridScrollController = ScrollController();

    // Auto-scroll to current page after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentPage();
    });
  }

  void _scrollToCurrentPage() {
    if (!mounted || !_gridScrollController.hasClients) return;
    final total = widget.pageController.pageCount;
    final current = widget.pageController.pageIndex;
    if (total <= 0 || current <= 0) return;

    final mediaWidth = MediaQuery.sizeOf(context).width;
    const maxExtent = 120.0;
    const spacing = 10.0;
    final columns = ((mediaWidth - 24) / (maxExtent + spacing)).floor().clamp(1, 10);
    final row = current ~/ columns;
    const estimatedItemHeight = (maxExtent / 0.70) + spacing;
    final targetOffset = (row * estimatedItemHeight) - (estimatedItemHeight * 0.4);
    final maxScroll = _gridScrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);

    if (widget.isEInk) {
      _gridScrollController.jumpTo(clamped);
    } else {
      _gridScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _gridScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitPageInput() {
    final text = _inputController.text.trim();
    final pageNum = int.tryParse(text);
    if (pageNum == null) return;

    final total = widget.pageController.pageCount;
    final targetIndex = (pageNum - 1).clamp(0, total - 1);
    widget.pageController.jumpToPage(targetIndex);
    Navigator.of(context).pop();
  }

  void _selectPage(int index) {
    widget.pageController.jumpToPage(index);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEInk = widget.isEInk;
    final totalPages = widget.pageController.pageCount;
    final currentPage = widget.pageController.pageIndex;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // Tokens
    final containerBg = isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surface;
    final textInk = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface;
    final dividerColor = isEInk ? const Color(0xFF9E9A90) : theme.colorScheme.outlineVariant;
    final recessedBg = isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surfaceContainerHigh;

    return Container(
      color: containerBg,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Row
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 8, top: 12, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'Jump to Page',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textInk,
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: textInk,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: dividerColor),

              // 2. Direct Page Number Input Bar
              Container(
                color: recessedBg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      'Go to page',
                      style: isEInk
                          ? GoogleFonts.robotoSlab(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textInk,
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      height: 38,
                      child: TextField(
                        controller: _inputController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        onSubmitted: (_) => _submitPageInput(),
                        style: isEInk
                            ? GoogleFonts.robotoMono(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: textInk,
                              )
                            : theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          filled: true,
                          fillColor: isEInk ? const Color(0xFFE0DCD3) : theme.colorScheme.surface,
                          border: isEInk
                              ? const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(2)),
                                  borderSide: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                                )
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: theme.colorScheme.outline),
                                ),
                          enabledBorder: isEInk
                              ? const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(2)),
                                  borderSide: BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                                )
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                                ),
                          focusedBorder: isEInk
                              ? const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(2)),
                                  borderSide: BorderSide(color: Color(0xFF1A1A18), width: 2.0),
                                )
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.0),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '/ $totalPages',
                      style: isEInk
                          ? GoogleFonts.robotoMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3D3C38),
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                    const Spacer(),
                    _GoButton(
                      isEInk: isEInk,
                      onPressed: _submitPageInput,
                    ),
                  ],
                ),
              ),

              Divider(height: 1, thickness: 1, color: dividerColor),

              // 3. Virtualized Page Thumbnail Grid
              Expanded(
                child: totalPages == 0
                    ? Center(
                        child: Text(
                          'No pages found',
                          style: TextStyle(color: textInk),
                        ),
                      )
                    : GridView.builder(
                        controller: _gridScrollController,
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          childAspectRatio: 0.70,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: totalPages,
                        itemBuilder: (context, index) {
                          final isCurrent = index == currentPage;
                          return _PageThumbnailTile(
                            pageIndex: index,
                            isCurrent: isCurrent,
                            isEInk: isEInk,
                            archivePath: widget.pageController.archivePath,
                            onTap: () => _selectPage(index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Go button with mechanical 0ms inversion for E-Ink and standard styled button for other themes.
class _GoButton extends StatefulWidget {
  final bool isEInk;
  final VoidCallback onPressed;

  const _GoButton({
    required this.isEInk,
    required this.onPressed,
  });

  @override
  State<_GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<_GoButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isEInk) {
      final bg = _isPressed ? const Color(0xFFEAE6DF) : const Color(0xFF1A1A18);
      final fg = _isPressed ? const Color(0xFF1A1A18) : const Color(0xFFEAE6DF);

      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(2.0),
            border: Border.all(color: const Color(0xFF1A1A18), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            'Go',
            style: GoogleFonts.robotoMono(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return FilledButton(
      onPressed: widget.onPressed,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
        minimumSize: const Size(0, 38),
      ),
      child: const Text('Go'),
    );
  }
}

/// A single comic page thumbnail card in the visual grid.
class _PageThumbnailTile extends StatefulWidget {
  final int pageIndex;
  final bool isCurrent;
  final bool isEInk;
  final String? archivePath;
  final VoidCallback onTap;

  const _PageThumbnailTile({
    required this.pageIndex,
    required this.isCurrent,
    required this.isEInk,
    required this.archivePath,
    required this.onTap,
  });

  @override
  State<_PageThumbnailTile> createState() => _PageThumbnailTileState();
}

class _PageThumbnailTileState extends State<_PageThumbnailTile> {
  ui.Image? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _PageThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.archivePath != widget.archivePath ||
        oldWidget.pageIndex != widget.pageIndex) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final path = widget.archivePath;
    if (path == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Check synchronous memory cache first
    final cached = CbzThumbnailService.getCachedThumbnail(
      archivePath: path,
      pageIndex: widget.pageIndex,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _thumbnail = cached;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final img = await CbzThumbnailService.getThumbnail(
      archivePath: path,
      pageIndex: widget.pageIndex,
    );
    if (mounted) {
      setState(() {
        _thumbnail = img;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEInk = widget.isEInk;
    final isCurrent = widget.isCurrent;

    // Card frame decoration
    final BoxDecoration cardDecoration;
    if (isEInk) {
      cardDecoration = BoxDecoration(
        color: const Color(0xFFE0DCD3),
        borderRadius: BorderRadius.circular(2.0),
        border: Border.all(
          color: const Color(0xFF1A1A18),
          width: isCurrent ? 2.5 : 1.0,
        ),
      );
    } else {
      cardDecoration = BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isCurrent ? 2.5 : 1.0,
        ),
      );
    }

    // Page badge decoration
    final BoxDecoration badgeDecoration;
    final TextStyle badgeStyle;
    if (isEInk) {
      if (isCurrent) {
        // Inverted badge for current page
        badgeDecoration = const BoxDecoration(
          color: Color(0xFF1A1A18),
          borderRadius: BorderRadius.all(Radius.circular(2.0)),
        );
        badgeStyle = GoogleFonts.robotoMono(
          color: const Color(0xFFEAE6DF),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        );
      } else {
        badgeDecoration = BoxDecoration(
          color: const Color(0xFFE0DCD3),
          borderRadius: const BorderRadius.all(Radius.circular(2.0)),
          border: Border.all(color: const Color(0xFF9E9A90), width: 1.0),
        );
        badgeStyle = GoogleFonts.robotoMono(
          color: const Color(0xFF1A1A18),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        );
      }
    } else {
      if (isCurrent) {
        badgeDecoration = BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(4.0),
        );
        badgeStyle = TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        );
      } else {
        badgeDecoration = BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4.0),
        );
        badgeStyle = const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        );
      }
    }

    Widget content;
    if (_isLoading) {
      content = Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(
              isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
            ),
          ),
        ),
      );
    } else if (_thumbnail != null) {
      final rawImg = RawImage(
        image: _thumbnail,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.low,
      );

      // Section 3.C: Grayscale (100%), Contrast (125%), Brightness (95%) on thumbnails in E-Ink
      content = isEInk
          ? ColorFiltered(
              colorFilter: EInkTokens.coverFilter,
              child: rawImg,
            )
          : rawImg;
    } else {
      content = Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: isEInk ? const Color(0xFF9E9A90) : theme.colorScheme.outlineVariant,
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: cardDecoration,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: badgeDecoration,
                child: Text(
                  '${widget.pageIndex + 1}',
                  style: badgeStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
