import 'package:flutter/material.dart';

class PdfTextPickerSheet extends StatefulWidget {
  final int pageIndex;
  final int pageCount;
  final Future<String> Function() loadText;
  final ValueChanged<String> onListenFromHere;

  const PdfTextPickerSheet({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    required this.loadText,
    required this.onListenFromHere,
  });

  @override
  State<PdfTextPickerSheet> createState() => _PdfTextPickerSheetState();
}

class _PdfTextPickerSheetState extends State<PdfTextPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  bool _isLoading = true;
  String? _error;
  List<_TextSegment> _segments = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text;
      if (next == _query) return;
      setState(() => _query = next);
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _segments = const [];
    });

    try {
      final raw = await widget.loadText();
      if (!mounted) return;

      final normalized = _normalizeText(raw);
      final parts = _splitIntoSegments(normalized)
          .asMap()
          .entries
          .map((e) => _TextSegment(index: e.key, text: e.value))
          .toList(growable: false);

      setState(() {
        _isLoading = false;
        _error = null;
        _segments = parts;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _splitIntoSegments(String text) {
    if (text.trim().isEmpty) return const [];

    const minChars = 160;
    const maxChars = 420;

    final segments = <String>[];
    var start = 0;
    var lastSpace = -1;

    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code == 32) {
        lastSpace = i;
      }

      final isSentenceBoundary = (code == 46 || code == 33 || code == 63) &&
          i + 1 < text.length &&
          text.codeUnitAt(i + 1) == 32;

      final currentLen = i - start + 1;

      if (isSentenceBoundary && currentLen >= minChars) {
        final part = text.substring(start, i + 1).trim();
        if (part.isNotEmpty) segments.add(part);

        start = i + 1;
        while (start < text.length && text.codeUnitAt(start) == 32) {
          start++;
        }
        lastSpace = -1;
        continue;
      }

      if (currentLen >= maxChars && lastSpace > start) {
        final part = text.substring(start, lastSpace).trim();
        if (part.isNotEmpty) segments.add(part);

        start = lastSpace + 1;
        while (start < text.length && text.codeUnitAt(start) == 32) {
          start++;
        }
        lastSpace = -1;
      }
    }

    if (start < text.length) {
      final part = text.substring(start).trim();
      if (part.isNotEmpty) segments.add(part);
    }

    return segments;
  }

  List<_TextSegment> get _filteredSegments {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _segments;
    return _segments
        .where((s) => s.text.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _listenFromSegmentIndex(int segmentIndex) {
    if (_segments.isEmpty) return;
    if (segmentIndex < 0 || segmentIndex >= _segments.length) return;

    final text = _segments
        .sublist(segmentIndex)
        .map((s) => s.text)
        .join(' ')
        .trim();

    if (text.isEmpty) return;
    widget.onListenFromHere(text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Text view — Page ${widget.pageIndex + 1} / ${widget.pageCount}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search this page…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: _buildBody(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final segments = _filteredSegments;
    if (segments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No readable text found on this page.'),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: segments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final segment = segments[index];
        return ListTile(
          title: Text(
            segment.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.play_arrow),
          onTap: () => _listenFromSegmentIndex(segment.index),
        );
      },
    );
  }
}

class _TextSegment {
  final int index;
  final String text;

  const _TextSegment({
    required this.index,
    required this.text,
  });
}

