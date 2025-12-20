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
import 'package:html/dom.dart' as dom;

class _NormalizedTextMap {
  final String normalized;
  final List<int> normalizedToRaw;

  const _NormalizedTextMap(this.normalized, this.normalizedToRaw);
}

_NormalizedTextMap _buildNormalizedTextMap(String raw) {
  if (raw.trim().isEmpty) {
    return const _NormalizedTextMap('', []);
  }

  final buffer = StringBuffer();
  final map = <int>[];
  var inWhitespace = false;

  for (var i = 0; i < raw.length; i++) {
    var ch = raw[i];
    if (ch == '\u200B') {
      continue;
    }
    if (ch == '\u00A0') {
      ch = ' ';
    }

    final isWhitespace = ch.trim().isEmpty;
    if (isWhitespace) {
      if (buffer.isEmpty) continue;
      if (inWhitespace) continue;
      buffer.write(' ');
      map.add(i);
      inWhitespace = true;
      continue;
    }

    buffer.write(ch);
    map.add(i);
    inWhitespace = false;
  }

  var normalized = buffer.toString();
  if (normalized.endsWith(' ')) {
    normalized = normalized.substring(0, normalized.length - 1);
    if (map.isNotEmpty) {
      map.removeLast();
    }
  }

  return _NormalizedTextMap(normalized, map);
}

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
  bool _ttsFollowMode = true;
  int _ttsAdvanceRequestId = 0;
  int _ttsFromHereRequestId = 0;
  int _ttsNormalizedBaseOffset = 0;
  final GlobalKey _ttsHighlightKey = GlobalKey();
  bool _highlightKeyAssigned = false;
  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  int? _lastHighlightBaseOffset;
  int? _lastEnsuredStart;
  int? _lastEnsuredEnd;
  String? _cachedHighlightedHtml;

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
        _cachedHighlightedHtml = null;
        _lastHighlightStart = null;
        _lastHighlightEnd = null;
        _lastHighlightBaseOffset = null;
        _lastEnsuredStart = null;
        _lastEnsuredEnd = null;
        _ttsNormalizedBaseOffset = 0;
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

  static const String _ttsHighlightTag = 'tts-highlight';

  void _collectTextNodes(dom.Node node, List<dom.Text> out) {
    if (node is dom.Text) {
      out.add(node);
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'script' || tag == 'style' || tag == 'noscript') {
        return;
      }
    }
    for (final child in node.nodes) {
      _collectTextNodes(child, out);
    }
  }

  String _buildHighlightedHtml(String html, int start, int end) {
    if (start < 0 || end <= start) return html;

    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final textNodes = <dom.Text>[];
    _collectTextNodes(root, textNodes);
    if (textNodes.isEmpty) return html;

    final rawBuffer = StringBuffer();
    for (final node in textNodes) {
      rawBuffer.write(node.data);
    }

    final rawText = rawBuffer.toString();
    final map = _buildNormalizedTextMap(rawText);
    if (map.normalizedToRaw.isEmpty) return html;

    final maxIndex = map.normalizedToRaw.length - 1;
    if (maxIndex < 0) return html;

    final clampedStart = start.clamp(0, maxIndex) as int;
    final clampedEnd = end.clamp(0, map.normalizedToRaw.length) as int;
    if (clampedEnd <= clampedStart) return html;

    final rawStart = map.normalizedToRaw[clampedStart];
    final rawEnd = map.normalizedToRaw[clampedEnd - 1] + 1;

    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;
      final nodeStart = offset;
      final nodeEnd = offset + nodeText.length;
      offset = nodeEnd;

      if (rawEnd <= nodeStart || rawStart >= nodeEnd) {
        continue;
      }

      final localStart = (rawStart - nodeStart).clamp(0, nodeText.length);
      final localEnd = (rawEnd - nodeStart).clamp(0, nodeText.length);

      if (localStart >= localEnd) continue;

      final before = nodeText.substring(0, localStart);
      final mid = nodeText.substring(localStart, localEnd);
      final after = nodeText.substring(localEnd);

      final parent = node.parent;
      if (parent == null) continue;

      final index = parent.nodes.indexOf(node);
      if (index < 0) continue;

      final newNodes = <dom.Node>[];
      if (before.isNotEmpty) {
        newNodes.add(dom.Text(before));
      }
      if (mid.isNotEmpty) {
        final mark = dom.Element.tag(_ttsHighlightTag);
        mark.append(dom.Text(mid));
        newNodes.add(mark);
      }
      if (after.isNotEmpty) {
        newNodes.add(dom.Text(after));
      }

      parent.nodes.removeAt(index);
      parent.nodes.insertAll(index, newNodes);
    }

    return root.outerHtml;
  }

  String _buildTtsHighlightedHtml() {
    final html = _currentContent;
    if (html == null) return '';

    final start = _ttsService.currentStartOffset;
    final end = _ttsService.currentEndOffset;
    if (start == null || end == null) {
      return html;
    }

    final baseOffset =
        _ttsNormalizedBaseOffset.clamp(0, _currentPlainText.length) as int;
    final adjustedStart = baseOffset + start;
    final adjustedEnd = baseOffset + end;

    if (_cachedHighlightedHtml != null &&
        adjustedStart == _lastHighlightStart &&
        adjustedEnd == _lastHighlightEnd &&
        baseOffset == _lastHighlightBaseOffset) {
      return _cachedHighlightedHtml!;
    }

    final highlighted = _buildHighlightedHtml(html, adjustedStart, adjustedEnd);
    _cachedHighlightedHtml = highlighted;
    _lastHighlightStart = adjustedStart;
    _lastHighlightEnd = adjustedEnd;
    _lastHighlightBaseOffset = baseOffset;
    return highlighted;
  }

  Key? _nextHighlightKey() {
    if (_highlightKeyAssigned) return null;
    _highlightKeyAssigned = true;
    return _ttsHighlightKey;
  }

  void _maybeEnsureHighlightVisible() {
    if (!_ttsFollowMode) return;
    if (_lastHighlightStart == null || _lastHighlightEnd == null) return;
    if (_lastEnsuredStart == _lastHighlightStart &&
        _lastEnsuredEnd == _lastHighlightEnd) {
      return;
    }

    final context = _ttsHighlightKey.currentContext;
    if (context == null) {
      // Retry after a short delay if context is not yet available
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _ttsFollowMode) {
          final retryContext = _ttsHighlightKey.currentContext;
          if (retryContext != null) {
            _performEnsureVisible(retryContext);
          }
        }
      });
      return;
    }

    _performEnsureVisible(context);
  }

  void _performEnsureVisible(BuildContext context) {
    _lastEnsuredStart = _lastHighlightStart;
    _lastEnsuredEnd = _lastHighlightEnd;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  String _sliceTextFromApproxIndex(String text, int approxIndex) {
    if (text.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return '';
    }
    if (approxIndex <= 0) {
      _ttsNormalizedBaseOffset = 0;
      return text;
    }
    if (approxIndex >= text.length) {
      _ttsNormalizedBaseOffset = text.length;
      return '';
    }

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

    _ttsNormalizedBaseOffset = start;
    return text.substring(start);
  }

  String _ttsTextFromScrollPosition() {
    final text = _currentPlainText;
    if (text.trim().isEmpty) return '';

    if (!_scrollController.hasClients) {
      _ttsNormalizedBaseOffset = 0;
      return text;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset.clamp(0.0, maxExtent);
    final fraction = maxExtent <= 0 ? 0.0 : (offset / maxExtent);
    final maxIndex = text.length - 1;
    final approxIndex =
        maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);
    return _sliceTextFromApproxIndex(text, approxIndex);
  }

  Future<void> _speakFromHere(String startText, {int? baseOffset}) async {
    final normalized = _normalizePlainText(startText);
    if (normalized.isEmpty) return;

    if (baseOffset != null && baseOffset >= 0) {
      _ttsNormalizedBaseOffset = baseOffset;
    } else {
      final index = _currentPlainText.indexOf(normalized);
      _ttsNormalizedBaseOffset = index >= 0 ? index : 0;
    }

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

      _ttsNormalizedBaseOffset = 0;
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
    _ttsNormalizedBaseOffset = 0;
    _cachedHighlightedHtml = null;
    _lastHighlightStart = null;
    _lastHighlightEnd = null;
    _lastHighlightBaseOffset = null;
    _lastEnsuredStart = null;
    _lastEnsuredEnd = null;
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
              isFollowMode: _ttsFollowMode,
              onFollowModeChanged: (value) {
                setState(() => _ttsFollowMode = value);
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
        _ttsNormalizedBaseOffset = 0;
        _cachedHighlightedHtml = null;
        _lastHighlightStart = null;
        _lastHighlightEnd = null;
        _lastHighlightBaseOffset = null;
        _lastEnsuredStart = null;
        _lastEnsuredEnd = null;
      }
    });
  }

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';

    final document = html_parser.parse(html);
    document
        .querySelectorAll('script,style,noscript')
        .forEach((e) => e.remove());

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
      final isTtsActive =
          _showTtsControls && _ttsService.state == TtsState.playing;
      final highlightColor = Theme.of(context).colorScheme.primaryContainer;
      final extensions = [
        TagExtension(
          tagsToExtend: {_ttsHighlightTag},
          builder: (context) {
            final text = context.node.text ?? '';
            final style =
                context.style?.generateTextStyle() ?? const TextStyle();
            return _TtsHighlightSpan(
              key: _nextHighlightKey(),
              text: text,
              textStyle: style,
              highlightColor: highlightColor,
            );
          },
        ),
      ];

      Widget htmlView(String data) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16.0),
          child: Html(
            data: data,
            extensions: extensions,
            style: {
              "body": Style(
                fontSize: FontSize(18),
                lineHeight: const LineHeight(1.8),
              ),
              _ttsHighlightTag: Style(
                backgroundColor: highlightColor,
              ),
              "p": Style(margin: Margins.only(bottom: 16)),
              "img": Style(width: Width(100, Unit.percent)),
            },
          ),
        );
      }

      if (isTtsActive) {
        return AnimatedBuilder(
          animation: _ttsService,
          builder: (context, _) {
            _highlightKeyAssigned = false;
            final highlightedHtml = _buildTtsHighlightedHtml();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeEnsureHighlightVisible();
            });
            return htmlView(highlightedHtml);
          },
        );
      }

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

                  unawaited(_speakFromHere(
                    startText,
                    baseOffset: startIndex >= 0 ? startIndex : null,
                  ));
                  selectableRegionState.hideToolbar();
                },
                label: 'Listen from here',
              ),
              ContextMenuButtonItem(
                onPressed: () {
                  if (_selectedContent != null &&
                      _selectedContent!.plainText.isNotEmpty) {
                    _showAnnotationDialog(_selectedContent!.plainText);
                    selectableRegionState.hideToolbar();
                  }
                },
                label: 'Highlight',
              ),
              ContextMenuButtonItem(
                onPressed: () {
                  if (_selectedContent != null &&
                      _selectedContent!.plainText.isNotEmpty) {
                    _showDictionaryDialog(
                      _selectedContent!.plainText.split(' ').first,
                    );
                    selectableRegionState.hideToolbar();
                  }
                },
                label: 'Define',
              ),
            ],
          );
        },
        child: htmlView(_currentContent!),
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
                ? () =>
                    _loadChapter(_currentChapterIndex - 1, userInitiated: true)
                : null,
          ),
          Text(
            "Chapter ${_currentChapterIndex + 1} / ${_chapters!.length}",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentChapterIndex < _chapters!.length - 1
                ? () =>
                    _loadChapter(_currentChapterIndex + 1, userInitiated: true)
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
                      const SnackBar(
                          content: Text('No searchable text in this chapter.')),
                    );
                    return;
                  }

                  if (plainText.toLowerCase().contains(query.toLowerCase())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Found "$query" in this chapter.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('"$query" not found in this chapter.')),
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

class _TtsHighlightSpan extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  final Color highlightColor;

  const _TtsHighlightSpan({
    super.key,
    required this.text,
    required this.textStyle,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // Use a more visible highlight with border and shadow for contrast
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.yellow.shade600 : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        text,
        style: textStyle.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.black : null,
        ),
      ),
    );
  }
}
