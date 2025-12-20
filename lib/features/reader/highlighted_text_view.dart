import 'package:flutter/material.dart';

/// A widget that displays text with a highlighted word/segment.
///
/// Used for TTS text highlighting to show the currently spoken word.
class HighlightedTextView extends StatefulWidget {
  final String text;
  final int? startOffset;
  final int? endOffset;
  final TextStyle? textStyle;
  final Color highlightColor;
  final EdgeInsets padding;
  final ScrollController? scrollController;
  final bool autoScroll;
  final double autoScrollPadding;
  final Duration autoScrollDuration;

  const HighlightedTextView({
    super.key,
    required this.text,
    this.startOffset,
    this.endOffset,
    this.textStyle,
    this.highlightColor = const Color(0xFFFFEB3B), // Yellow
    this.padding = const EdgeInsets.all(16.0),
    this.scrollController,
    this.autoScroll = true,
    this.autoScrollPadding = 48.0,
    this.autoScrollDuration = const Duration(milliseconds: 180),
  });

  @override
  State<HighlightedTextView> createState() => _HighlightedTextViewState();
}

class _HighlightedTextViewState extends State<HighlightedTextView> {
  ScrollController? _internalController;
  int? _lastAutoScrollStart;
  String _lastAutoScrollText = '';
  double _lastAutoScrollWidth = 0;
  DateTime _lastAutoScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

  ScrollController get _controller =>
      widget.scrollController ?? (_internalController ??= ScrollController());

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _maybeAutoScroll({
    required BoxConstraints constraints,
    required TextStyle style,
    required TextDirection direction,
    required TextScaler textScaler,
  }) {
    if (!widget.autoScroll) return;
    final startOffset = widget.startOffset;
    final endOffset = widget.endOffset;
    if (startOffset == null || endOffset == null) return;
    if (!_controller.hasClients) return;
    if (constraints.maxWidth <= 0) return;

    final text = widget.text;
    if (text.isEmpty) return;

    final start = startOffset.clamp(0, text.length);
    if (start == _lastAutoScrollStart &&
        text == _lastAutoScrollText &&
        constraints.maxWidth == _lastAutoScrollWidth) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastAutoScrollAt) < const Duration(milliseconds: 120)) {
      return;
    }

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: textScaler,
    );
    painter.layout(maxWidth: constraints.maxWidth);

    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: start),
      Rect.zero,
    );

    final lineHeight = painter.preferredLineHeight;
    final caretTop = caretOffset.dy;
    final caretBottom = caretTop + lineHeight;

    final position = _controller.position;
    final visibleTop = position.pixels;
    final visibleBottom = position.pixels + position.viewportDimension;
    final padding = widget.autoScrollPadding;

    if (caretTop >= visibleTop + padding &&
        caretBottom <= visibleBottom - padding) {
      _lastAutoScrollStart = start;
      _lastAutoScrollText = text;
      _lastAutoScrollWidth = constraints.maxWidth;
      return;
    }

    final target = (caretTop - padding).clamp(
      0.0,
      position.maxScrollExtent,
    );

    if ((target - position.pixels).abs() < 2) {
      return;
    }

    _lastAutoScrollStart = start;
    _lastAutoScrollText = text;
    _lastAutoScrollWidth = constraints.maxWidth;
    _lastAutoScrollAt = now;

    _controller.animateTo(
      target,
      duration: widget.autoScrollDuration,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) {
      return const Center(
        child: Text('No text available.'),
      );
    }

    final defaultStyle = widget.textStyle ??
        Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 18,
              height: 1.8,
            ) ??
        const TextStyle(fontSize: 18, height: 1.8);

    // If no highlighting offsets, show plain text
    if (widget.startOffset == null || widget.endOffset == null) {
      return SingleChildScrollView(
        controller: _controller,
        padding: widget.padding,
        child: SelectableText(
          widget.text,
          style: defaultStyle,
        ),
      );
    }

    // Validate and clamp offsets
    final start = widget.startOffset!.clamp(0, widget.text.length);
    final end = widget.endOffset!.clamp(start, widget.text.length);

    // Build highlighted text with three spans
    final beforeText = widget.text.substring(0, start);
    final highlightedText = widget.text.substring(start, end);
    final afterText = widget.text.substring(end);

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeAutoScroll(
            constraints: constraints,
            style: defaultStyle,
            direction: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          );
        });

        return SingleChildScrollView(
          controller: _controller,
          padding: widget.padding,
          child: SelectableText.rich(
            TextSpan(
              style: defaultStyle,
              children: [
                TextSpan(text: beforeText),
                TextSpan(
                  text: highlightedText,
                  style: TextStyle(
                    backgroundColor: widget.highlightColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: afterText),
              ],
            ),
          ),
        );
      },
    );
  }
}
