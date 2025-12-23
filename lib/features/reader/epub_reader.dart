import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/models/annotation.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';
import 'package:reader_app/features/dictionary/dictionary_dialog.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:reader_app/features/reader/epub_fallback_parser.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/utils/sentence_utils.dart';

import 'package:reader_app/utils/normalized_text_map.dart';
import 'package:reader_app/utils/text_normalization.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/features/reader/widgets/reader_settings_sheet.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';

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

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with WidgetsBindingObserver {
  List<EpubChapter>? _chapters;
  List<String> _allChapterContents =
      const []; // All chapter HTML for continuous scroll
  List<String> _allChapterPlainTexts = const []; // Plain text for each chapter
  List<GlobalKey> _chapterKeys = const []; // Keys to track chapter positions
  int _currentChapterIndex = 0;
  String? _currentContent;
  String _currentPlainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  SelectedContent? _selectedContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  bool _showChrome = false;
  bool _lockMode = false;
  Offset? _lastDoubleTapDown;
  late ReadingMode _readingMode;

  // TTS
  final TtsService _ttsService = TtsService();
  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  late PageController _pageController;
  int _ttsAdvanceRequestId = 0;
  int _ttsFromHereRequestId = 0;
  int _ttsNormalizedBaseOffset = 0;
  final GlobalKey _ttsHighlightKey = GlobalKey();
  bool _highlightKeyAssigned = false;
  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  int? _lastEnsuredStart;
  int? _lastEnsuredEnd;
  String? _cachedHighlightedHtml;
  ResolvedBookFile? _resolvedFile;
  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;
  late int _lastTtsSection;
  late double _lastScrollPosition;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HyphenationHelper.init();
    _ttsService.setOnFinished(_handleTtsFinished);
    _currentChapterIndex = widget.book.sectionIndex;
    _pageController = PageController(initialPage: _currentChapterIndex);
    _lastTtsSentenceStart = widget.book.lastTtsSentenceStart;
    _lastTtsSentenceEnd = widget.book.lastTtsSentenceEnd;
    _lastTtsSection = widget.book.lastTtsSection;
    _lastScrollPosition = widget.book.scrollPosition;
    _readingMode = widget.book.readingMode;
    _loadEpub();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSystemUiMode();
    });
  }

  @override
  void dispose() {
    _cleanupTempFile();
    _scrollController.dispose();
    _pageController.dispose();
    _ttsService.setOnFinished(null);
    _ttsService.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveReadingPositionFromScroll();
      _saveCurrentTtsSentence();
    }
  }

  Future<void> _loadEpub() async {
    try {
      final resolver = BookFileResolver();
      final resolved = await resolver.resolve(widget.book);
      _resolvedFile = resolved;
      final bytes = await File(resolved.path).readAsBytes();
      final chapters = await _readChaptersWithFallback(bytes);

      if (chapters.isEmpty) {
        setState(() {
          _error = "No chapters found in EPUB";
          _isLoading = false;
        });
        return;
      }

      // Preload ALL chapter contents for continuous scrolling
      final allContents = <String>[];
      final allPlainTexts = <String>[];
      final allKeys = <GlobalKey>[];

      for (final chapter in chapters) {
        final content = chapter.HtmlContent ?? '';
        allContents.add(content);
        allPlainTexts.add(_htmlToPlainText(content));
        allKeys.add(GlobalKey());
      }

      // Validation of index
      if (_currentChapterIndex >= chapters.length) {
        _currentChapterIndex = 0;
      }

      // Set current chapter data for TTS compatibility
      final currentContent = allContents[_currentChapterIndex];
      final currentPlainText = allPlainTexts[_currentChapterIndex];

      setState(() {
        _chapters = chapters;
        _allChapterContents = allContents;
        _allChapterPlainTexts = allPlainTexts;
        _chapterKeys = allKeys;
        _currentContent = currentContent;
        _currentPlainText = currentPlainText;
        _sentenceSpans = splitIntoSentences(currentPlainText);
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _cleanupTempFile() {
    final resolved = _resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      File(resolved.path).deleteSync();
    } catch (_) {
      // Ignore cleanup failures
    }
  }

  void _updateSystemUiMode() {
    if (_showChrome && !_lockMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _toggleChrome() {
    if (_lockMode) return;
    setState(() => _showChrome = !_showChrome);
    _updateSystemUiMode();
  }

  void _toggleLockMode() {
    setState(() {
      _lockMode = !_lockMode;
      if (_lockMode) {
        _showChrome = false;
      } else {
        _showChrome = true;
      }
    });
    _updateSystemUiMode();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _lockMode
                ? 'Lock mode on. Double-tap center to unlock.'
                : 'Lock mode off.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isCenterTap(Offset globalPosition) {
    final size = MediaQuery.of(context).size;
    if (size.isEmpty) return false;
    final centerWidth = size.width * 0.45;
    final centerHeight = size.height * 0.35;
    final left = (size.width - centerWidth) / 2;
    final top = (size.height - centerHeight) / 2;
    final rect = Rect.fromLTWH(left, top, centerWidth, centerHeight);
    return rect.contains(globalPosition);
  }



  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!_lockMode) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    if (_isCenterTap(position)) {
      _toggleLockMode();
    }
  }

  ReadingMode get _effectiveReadingMode {
    if (_readingMode == ReadingMode.webtoon) return ReadingMode.verticalContinuous;
    return _readingMode;
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.text,
    );
    if (selected == null || selected == _readingMode) return;
    setState(() => _readingMode = selected);
    unawaited(
      widget.repository.updateReadingProgress(
        widget.book.id,
        readingMode: selected,
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ReaderSettingsSheet(),
    );
  }

  Future<List<EpubChapter>> _readChaptersWithFallback(List<int> bytes) async {
    try {
      final book = await EpubReader.readBook(bytes);
      return _flattenChapters(book.Chapters ?? []);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (_shouldFallbackToSpine(message)) {
        try {
          final chapters = EpubFallbackParser.parseChapters(bytes);
          if (chapters.isNotEmpty) {
            return chapters;
          }
        } catch (_) {
          // Fall through to rethrow the original navigation error.
        }
      }
      rethrow;
    }
  }

  bool _shouldFallbackToSpine(String message) {
    if (!message.contains('epub parsing error') &&
        !message.contains('incorrect epub manifest')) {
      return false;
    }
    return message.contains('toc') ||
        message.contains('nav') ||
        message.contains('manifest');
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
    if (_allChapterContents.isEmpty) return;

    if (userInitiated) {
      _ttsAdvanceRequestId++;
      if (_showTtsControls) {
        unawaited(_ttsService.stop());
      }
    }

    // Update current chapter data from preloaded content
    setState(() {
      _currentChapterIndex = index;
      _currentContent = _allChapterContents[index];
      _currentPlainText = _allChapterPlainTexts[index];
      _sentenceSpans = splitIntoSentences(_currentPlainText);
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      _lastEnsuredStart = null;
      _lastEnsuredEnd = null;
      _ttsNormalizedBaseOffset = 0;
    });

    // Save progress
    unawaited(widget.repository.updateReadingProgress(
      widget.book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
      scrollPosition: userInitiated ? 0.0 : null,
      lastReadingSentenceStart: userInitiated ? -1 : null,
      lastReadingSentenceEnd: userInitiated ? -1 : null,
    ));

    // Scroll to the chapter position
    if (userInitiated && _chapterKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final key = _chapterKeys[index];
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.0, // Align to the top
          );
        }
      });
    }
  }

  void _handleTtsFinished() {
    if (!mounted) return;
    if (!_showTtsControls || !_ttsContinuous) return;
    unawaited(_advanceToNextReadableChapterAndSpeak());
  }

  // _normalizePlainText removed - using shared normalizePlainText from lib/utils/text_normalization.dart

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
    final map = buildNormalizedTextMap(rawText);
    if (map.normalizedToRaw.isEmpty) return html;

    final maxIndex = map.normalizedToRaw.length - 1;
    if (maxIndex < 0) return html;

    final clampedStart = start.clamp(0, maxIndex);
    final clampedEnd = end.clamp(0, map.normalizedToRaw.length);
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

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) {
      return html;
    }

    // Calculate absolute position in chapter text
    final baseOffset =
        _ttsNormalizedBaseOffset.clamp(0, _currentPlainText.length);
    final highlightStart = baseOffset + wordStart;
    final highlightEnd = baseOffset + wordEnd;

    // Cache check - same highlight range?
    if (_cachedHighlightedHtml != null &&
        highlightStart == _lastHighlightStart &&
        highlightEnd == _lastHighlightEnd) {
      return _cachedHighlightedHtml!;
    }

    // Build highlighted HTML for word range
    final highlighted =
        _buildHighlightedHtml(html, highlightStart, highlightEnd);
    _cachedHighlightedHtml = highlighted;
    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;

    // Save reading progress (debounced via repository)
    _lastTtsSentenceStart = highlightStart;
    _lastTtsSentenceEnd = highlightEnd;
    _lastTtsSection = _currentChapterIndex;

    unawaited(
      widget.repository.updateReadingProgress(
        widget.book.id,
        sectionIndex: _currentChapterIndex,
        totalPages: _chapters?.length ?? 0,
        lastTtsSentenceStart: highlightStart,
        lastTtsSentenceEnd: highlightEnd,
        lastTtsSection: _currentChapterIndex,
      ),
    );
    return highlighted;
  }

  /// Pre-compute TTS text data using Rust for faster sentence lookups




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
      // Retry after a short delay if context is not yet available.
      Future.delayed(const Duration(milliseconds: 50), _retryEnsureVisible);
      return;
    }

    _performEnsureVisible(context);
  }

  void _retryEnsureVisible() {
    if (!mounted || !_ttsFollowMode) return;
    final retryContext = _ttsHighlightKey.currentContext;
    if (retryContext == null) return;
    _performEnsureVisible(retryContext);
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

  void _restoreScrollPosition() {
    if (!_scrollController.hasClients) return;
    if (_chapterKeys.isEmpty) return;

    // Wait for the ListView to be laid out before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final chapterIndex =
          _currentChapterIndex.clamp(0, _chapterKeys.length - 1);
      final key = _chapterKeys[chapterIndex];
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;

      if (renderBox != null) {
        // Scroll to the chapter position
        final position = renderBox.localToGlobal(Offset.zero);
        final scrollOffset = _scrollController.offset + position.dy;
        final maxExtent = _scrollController.position.maxScrollExtent;
        final clamped = scrollOffset.clamp(0.0, maxExtent);
        _scrollController.jumpTo(clamped);
      } else if (_lastScrollPosition > 0) {
        // Fallback: use saved scroll position
        final maxExtent = _scrollController.position.maxScrollExtent;
        final clamped = _lastScrollPosition.clamp(0.0, maxExtent);
        _scrollController.jumpTo(clamped);
      }
    });
  }

  void _saveReadingPositionFromScroll() {
    if (!_scrollController.hasClients) return;
    final text = _currentPlainText;
    if (text.trim().isEmpty) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset.clamp(0.0, maxExtent);
    final fraction = maxExtent <= 0 ? 0.0 : (offset / maxExtent);
    final maxIndex = text.length - 1;
    final approxIndex =
        maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);

    final span = sentenceForOffset(_sentenceSpans, approxIndex) ??
        SentenceSpan(0, text.length);

    _lastScrollPosition = offset;

    unawaited(
      widget.repository.updateReadingProgress(
        widget.book.id,
        sectionIndex: _currentChapterIndex,
        totalPages: _chapters?.length ?? 0,
        scrollPosition: offset,
        lastReadingSentenceStart: span.start,
        lastReadingSentenceEnd: span.end,
      ),
    );
  }

  void _saveCurrentTtsSentence() {
    final start = _ttsService.currentWordStart;
    if (start == null) return;
    if (_currentPlainText.trim().isEmpty) return;

    final baseOffset =
        _ttsNormalizedBaseOffset.clamp(0, _currentPlainText.length);
    final absoluteOffset = baseOffset + start;
    final span = sentenceForOffset(_sentenceSpans, absoluteOffset);
    if (span == null) return;

    _lastTtsSentenceStart = span.start;
    _lastTtsSentenceEnd = span.end;
    _lastTtsSection = _currentChapterIndex;

    unawaited(
      widget.repository.updateReadingProgress(
        widget.book.id,
        sectionIndex: _currentChapterIndex,
        totalPages: _chapters?.length ?? 0,
        lastTtsSentenceStart: span.start,
        lastTtsSentenceEnd: span.end,
        lastTtsSection: _currentChapterIndex,
      ),
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

    final start = findSentenceStart(text, approxIndex);
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

  String _resolveTtsText() {
    final text = _currentPlainText;
    if (text.trim().isEmpty) return '';

    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsSection == _currentChapterIndex) {
      final start = _lastTtsSentenceStart.clamp(0, text.length);
      _ttsNormalizedBaseOffset = start;
      return text.substring(start);
    }

    return _ttsTextFromScrollPosition();
  }

  Future<void> _speakFromHere(String startText, {int? baseOffset}) async {
    final normalized = normalizePlainText(startText);
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

    // Pre-compute Rust TTS data for faster highlighting


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
      // Pre-compute Rust TTS data for faster highlighting

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
    _lastEnsuredStart = null;
    _lastEnsuredEnd = null;
    _updateSystemUiMode();
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = _showChrome && !_lockMode;
    final showTtsControls = showChrome && _showTtsControls;
    final showBottomControls = showChrome && !_showTtsControls;

    return Scaffold(
      body: Stack(
        children: [
          // Content layer
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: _buildBody(),
            ),
          ),
          // Removed center overlay - tap detection handled via the content layer
          if (showChrome) _buildTopBar(),
          if (showBottomControls && _buildControls() != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildControls()!,
            ),
          if (showTtsControls)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: TtsControlsSheet(
                  ttsService: _ttsService,
                  textToSpeak: _currentPlainText,
                  resolveTextToSpeak: _resolveTtsText,
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
                  onStop: _saveCurrentTtsSentence,
                  onPause: _saveCurrentTtsSentence,
                  onClose: _closeTtsControls,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleTts() async {
    final next = !_showTtsControls;
    setState(() {
      _showTtsControls = next;
      if (next) {
        _showChrome = true;
      }
    });
    _updateSystemUiMode();

    if (!next) {
      _saveCurrentTtsSentence();
      _ttsAdvanceRequestId++;
      _ttsService.stop();
      _ttsNormalizedBaseOffset = 0;
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      _lastEnsuredStart = null;
      _lastEnsuredEnd = null;
      return;
    }

    final chapters = _chapters;
    if (_lastTtsSentenceStart >= 0 &&
        chapters != null &&
        _lastTtsSection >= 0 &&
        _lastTtsSection < chapters.length &&
        _lastTtsSection != _currentChapterIndex) {
      await _loadChapter(_lastTtsSection, userInitiated: false);
    }
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



  bool get _isPagedMode => 
      _effectiveReadingMode == ReadingMode.vertical || 
      _effectiveReadingMode == ReadingMode.leftToRight;

  Widget _buildPagedView() {
    final isVertical = _effectiveReadingMode == ReadingMode.vertical;
    final highlightColor = Theme.of(context).colorScheme.primaryContainer;
    
    final extensions = [
      TagExtension(
        tagsToExtend: {_ttsHighlightTag},
        builder: (context) {
          final text = context.node.text ?? '';
          final style = context.style?.generateTextStyle() ?? const TextStyle();
          return _TtsHighlightSpan(
            key: _nextHighlightKey(),
            text: text,
            textStyle: style,
            highlightColor: highlightColor,
          );
        },
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        if (_isCenterTap(details.globalPosition)) {
          _toggleChrome();
        }
      },
      child: Consumer<ReaderThemeRepository>(
        builder: (context, themeRepo, _) {
          final themeConfig = themeRepo.config;
          final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
          
          return PageView.builder(
            controller: _pageController,
            scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
            itemCount: _allChapterContents.length,
            onPageChanged: (index) {
               if (index != _currentChapterIndex) {
                  _loadChapter(index);
               }
            },
            itemBuilder: (context, index) {
              final htmlContent = _allChapterContents[index];
              final displayContent = themeConfig.hyphenation
                    ? HyphenationHelper.processHtml(htmlContent)
                    : htmlContent;
              
              final isTtsActive = _showTtsControls && _ttsService.state == TtsState.playing;
              
              if (isTtsActive && index == _currentChapterIndex) {
                   // Note: reusing _buildTtsHighlightedHtml which uses globals. 
                   // This works because we call _loadChapter on page change which updates state.
               }
              
              return AnimatedBuilder(
                animation: _ttsService,
                builder: (context, _) {
                   if (isTtsActive && index == _currentChapterIndex) {
                       return Html(
                          data: _buildTtsHighlightedHtml(),
                          extensions: extensions,
                          style: _buildHtmlStyles(themeConfig),
                       );
                   }
                   return SingleChildScrollView(
                     child: Padding(
                       padding: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 24.0),
                       child: Html(
                          data: displayContent,
                          extensions: extensions,
                          style: _buildHtmlStyles(themeConfig),
                       ),
                     ),
                   );
                }
              );
            },
          );
        },
      ),
    );
  }

  Map<String, Style> _buildHtmlStyles(ReaderThemeConfig themeConfig) {
      return {
        "body": Style(
          fontSize: FontSize(themeConfig.fontSize),
          lineHeight: LineHeight(themeConfig.lineHeight),
          fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
          fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
          fontWeight: FontWeight.values[(themeConfig.fontWeight ~/ 100).clamp(0, 8)],
          textAlign: _parseTextAlign(themeConfig.textAlign),
          letterSpacing: themeConfig.wordSpacing,
          padding: HtmlPaddings.zero,
          margin: Margins.zero,
        ),
        _ttsHighlightTag: Style(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
        "p": Style(
          margin: Margins.only(bottom: themeConfig.paragraphSpacing),
          textAlign: _parseTextAlign(themeConfig.textAlign),
        ),
        "img": Style(
           width: Width(100, Unit.percent),
           margin: Margins.only(bottom: 12.0),
        ),
      };
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

    if (_allChapterContents.isEmpty) {
      return const Center(child: Text("No content available."));
    }

    if (_isPagedMode) {
      return _buildPagedView();
    }





    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          _saveReadingPositionFromScroll();
          _updateCurrentChapterFromScroll();
        }
        return false;
      },
      child: SelectionArea(
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
                  final selected = normalizePlainText(
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
        child: ListenableBuilder(
          listenable: _ttsService,
          builder: (context, _) {
            // Recompute isTtsActive on every TTS state change
            final isTtsActive =
                _showTtsControls && _ttsService.state == TtsState.playing;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) {
                if (_isCenterTap(details.globalPosition)) {
                  _toggleChrome();
                }
              },
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _allChapterContents.length,
                itemBuilder: (context, index) {
                  final content = _allChapterContents[index];
                  final isFirst = index == 0;
                  final isLast = index == _allChapterContents.length - 1;
                  final isWebtoon =
                      _effectiveReadingMode == ReadingMode.webtoon;

                  final imageSpacing = isWebtoon ? 24.0 : 12.0;
                  final chapterSpacing = isWebtoon ? 80.0 : 48.0;
                  final highlightColor =
                      Theme.of(context).colorScheme.primaryContainer;

                  final extensions = [
                    TagExtension(
                      tagsToExtend: {_ttsHighlightTag},
                      builder: (context) {
                        final text = context.node.text ?? '';
                        final style = context.style?.generateTextStyle() ??
                            const TextStyle();
                        return _TtsHighlightSpan(
                          key: _nextHighlightKey(),
                          text: text,
                          textStyle: style,
                          highlightColor: highlightColor,
                        );
                      },
                    ),
                  ];

                  Widget buildHtml(String htmlContent) {
                    return Consumer<ReaderThemeRepository>(
                      builder: (context, themeRepo, _) {
                        final themeConfig = themeRepo.config;
                        final horizontalMargin = themeConfig.pageMargins ? 16.0 : 0.0;
                        
                        final displayContent = themeConfig.hyphenation
                            ? HyphenationHelper.processHtml(htmlContent)
                            : htmlContent;
                        
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
                          child: Html(
                            data: displayContent,
                            extensions: extensions,
                            style: {
                              "body": Style(
                                fontSize: FontSize(themeConfig.fontSize),
                                lineHeight: LineHeight(themeConfig.lineHeight),
                                fontFamily: _getGoogleFontData(themeConfig.fontFamily).fontFamily,
                                fontFamilyFallback: _getGoogleFontData(themeConfig.fontFamily).fontFamilyFallback,
                                fontWeight: FontWeight.values[(themeConfig.fontWeight ~/ 100).clamp(0, 8)],
                                textAlign: _parseTextAlign(themeConfig.textAlign),
                                letterSpacing: themeConfig.wordSpacing,
                                padding: HtmlPaddings.zero,
                                margin: Margins.zero,
                              ),
                              _ttsHighlightTag: Style(
                                backgroundColor: highlightColor,
                              ),
                              "p": Style(
                                margin: Margins.only(bottom: themeConfig.paragraphSpacing),
                                textAlign: _parseTextAlign(themeConfig.textAlign),
                              ),
                              "img": Style(
                                width: Width(100, Unit.percent),
                                margin: Margins.only(bottom: imageSpacing),
                              ),
                            },
                          ),
                        );
                      },
                    );
                  }

                  return Container(
                    key: _chapterKeys[index],
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: isFirst ? 16.0 : chapterSpacing,
                      bottom: isLast ? 100.0 : 0.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Chapter content - use highlighted version if TTS is active
                        if (isTtsActive && index == _currentChapterIndex)
                          AnimatedBuilder(
                            animation: _ttsService,
                            builder: (context, _) {
                              _highlightKeyAssigned = false;
                              final highlightedHtml =
                                  _buildTtsHighlightedHtml();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _maybeEnsureHighlightVisible();
                              });
                              return buildHtml(highlightedHtml);
                            },
                          )
                        else
                          buildHtml(content),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Updates _currentChapterIndex based on scroll position
  void _updateCurrentChapterFromScroll() {
    if (_chapterKeys.isEmpty || !_scrollController.hasClients) return;

    final viewportTop = _scrollController.offset;
    final viewportMiddle = viewportTop + MediaQuery.of(context).size.height / 2;

    int visibleChapter = 0;
    for (int i = 0; i < _chapterKeys.length; i++) {
      final key = _chapterKeys[i];
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      final chapterTop = position.dy + viewportTop;
      final chapterBottom = chapterTop + renderBox.size.height;

      if (viewportMiddle >= chapterTop && viewportMiddle < chapterBottom) {
        visibleChapter = i;
        break;
      }
      if (chapterTop > viewportMiddle) {
        visibleChapter = (i > 0) ? i - 1 : 0;
        break;
      }
      visibleChapter = i;
    }

    if (visibleChapter != _currentChapterIndex) {
      setState(() {
        _currentChapterIndex = visibleChapter;
        _currentContent = _allChapterContents[visibleChapter];
        _currentPlainText = _allChapterPlainTexts[visibleChapter];
        _sentenceSpans = splitIntoSentences(_currentPlainText);
      });

      // Save progress
      unawaited(widget.repository.updateReadingProgress(
        widget.book.id,
        sectionIndex: visibleChapter,
        totalPages: _chapters?.length ?? 0,
      ));
    }
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(_lockMode ? Icons.lock : Icons.lock_open),
                  tooltip: _lockMode ? 'Unlock' : 'Lock',
                  onPressed: _toggleLockMode,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: _showSettingsSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: _showReadingModePicker,
                ),
                IconButton(
                  icon: Icon(
                      _showTtsControls ? Icons.volume_off : Icons.volume_up),
                  tooltip: 'Listen',
                  onPressed: () => _toggleTts(),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Find in chapter',
                  onPressed: _showSearchDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.list),
                  tooltip: 'Chapters',
                  onPressed: _showChapterList,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildControls() {
    if (_chapters == null || _chapters!.length <= 1) return null;

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentChapterIndex > 0
                    ? () => _loadChapter(
                          _currentChapterIndex - 1,
                          userInitiated: true,
                        )
                    : null,
              ),
              Text(
                "Chapter ${_currentChapterIndex + 1} / ${_chapters!.length}",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentChapterIndex < _chapters!.length - 1
                    ? () => _loadChapter(
                          _currentChapterIndex + 1,
                          userInitiated: true,
                        )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAnnotationDialog(String selectedText) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AnnotationDialog(selectedText: selectedText),
    );

    if (!mounted || result == null) return;

    final note = result['note'] as String;
    final color = result['color'] as int;
    final annotationRepo = context.read<AnnotationRepository>();

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

    await annotationRepo.addAnnotation(annotation);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Annotation saved')),
    );
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

  /// Get font data for flutter_html Style
  ({String? fontFamily, List<String>? fontFamilyFallback}) _getGoogleFontData(String family) {
    try {
      final textStyle = GoogleFonts.getFont(family);
      return (
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: textStyle.fontFamilyFallback,
      );
    } catch (_) {
      // Fallback to the raw family name
      return (fontFamily: family, fontFamilyFallback: null);
    }
  }

  TextAlign _parseTextAlign(String align) {
    switch (align) {
      case 'left': return TextAlign.left;
      case 'right': return TextAlign.right;
      case 'center': return TextAlign.center;
      case 'justify': return TextAlign.justify;
      default: return TextAlign.justify;
    }
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
            color: borderColor.withValues(alpha: 0.4),
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
