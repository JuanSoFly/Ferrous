import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/services/book_file_resolver.dart';
import 'package:ferrous/core/utils/performance.dart';
import 'package:ferrous/core/utils/sentence_utils.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ferrous/core/utils/dom_text_utils.dart';
import 'package:ferrous/features/reader/hyphenation_helper.dart';
import 'package:ferrous/core/utils/html_defragmenter.dart';
import 'package:ferrous/src/rust/api/txt.dart' as rust_txt;
import 'package:ferrous/core/services/diagnostic_logger.dart';
import 'package:ferrous/core/utils/dom_chunker.dart';
import 'reader_mode_controller.dart';

class TxtChapterInfo {
  final String? title;
  TxtChapterInfo({this.title});
  // ignore: non_constant_identifier_names
  String? get Title => title;
}

class TxtRawChapter {
  final String title;
  final String htmlContent;
  final int rawCharLength;

  const TxtRawChapter({
    required this.title,
    required this.htmlContent,
    required this.rawCharLength,
  });

  factory TxtRawChapter.fromJson(Map<String, dynamic> json) {
    return TxtRawChapter(
      title: json['title'] as String? ?? 'Section',
      htmlContent: json['html_content'] as String? ?? json['htmlContent'] as String? ?? '',
      rawCharLength: (json['raw_char_length'] ?? json['rawCharLength'] ?? 0) as int,
    );
  }
}

class ParsedChapterArtifact {
  final String contentWithIndent;
  final String plainText;
  final List<SentenceSpan> sentenceSpans;
  final List<String> chunks;
  final List<int> chunkOffsets;

  const ParsedChapterArtifact({
    required this.contentWithIndent,
    required this.plainText,
    required this.sentenceSpans,
    required this.chunks,
    required this.chunkOffsets,
  });
}

class _DecodeStage1Payload {
  final String rawOutput;
  final int targetIndex;
  const _DecodeStage1Payload({
    required this.rawOutput,
    required this.targetIndex,
  });
}

class _DecodeStage1Result {
  final List<TxtRawChapter> rawChapters;
  final Map<int, ParsedChapterArtifact> initialParsed;
  const _DecodeStage1Result({
    required this.rawChapters,
    required this.initialParsed,
  });
}

