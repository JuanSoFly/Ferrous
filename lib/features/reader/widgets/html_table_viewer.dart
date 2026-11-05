import 'package:flutter/material.dart';

/// A responsive, interactive wrapper for HTML tables in reader views.
///
/// Features:
/// - Smooth horizontal scrolling with visible, interactive scrollbar.
/// - Left/right chevron navigation buttons in the header for effortless one-tap column scrolling.
/// - Direct drag gestures within the table that scroll the table instead of turning book pages.
/// - Double-tap anywhere on the table to immediately open Full View.
/// - A "Full View" expansion button that opens a 2D pinch-to-zoom viewer (`TableFullScreenViewer`).
class HtmlTableViewer extends StatefulWidget {
  final Widget child;

  const HtmlTableViewer({
    super.key,
    required this.child,
  });

  @override
  State<HtmlTableViewer> createState() => _HtmlTableViewerState();
}

class _HtmlTableViewerState extends State<HtmlTableViewer> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollMetrics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollMetrics();
    });
  }

  @override
  void didUpdateWidget(HtmlTableViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollMetrics();
    });
  }

  void _updateScrollMetrics() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final currentOffset = _scrollController.offset;
    final canLeft = currentOffset > 2.0;
    final canRight = currentOffset < (maxExtent - 2.0);

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollMetrics);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollLeft() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset - 160.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollRight() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + 160.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _openFullScreenTable(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Table Viewer',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return TableFullScreenViewer(tableWidget: widget.child);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    final hasOverflow = _canScrollLeft || _canScrollRight;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        border: Border.all(color: borderColor, width: 1.0),
        borderRadius: BorderRadius.circular(10.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
              border: Border(bottom: BorderSide(color: borderColor, width: 0.75)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Table',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (hasOverflow) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Scrollable',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Left chevron button
                  InkWell(
                    onTap: _canScrollLeft ? _scrollLeft : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 20,
                        color: _canScrollLeft
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  // Right chevron button
                  InkWell(
                    onTap: _canScrollRight ? _scrollRight : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: _canScrollRight
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Expand / Full-Screen Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openFullScreenTable(context),
                    borderRadius: BorderRadius.circular(6.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_full_rounded,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Full View',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable Table Body with direct horizontal swipe and double-tap to expand
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {},
            onHorizontalDragUpdate: (details) {
              if (_scrollController.hasClients) {
                final newOffset = (_scrollController.offset - details.primaryDelta!).clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                );
                _scrollController.jumpTo(newOffset);
              }
            },
            onHorizontalDragEnd: (_) {},
            onDoubleTap: () => _openFullScreenTable(context),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: hasOverflow,
              interactive: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dedicated, full-screen interactive viewer for HTML tables.
///
/// Features:
/// - Unconstrained layout rendering (`constrained: false`), allowing all columns and rows to render fully.
/// - Two-dimensional smooth panning (both horizontal and vertical).
/// - Multi-touch pinch-to-zoom (0.2x to 4.5x) so users can zoom out to view the entire table,
///   or zoom in to inspect cell details.
/// - Single-thumb zoom buttons (+, -, Fit) at bottom right for effortless navigation on mobile.
class TableFullScreenViewer extends StatefulWidget {
  final Widget tableWidget;

  const TableFullScreenViewer({
    super.key,
    required this.tableWidget,
  });

  @override
  State<TableFullScreenViewer> createState() => _TableFullScreenViewerState();
}

class _TableFullScreenViewerState extends State<TableFullScreenViewer> {
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    if (currentScale < 4.2) {
      final newScale = (currentScale * 1.3).clamp(0.2, 4.5);
      _transformController.value = Matrix4.identity()..scaleByDouble(newScale, newScale, 1.0, 1.0);
    }
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    if (currentScale > 0.25) {
      final newScale = (currentScale / 1.3).clamp(0.2, 4.5);
      _transformController.value = Matrix4.identity()..scaleByDouble(newScale, newScale, 1.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Table Viewer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Pinch to zoom • Pan all columns & rows',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen_rounded),
            tooltip: 'Fit / Reset',
            onPressed: _resetZoom,
          ),
        ],
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Divider(
            height: 1.0,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.2,
              maxScale: 4.5,
              boundaryMargin: const EdgeInsets.all(80.0),
              constrained: false, // Unconstrained layout so every single column and row renders in full!
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: widget.tableWidget,
              ),
            ),
          ),
          // Floating Thumb-Friendly Zoom Controls
          Positioned(
            right: 16.0,
            bottom: 24.0,
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(24.0),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 0.75,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 20),
                      tooltip: 'Zoom Out',
                      onPressed: _zoomOut,
                    ),
                    Container(
                      width: 1.0,
                      height: 20.0,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fit_screen_rounded, size: 18),
                      tooltip: 'Reset Zoom',
                      onPressed: _resetZoom,
                    ),
                    Container(
                      width: 1.0,
                      height: 20.0,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 20),
                      tooltip: 'Zoom In',
                      onPressed: _zoomIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
