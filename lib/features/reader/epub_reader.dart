import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/models/annotation.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/dictionary/dictionary_dialog.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:html/parser.dart' as html_parser;

class EpubReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const EpubReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  List<EpubChapter>? _chapters;
  int _currentChapterIndex = 0;
  String? _currentContent;
  String _currentPlainText = '';
  SelectedContent? _selectedContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  
  // TTS
  final TtsService _ttsService = TtsService();
  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  int _ttsAdvanceRequestId = 0;
  int _ttsFromHereRequestId = 0;

  @override
  void initState() {
    super.initState();
    _ttsService.setOnFinished(_handleTtsFinished);
    _currentChapterIndex = widget.book.sectionIndex;
    _loadEpub();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _ttsService.setOnFinished(null);
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _loadEpub() async {
    try {
      final bytes = await File(widget.book.path).readAsBytes();
      final book = await EpubReader.readBook(bytes);

      // Flatten chapters
      final chapters = _flattenChapters(book.Chapters ?? []);

      setState(() {
        _chapters = chapters;
      });

      if (chapters.isNotEmpty) {
        // Validation of index
        if (_currentChapterIndex >= chapters.length) {
          _currentChapterIndex = 0;
        }
        await _loadChapter(_currentChapterIndex);
      } else {
        setState(() {
          _error = "No chapters found in EPUB";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<EpubChapter> _flattenChapters(List<EpubChapter> chapters) {
    List<EpubChapter> result = [];
    for (var chapter in chapters) {
      result.add(chapter);
      if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
        result.addAll(_flattenChapters(chapter.SubChapters!));
      }
    }
    return result;
  }

  Future<void> _loadChapter(int index, {bool userInitiated = false}) async {
    if (_chapters == null || index < 0 || index >= _chapters!.length) return;

    if (userInitiated) {
      _ttsAdvanceRequestId++;
      if (_showTtsControls) {
        unawaited(_ttsService.stop());
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _currentChapterIndex = index;
    });

    // Save progress
    widget.repository.updateReadingProgress(
      widget.book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
    );

    try {
      final chapter = _chapters![index];
      final content = chapter.HtmlContent ?? '';
      final plainText = _htmlToPlainText(content);

      setState(() {
        _currentContent = content;
        _currentPlainText = plainText;
        _error = null;
        _isLoading = false;
      });

      // Reset scroll for now (TODO: Restore scroll position)
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (e) {
      setState(() {
        _error = "Chapter load error: $e";
        _currentContent = null;
        _currentPlainText = '';
        _isLoading = false;
      });
    }
  }

  void _handleTtsFinished() {
    if (!mounted) return;
    if (!_showTtsControls || !_ttsContinuous) return;
    unawaited(_advanceToNextReadableChapterAndSpeak());
  }

  String _normalizePlainText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _sliceTextFromApproxIndex(String text, int approxIndex) {
    if (text.isEmpty) return '';
    if (approxIndex <= 0) return text;
    if (approxIndex >= text.length) return '';

    var start = 0;

    // Prefer starting at the beginning of a sentence near the scroll position.
    final boundaries = <String>['. ', '! ', '? '];
    for (final boundary in boundaries) {
      final i = text.lastIndexOf(boundary, approxIndex);
      if (i != -1) {
        final candidate = i + boundary.length;
        if (candidate > start) start = candidate;
      }
    }

    // If we couldn't find a sentence boundary, at least avoid restarting from the
    // very beginning by snapping to the previous whitespace.
    if (start == 0) {
      final ws = text.lastIndexOf(' ', approxIndex);
      if (ws != -1 && ws + 1 < text.length) {
        start = ws + 1;
      }
    }

    while (start < text.length && text[start] == ' ') {
      start++;
    }

    return text.substring(start);
  }

  String _ttsTextFromScrollPosition() {
    final text = _currentPlainText;
    if (text.trim().isEmpty) return '';

    if (!_scrollController.hasClients) {
      return text;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset.clamp(0.0, maxExtent);
    final fraction = maxExtent <= 0 ? 0.0 : (offset / maxExtent);
    final maxIndex = text.length - 1;
    final approxIndex = maxIndex <= 0
        ? 0
        : (fraction * maxIndex).floor().clamp(0, maxIndex);
    return _sliceTextFromApproxIndex(text, approxIndex);
  }

  Future<void> _speakFromHere(String startText) async {
    final normalized = _normalizePlainText(startText);
    if (normalized.isEmpty) return;

    final requestId = ++_ttsFromHereRequestId;
    _ttsAdvanceRequestId++;

    setState(() {
      _showTtsControls = true;
    });

    await _ttsService.speak(normalized);
    if (!mounted || requestId != _ttsFromHereRequestId) return;
  }

  Future<void> _advanceToNextReadableChapterAndSpeak() async {
    final chapters = _chapters;
    if (chapters == null || chapters.isEmpty) return;

    final startIndex = _currentChapterIndex + 1;
    if (startIndex >= chapters.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reached end of book.')),
        );
      }
      return;
    }

    final requestId = ++_ttsAdvanceRequestId;

    for (var index = startIndex; index < chapters.length; index++) {
      await _loadChapter(index, userInitiated: false);
      if (!mounted || requestId != _ttsAdvanceRequestId) return;

      final text = _currentPlainText.trim();
      if (text.isEmpty) {
        continue;
      }

      await _ttsService.speak(text);
      return;
    }

    if (mounted && requestId == _ttsAdvanceRequestId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more readable text found.')),
      );
    }
  }

  void _closeTtsControls() {
    _ttsAdvanceRequestId++;
    setState(() => _showTtsControls = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            icon: Icon(_showTtsControls ? Icons.volume_off : Icons.volume_up),
            onPressed: _toggleTts,
            tooltip: 'Listen',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
            tooltip: 'Find in chapter',
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showChapterList,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_showTtsControls)
            TtsControlsSheet(
              ttsService: _ttsService,
              textToSpeak: _currentPlainText,
              resolveTextToSpeak: _ttsTextFromScrollPosition,
              emptyTextMessage: 'No readable text in this chapter.',
              isContinuous: _ttsContinuous,
              onContinuousChanged: (value) {
                _ttsAdvanceRequestId++;
                setState(() => _ttsContinuous = value);
              },
              onClose: _closeTtsControls,
            ),
        ],
      ),
      bottomNavigationBar: _buildControls(),
    );
  }

  void _toggleTts() {
    setState(() {
      _showTtsControls = !_showTtsControls;
      if (!_showTtsControls) {
        _ttsAdvanceRequestId++;
        _ttsService.stop();
      }
    });
  }

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';

    final document = html_parser.parse(html);
    document.querySelectorAll('script,style,noscript').forEach((e) => e.remove());

    final rawText = document.body?.text ??
        document.documentElement?.text ??
        document.text ??
        '';

    return rawText
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Error: $_error", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentContent != null) {
      return SelectionArea(
        onSelectionChanged: (content) {
          _selectedContent = content;
        },
        contextMenuBuilder: (context, selectableRegionState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: [
              ...selectableRegionState.contextMenuButtonItems,
              ContextMenuButtonItem(
                onPressed: () {
                  final selected = _normalizePlainText(
                    _selectedContent?.plainText ?? '',
                  );
                  if (selected.isEmpty || _currentPlainText.isEmpty) {
                    selectableRegionState.hideToolbar();
                    return;
                  }

                  final full = _currentPlainText;
                  var startIndex = full.indexOf(selected);

                  if (startIndex < 0) {
                    final fullLower = full.toLowerCase();
                    final selectedLower = selected.toLowerCase();
                    startIndex = fullLower.indexOf(selectedLower);
                  }

                  final startText =
                      startIndex >= 0 ? full.substring(startIndex) : selected;

                  unawaited(_speakFromHere(startText));
                  selectableRegionState.hideToolbar();
                },
                label: 'Listen from here',
              ),
              ContextMenuButtonItem(
                onPressed: () {
                  if (_selectedContent != null && _selectedContent!.plainText.isNotEmpty) {
                    _showAnnotationDialog(_selectedContent!.plainText);
                    selectableRegionState.hideToolbar();
                  }
                },
                label: 'Highlight',
              ),
              ContextMenuButtonItem(
                onPressed: () {
                  if (_selectedContent != null && _selectedContent!.plainText.isNotEmpty) {
                    _showDictionaryDialog(_selectedContent!.plainText.split(' ').first);
                    selectableRegionState.hideToolbar();
                  }
                },
                label: 'Define',
              ),
            ],
          );
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16.0),
          child: Html(
            data: _currentContent!,
            style: {
              "body": Style(
                fontSize: FontSize(18),
                lineHeight: const LineHeight(1.8),
              ),
              "p": Style(margin: Margins.only(bottom: 16)),
              "img": Style(width: Width(100, Unit.percent)),
            },
          ),
        ),
      );
    }

    return const Center(child: Text("Loading..."));
  }

  Widget? _buildControls() {
    if (_chapters == null || _chapters!.length <= 1) return null;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentChapterIndex > 0
                ? () => _loadChapter(_currentChapterIndex - 1, userInitiated: true)
                : null,
          ),
          Text(
            "Chapter ${_currentChapterIndex + 1} / ${_chapters!.length}",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentChapterIndex < _chapters!.length - 1
                ? () => _loadChapter(_currentChapterIndex + 1, userInitiated: true)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _showAnnotationDialog(String selectedText) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AnnotationDialog(selectedText: selectedText),
    );

    if (result != null && mounted) {
      final note = result['note'] as String;
      final color = result['color'] as int;

      final annotation = Annotation(
        id: const Uuid().v4(),
        bookId: widget.book.id,
        selectedText: selectedText,
        note: note,
        chapterIndex: _currentChapterIndex,
        startOffset: 0, // Not precise yet
        endOffset: 0, // Not precise yet
        color: color,
        createdAt: DateTime.now(),
      );

      await context.read<AnnotationRepository>().addAnnotation(annotation);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Annotation saved')),
        );
      }
    }
  }

  void _showDictionaryDialog(String word) {
    showDictionaryDialog(context, word);
  }

  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Find in Chapter'),
          content: TextField(
            controller: searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter text to find...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final query = searchController.text.trim();
                Navigator.pop(ctx);
                if (query.isNotEmpty) {
                  final plainText = _currentPlainText;
                  if (plainText.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No searchable text in this chapter.')),
                    );
                    return;
                  }

                  if (plainText.toLowerCase().contains(query.toLowerCase())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Found "$query" in this chapter.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('"$query" not found in this chapter.')),
                    );
                  }
                }
              },
              child: const Text('Find'),
            ),
          ],
        );
      },
    );
  }

  void _showChapterList() {
    if (_chapters == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _chapters!.length,
        itemBuilder: (context, index) {
          final chapter = _chapters![index];
          return ListTile(
            title: Text(chapter.Title ?? 'Chapter ${index + 1}'),
            selected: index == _currentChapterIndex,
            onTap: () {
              Navigator.pop(context);
              _loadChapter(index, userInitiated: true);
            },
          );
        },
      ),
    );
  }
}