class TxtChapterController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  TxtChapterController({
    required this.book,
    required this.repository,
  }) : _scrollController = ScrollController(
         initialScrollOffset: (book.readingMode == ReadingMode.verticalContinuous &&
                 book.scrollPosition.isFinite &&
                 book.scrollPosition > 0)
             ? book.scrollPosition
             : 0.0,
       );

  List<TxtChapterInfo>? _chapters;
  List<TxtRawChapter> _rawChapters = const [];
  List<int> _rawChapterLengths = const [];
  List<GlobalKey> _chapterKeys = const [];

  final Map<int, ParsedChapterArtifact> _parsedCache = {};
  static const int _maxCachedChapters = 35;

  List<String> _allChapterContents = const [];
  List<String> _allChapterPlainTexts = const [];
  List<List<SentenceSpan>> _allChapterSentenceSpans = const [];
  List<List<String>> _allChapterChunks = const [];
  List<List<int>> _allChapterChunkOffsets = const [];

  int _currentChapterIndex = 0;
  String? _currentContent;
  String _currentPlainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  bool _isLoading = true;
  String? _error;

  ScrollController _scrollController;
  int _scrollEpoch = 0;
  bool _isTransitioningMode = false;
  double _chapterProgress = 0.0;
  final Map<int, double> _chapterHeights = {};
  ResolvedBookFile? _resolvedFile;

  double _activeChapterTop = 0.0;
  double _activeChapterBottom = -1.0;
  int _lastTrackedChapter = -1;

  void invalidateScrollBounds() {
    _activeChapterTop = 0.0;
    _activeChapterBottom = -1.0;
    _lastTrackedChapter = -1;
  }

  bool _isRestoringPosition = false;
  int _restoreGeneration = 0;
  bool _isProgrammaticScroll = false;
  DateTime _lastScrollCheckTime = DateTime.fromMillisecondsSinceEpoch(0);

  late int _lastReadingSentenceStart;
  late int _lastReadingSentenceEnd;
  late double _lastScrollPosition;

  // Getters
  List<TxtChapterInfo>? get chapters => _chapters;
  List<TxtRawChapter> get rawChapters => _rawChapters;
  List<int> get rawChapterLengths => _rawChapterLengths;
  List<String> get allChapterContents => _allChapterContents;
  List<String> get allChapterPlainTexts => _allChapterPlainTexts;
  List<List<String>> get allChapterChunks => _allChapterChunks;
  List<List<int>> get allChapterChunkOffsets => _allChapterChunkOffsets;
  List<GlobalKey> get chapterKeys => _chapterKeys;
  int get currentChapterIndex => _currentChapterIndex;
  String? get currentContent => _currentContent;
  String get currentPlainText => _currentPlainText;
  List<SentenceSpan> get sentenceSpans => _sentenceSpans;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ScrollController get scrollController => _scrollController;
  int get scrollEpoch => _scrollEpoch;
  bool get isTransitioningMode => _isTransitioningMode;
  bool get isRestoringPosition => _isRestoringPosition;
  bool get isProgrammaticScroll => _isProgrammaticScroll;
  double get chapterProgress => _chapterProgress;
  ResolvedBookFile? get resolvedFile => _resolvedFile;
  int get lastReadingSentenceStart => _lastReadingSentenceStart;
  int get lastReadingSentenceEnd => _lastReadingSentenceEnd;
  double get lastScrollPosition => _lastScrollPosition;

  int _activePageStartCharOffset = -1;
  int _activePageEndCharOffset = -1;

  int get activePageStartCharOffset => _activePageStartCharOffset;
  int get activePageEndCharOffset => _activePageEndCharOffset;

  void setActivePageBounds(int start, int end) {
    _activePageStartCharOffset = start;
    _activePageEndCharOffset = end;
  }

  void resetActivePageBounds() {
    _activePageStartCharOffset = -1;
    _activePageEndCharOffset = -1;
  }

  ({int start, int end, int expected}) getReadingBoundsForTap({
    required double tapDy,
    required double viewportHeight,
    required ReaderModeController modeController,
    int? chapterLength,
    int? tappedChapterIndex,
  }) {
    final len = chapterLength ?? _currentPlainText.length;
    if (tappedChapterIndex != null && tappedChapterIndex != _currentChapterIndex) {
      return (start: 0, end: len, expected: 0);
    }
    final ratio = viewportHeight > 0 ? (tapDy / viewportHeight).clamp(0.0, 1.0) : 0.0;
    if (modeController.isPagedMode) {
      final rawStart = _activePageStartCharOffset >= 0
          ? _activePageStartCharOffset
          : (_lastReadingSentenceStart >= 0 ? _lastReadingSentenceStart : 0);
      final start = rawStart.clamp(0, len);
      final rawEnd = _activePageEndCharOffset > start
          ? _activePageEndCharOffset
          : (start + 3000);
      final end = rawEnd.clamp(start, len);
      final expected = start + ((end - start) * ratio).round();
      return (start: start, end: end, expected: expected);
    } else {
      final rawAnchor = _lastReadingSentenceStart >= 0 ? _lastReadingSentenceStart : 0;
      final anchor = rawAnchor.clamp(0, len);
      final start = (anchor - 2500).clamp(0, len);
      final end = (anchor + 3500).clamp(start, len);
      return (start: start, end: end, expected: anchor);
    }
  }

  void init() {
    _currentChapterIndex = book.sectionIndex;
    _lastReadingSentenceStart = book.lastReadingSentenceStart;
    _lastReadingSentenceEnd = book.lastReadingSentenceEnd;
    _lastScrollPosition = book.scrollPosition;
    _chapterProgress = 0.0;
    unawaited(_loadTxt());
  }

  Future<void> _loadTxt() async {
    await measureAsync('txt_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;

        final rawOutput = await rust_txt.readTxtToHtml(path: resolved.path);
        
        List<TxtRawChapter> rawChapters;
        Map<int, ParsedChapterArtifact> initialParsed;
        final targetChapter = _currentChapterIndex;

        if (rawOutput.length > 500000) {
          // Offload JSON decoding and Stage 1 parsing to background isolate to avoid UI jank
          final result = await compute(
            _decodeAndParseStage1Isolated,
            _DecodeStage1Payload(rawOutput: rawOutput, targetIndex: targetChapter),
          );
          rawChapters = result.rawChapters;
          initialParsed = result.initialParsed;
        } else {
          rawChapters = _decodeRawChapters(rawOutput);
          final priorityIndices = <int>{
            targetChapter,
            if (targetChapter > 0) targetChapter - 1,
            if (targetChapter + 1 < rawChapters.length) targetChapter + 1,
          };
          final initialPayload = <int, String>{
            for (final idx in priorityIndices)
              if (idx >= 0 && idx < rawChapters.length) idx: rawChapters[idx].htmlContent,
          };
          initialParsed = await compute(_parseBatchIsolated, initialPayload);
        }

        if (rawChapters.isEmpty) {
          DiagnosticLogger.instance.log('TXT', 'No content found in TXT file', level: LogLevel.error);
          _error = 'No content found in TXT file';
          _isLoading = false;
          notifyListeners();
          return;
        }

        _rawChapters = rawChapters;
        _rawChapterLengths = rawChapters.map((c) => c.rawCharLength).toList();
        _chapters = rawChapters.map((c) => TxtChapterInfo(title: c.title)).toList();
        _chapterKeys = List.generate(rawChapters.length, (_) => GlobalKey());

        // Initialize flat arrays with placeholders
        _allChapterContents = List.generate(rawChapters.length, (i) => rawChapters[i].htmlContent);
        _allChapterPlainTexts = List.generate(rawChapters.length, (_) => '');
        _allChapterSentenceSpans = List.generate(rawChapters.length, (_) => const []);
        _allChapterChunks = List.generate(rawChapters.length, (i) => [rawChapters[i].htmlContent]);
        _allChapterChunkOffsets = List.generate(rawChapters.length, (_) => [0]);

        if (_currentChapterIndex >= rawChapters.length) {
          _currentChapterIndex = 0;
        }

        for (final entry in initialParsed.entries) {
          _applyParsedArtifact(entry.key, entry.value);
        }

        final activeArtifact = _parsedCache[_currentChapterIndex];
        if (activeArtifact != null) {
          _currentContent = activeArtifact.contentWithIndent;
          _currentPlainText = activeArtifact.plainText;
          _sentenceSpans = activeArtifact.sentenceSpans;
        } else {
          _currentContent = rawChapters[_currentChapterIndex].htmlContent;
        }

        final anchor = _readingAnchorOffset();
        _chapterProgress = anchor >= 0 ? _fractionForTextOffset(_currentChapterIndex, anchor) : 0.0;

        // Stage 1 Done: Immediately render first frame (< 60ms)
        _isLoading = false;
        notifyListeners();

        // STAGE 2: Schedule sliding lookahead background parsing for surrounding chapters
        _scheduleBackgroundParsing();
      } catch (e, stack) {
        DiagnosticLogger.instance.logError('TXT', e, stack);
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  int _backgroundParsingEpoch = 0;

  void _scheduleBackgroundParsing() {
    final epoch = ++_backgroundParsingEpoch;
    unawaited(() async {
      // Lookahead window: 5 chapters behind, 25 chapters ahead (max 30 chapters, always <= 35 LRU cap)
      final start = (_currentChapterIndex - 5).clamp(0, _rawChapters.length);
      final end = (_currentChapterIndex + 25).clamp(0, _rawChapters.length);

      for (int i = start; i < end; i += 4) {
        await Future.delayed(const Duration(milliseconds: 35));
        if (!hasListeners || epoch != _backgroundParsingEpoch) return;

        final batchIndices = <int>[];
        for (int j = i; j < (i + 4).clamp(0, end); j++) {
          if (!_parsedCache.containsKey(j)) {
            batchIndices.add(j);
          }
        }

        if (batchIndices.isEmpty) continue;

        final batchPayload = <int, String>{
          for (final idx in batchIndices) idx: _rawChapters[idx].htmlContent,
        };

        try {
          final batchResult = await compute(_parseBatchIsolated, batchPayload);
          if (epoch != _backgroundParsingEpoch) return;
          for (final entry in batchResult.entries) {
            _applyParsedArtifact(entry.key, entry.value);
          }
          _evictDistantCache();
        } catch (_) {}
      }
    }());
  }

  Future<void> ensureChapterParsed(int chapterIndex) async {
    if (chapterIndex < 0 || chapterIndex >= _rawChapters.length) return;
    if (_parsedCache.containsKey(chapterIndex)) {
      final cached = _parsedCache[chapterIndex]!;
      _applyParsedArtifact(chapterIndex, cached);
      return;
    }

    final batchPayload = <int, String>{
      chapterIndex: _rawChapters[chapterIndex].htmlContent,
    };

    try {
      final batchResult = await compute(_parseBatchIsolated, batchPayload);
      for (final entry in batchResult.entries) {
        _applyParsedArtifact(entry.key, entry.value);
      }
      _evictDistantCache();
    } catch (e) {
      DiagnosticLogger.instance.log(
        'TXT',
        'Failed to ensure chapter $chapterIndex parsed: $e',
        level: LogLevel.error,
      );
    }
  }

  void _applyParsedArtifact(int index, ParsedChapterArtifact artifact) {
    _parsedCache[index] = artifact;
    if (index >= 0 && index < _allChapterContents.length) {
      _allChapterContents[index] = artifact.contentWithIndent;
      _allChapterPlainTexts[index] = artifact.plainText;
      _allChapterSentenceSpans[index] = artifact.sentenceSpans;
      _allChapterChunks[index] = artifact.chunks;
      _allChapterChunkOffsets[index] = artifact.chunkOffsets;
    }
    if (index == _currentChapterIndex) {
      _currentContent = artifact.contentWithIndent;
      _currentPlainText = artifact.plainText;
      _sentenceSpans = artifact.sentenceSpans;
    }
  }

  void _evictDistantCache() {
    if (_parsedCache.length <= _maxCachedChapters) return;

    final sortedEntries = _parsedCache.keys.toList()
      ..sort((a, b) {
        final distA = (a - _currentChapterIndex).abs();
        final distB = (b - _currentChapterIndex).abs();
        return distB.compareTo(distA);
      });

    while (_parsedCache.length > _maxCachedChapters && sortedEntries.isNotEmpty) {
      final furthest = sortedEntries.removeAt(0);
      if ((furthest - _currentChapterIndex).abs() > 2) {
        _parsedCache.remove(furthest);
      }
    }
  }

  static _DecodeStage1Result _decodeAndParseStage1Isolated(_DecodeStage1Payload payload) {
    final rawChapters = _decodeRawChapters(payload.rawOutput);
    final targetIndex = payload.targetIndex.clamp(0, rawChapters.isEmpty ? 0 : rawChapters.length - 1);

    final priorityIndices = <int>{
      targetIndex,
      if (targetIndex > 0) targetIndex - 1,
      if (targetIndex + 1 < rawChapters.length) targetIndex + 1,
    };

    final batchPayload = <int, String>{
      for (final idx in priorityIndices)
        if (idx >= 0 && idx < rawChapters.length) idx: rawChapters[idx].htmlContent,
    };

    final initialParsed = _parseBatchIsolated(batchPayload);

    return _DecodeStage1Result(
      rawChapters: rawChapters,
      initialParsed: initialParsed,
    );
  }

  static List<TxtRawChapter> _decodeRawChapters(String rawOutput) {
    final trimmed = rawOutput.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final List<dynamic> decoded = jsonDecode(trimmed);
        return decoded
            .map((item) => TxtRawChapter.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    return [
      TxtRawChapter(
        title: 'Beginning',
        htmlContent: rawOutput,
        rawCharLength: rawOutput.length,
      ),
    ];
  }

  static Map<int, ParsedChapterArtifact> _parseBatchIsolated(Map<int, String> payload) {
    final result = <int, ParsedChapterArtifact>{};

    for (final entry in payload.entries) {
      final index = entry.key;
      final content = entry.value;

      final doc = html_parser.parse(content);
      HtmlDefragmenter.defragmentDocument(doc);
      final plainText = DomTextUtils.extractPlainText(doc.body ?? doc.documentElement);
      final spans = splitIntoSentences(plainText);
      final defragmentedHtml = doc.body?.innerHtml ?? content;
      final contentWithIndent = HyphenationHelper.injectIndentTags(defragmentedHtml);
      final chunkResult = DomChunker.split(contentWithIndent);

      result[index] = ParsedChapterArtifact(
        contentWithIndent: contentWithIndent,
        plainText: plainText,
        sentenceSpans: spans,
        chunks: chunkResult.chunks,
        chunkOffsets: chunkResult.chunkStartOffsets,
      );
    }

    return result;
  }

  void startModeTransition() {
    _isTransitioningMode = true;
    _isRestoringPosition = true;
    _restoreGeneration++;
  }

  void endModeTransition() {
    _isTransitioningMode = false;
    _isRestoringPosition = false;
    notifyListeners();
  }

  void prepareForContinuousMode(int targetChapter, {double? progress}) {
    startModeTransition();
    _currentChapterIndex = targetChapter;
    if (progress != null) {
      _chapterProgress = progress.clamp(0.0, 1.0);
    }

    final targetOffset = estimateScrollOffsetForChapter(targetChapter, _chapterProgress);
    _lastScrollPosition = targetOffset;
    book.sectionIndex = targetChapter;
    book.scrollPosition = targetOffset;

    if (_scrollController.hasClients) {
      _scrollController.dispose();
      _scrollController = ScrollController(initialScrollOffset: targetOffset);
      _scrollEpoch++;
      notifyListeners();
    } else {
      _scrollController.dispose();
      _scrollController = ScrollController(initialScrollOffset: targetOffset);
    }
  }

  void prepareForPagedMode(int targetChapter, {double? progress}) {
    startModeTransition();
    _currentChapterIndex = targetChapter;
    if (progress != null) {
      _chapterProgress = progress.clamp(0.0, 1.0);
    }
    book.sectionIndex = targetChapter;
  }

  void recordChapterHeight(int index, double height) {
    if (height > 0) {
      _chapterHeights[index] = height;
    }
  }

  void clearRecordedChapterHeights() {
    _chapterHeights.clear();
    invalidateScrollBounds();
  }

  double estimateScrollOffsetForChapter(int chapterIndex, [double progress = 0.0]) {
    if (chapterIndex <= 0 && progress <= 0.0) return 0.0;

    double totalMeasuredHeight = 0.0;
    int totalMeasuredChars = 0;
    for (final entry in _chapterHeights.entries) {
      final idx = entry.key;
      if (idx >= 0 && idx < _rawChapterLengths.length) {
        final chars = _rawChapterLengths[idx];
        if (chars > 0 && entry.value > 0) {
          totalMeasuredHeight += entry.value;
          totalMeasuredChars += chars;
        }
      }
    }

    final avgPxPerChar = (totalMeasuredChars > 0 && totalMeasuredHeight > 0)
        ? (totalMeasuredHeight / totalMeasuredChars)
        : 0.38;

    const chapterSpacing = 48.0;
    double offset = 0.0;

    for (int i = 0; i < chapterIndex; i++) {
      final recordedHeight = _chapterHeights[i];
      if (recordedHeight != null && recordedHeight > 0) {
        offset += recordedHeight;
      } else {
        final chars = (i < _rawChapterLengths.length) ? _rawChapterLengths[i] : 800;
        offset += chars * avgPxPerChar;
      }
      offset += chapterSpacing;
    }

    if (progress > 0.0) {
      final curHeight = _chapterHeights[chapterIndex] ??
          (((chapterIndex < _rawChapterLengths.length) ? _rawChapterLengths[chapterIndex] : 800) * avgPxPerChar);
      offset += curHeight * progress.clamp(0.0, 1.0);
    }

    return offset;
  }

  void scrollToChapter(int index) {
    _scrollToChapter(index);
  }

  void _scrollToChapter(int index, {int attempt = 0}) {
    if (index < 0 || _chapters == null || index >= _chapters!.length) return;
    if (attempt == 0) {
      invalidateScrollBounds();
      _isProgrammaticScroll = true;
      _currentChapterIndex = index;
      _chapterProgress = 0.0;
    }

    if (!_scrollController.hasClients) {
      _isProgrammaticScroll = false;
      prepareForContinuousMode(index, progress: 0.0);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isProgrammaticScroll = false;
        return;
      }
      if (index >= _chapterKeys.length) {
        _isProgrammaticScroll = false;
        return;
      }

      final key = _chapterKeys[index];
      final context = key.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (context != null && box != null && box.attached && box.hasSize) {
        recordChapterHeight(index, box.size.height);
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: 0.0,
        ).then((_) {
          _isProgrammaticScroll = false;
          _chapterProgress = 0.0;
          if (_scrollController.hasClients) {
            final currentContext = key.currentContext;
            if (currentContext != null && currentContext.mounted) {
              updateCurrentChapterFromScroll(currentContext, force: true);
            }
          }
        }).catchError((_) {
          _isProgrammaticScroll = false;
        });
      } else {
        final currentOffset = _scrollController.offset;
        final maxExtent = _scrollController.position.maxScrollExtent;
        final estimatedPixelTarget = estimateScrollOffsetForChapter(index, 0.0);

        final targetJump = (maxExtent > 0 && estimatedPixelTarget > maxExtent)
            ? maxExtent
            : estimatedPixelTarget.clamp(0.0, maxExtent);

        if ((currentOffset - targetJump).abs() > 1.0) {
          _scrollController.jumpTo(targetJump);
        }

        if (attempt < 15) {
          _scrollToChapter(index, attempt: attempt + 1);
        } else {
          _isProgrammaticScroll = false;
          _currentChapterIndex = index;
          _chapterProgress = 0.0;
          notifyListeners();
          unawaited(repository.updateReadingProgress(
            book.id,
            sectionIndex: index,
            totalPages: _chapters?.length ?? 0,
            scrollPosition: _scrollController.hasClients ? _scrollController.offset : null,
          ));
        }
      }
    });
  }

  void updateCurrentChapterFromScroll(BuildContext context, {bool force = false}) {
    if (_isTransitioningMode || _isProgrammaticScroll || _isRestoringPosition) return;
    if (_chapterKeys.isEmpty || !_scrollController.hasClients) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastScrollCheckTime).inMilliseconds < 100) return;
    _lastScrollCheckTime = now;

    final scrollOffset = _scrollController.offset;
    if (_activeChapterBottom > _activeChapterTop &&
        scrollOffset >= _activeChapterTop &&
        scrollOffset < _activeChapterBottom &&
        _lastTrackedChapter == _currentChapterIndex) {
      final h = _activeChapterBottom - _activeChapterTop;
      if (h > 0) {
        _chapterProgress = ((scrollOffset - _activeChapterTop) / h).clamp(0.0, 1.0);
      }
      return;
    }

    int? bestChapter;
    double minDistance = double.infinity;

    for (int i = 0; i < _chapterKeys.length; i++) {
      final key = _chapterKeys[i];
      final currentCtx = key.currentContext;
      if (currentCtx == null) continue;

      final renderBox = currentCtx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached || !renderBox.hasSize) continue;

      recordChapterHeight(i, renderBox.size.height);
      final position = renderBox.localToGlobal(Offset.zero, ancestor: null);
      final dist = (position.dy - 100).abs();

      if (dist < minDistance) {
        minDistance = dist;
        bestChapter = i;
      }
    }

    if (bestChapter != null && (bestChapter != _currentChapterIndex || force)) {
      final changed = _currentChapterIndex != bestChapter;
      _currentChapterIndex = bestChapter;
      _lastTrackedChapter = bestChapter;
      if (bestChapter < _allChapterContents.length) {
        _currentContent = _allChapterContents[bestChapter];
        _currentPlainText = _allChapterPlainTexts[bestChapter];
        _sentenceSpans = _allChapterSentenceSpans[bestChapter];
      }
      notifyListeners();
      if (changed) {
        _scheduleBackgroundParsing();
      }
    }
  }

  void restoreReadingPosition(ReadingMode mode) {
    if (mode == ReadingMode.verticalContinuous) {
      _restoreContinuousPosition();
    } else {
      endModeTransition();
    }
  }

  void _restoreContinuousPosition({int attempt = 0}) {
    if (!_scrollController.hasClients) {
      endModeTransition();
      return;
    }

    if (attempt == 0) {
      _isRestoringPosition = true;
      _restoreGeneration++;
    }

    final generation = _restoreGeneration;

    final targetOffset = _lastScrollPosition;
    if (targetOffset <= 0) {
      endModeTransition();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_restoreGeneration != generation || !_scrollController.hasClients) {
        endModeTransition();
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, maxExtent);
      _scrollController.jumpTo(clamped);

      if (attempt < 5) {
        _restoreContinuousPosition(attempt: attempt + 1);
      } else {
        endModeTransition();
      }
    });
  }

  void saveReadingPositionForMode(ReadingMode mode, {bool refreshChapter = true}) {
    if (!_scrollController.hasClients && mode == ReadingMode.verticalContinuous) return;

    if (mode == ReadingMode.verticalContinuous && _scrollController.hasClients) {
      _lastScrollPosition = _scrollController.offset;
    }

    repository.updateReadingProgress(
      book.id,
      sectionIndex: _currentChapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: _lastReadingSentenceStart,
      lastReadingSentenceEnd: _lastReadingSentenceEnd,
    );
  }

  int _readingAnchorOffset() {
    return _lastReadingSentenceStart >= 0 ? _lastReadingSentenceStart : 0;
  }

  double _fractionForTextOffset(int chapterIndex, int textOffset) {
    if (chapterIndex < 0 || chapterIndex >= _rawChapterLengths.length) return 0.0;
    final total = _rawChapterLengths[chapterIndex];
    if (total <= 0) return 0.0;
    return (textOffset / total).clamp(0.0, 1.0);
  }

  void setChapterIndex(int index, {bool userInitiated = false}) {
    if (index < 0 || _chapters == null || index >= _chapters!.length) return;
    final changed = _currentChapterIndex != index;
    _currentChapterIndex = index;
    if (index < _allChapterContents.length) {
      _currentContent = _allChapterContents[index];
      _currentPlainText = _allChapterPlainTexts[index];
      _sentenceSpans = _allChapterSentenceSpans[index];
    }
    notifyListeners();
    if (changed) {
      _scheduleBackgroundParsing();
    }
  }

  Future<void> loadChapter(int index, {bool userInitiated = false}) async {
    if (index < 0 || _chapters == null || index >= _chapters!.length) return;
    if (!_parsedCache.containsKey(index)) {
      await ensureChapterParsed(index);
    }
    setChapterIndex(index, userInitiated: userInitiated);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
