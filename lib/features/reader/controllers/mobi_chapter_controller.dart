import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/core/utils/performance.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';
import 'package:reader_app/core/utils/html_defragmenter.dart';
import 'package:reader_app/src/rust/api/covers.dart' as covers_api;
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;
import 'package:reader_app/core/services/diagnostic_logger.dart';
import 'package:reader_app/core/utils/dom_chunker.dart';

class MobiChapterInfo {
  final String? title;
  MobiChapterInfo({this.title});
  // ignore: non_constant_identifier_names
  String? get Title => title;
}

class ParsedMobiBook {
  final List<MobiChapterInfo> chapters;
  final List<String> contents;
  final List<String> plainTexts;
  final List<List<SentenceSpan>> sentenceSpans;
  final List<List<String>> chapterChunks;
  final List<List<int>> chapterChunkOffsets;

  ParsedMobiBook({
    required this.chapters,
    required this.contents,
    required this.plainTexts,
    required this.sentenceSpans,
    this.chapterChunks = const [],
    this.chapterChunkOffsets = const [],
  });
}

class MobiChapterController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  MobiChapterController({
    required this.book,
    required this.repository,
  }) : _scrollController = ScrollController(
         initialScrollOffset: (book.readingMode == ReadingMode.verticalContinuous &&
                 book.scrollPosition.isFinite &&
                 book.scrollPosition > 0)
             ? book.scrollPosition
             : 0.0,
       );

  List<MobiChapterInfo>? _chapters;
  List<String> _allChapterContents = const [];
  List<String> _allChapterPlainTexts = const [];
  List<List<SentenceSpan>> _allChapterSentenceSpans = const [];
  List<List<String>> _allChapterChunks = const [];
  List<List<int>> _allChapterChunkOffsets = const [];
  List<GlobalKey> _chapterKeys = const [];
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
  final Map<int, ScrollController> _chapterScrollControllers = {};
  final Map<int, double> _chapterScrollOffsets = {};
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

  // Trackers from book model
  late int _lastReadingSentenceStart;
  late int _lastReadingSentenceEnd;
  late double _lastScrollPosition;

  // Getters
  List<MobiChapterInfo>? get chapters => _chapters;
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

  void init() {
    _currentChapterIndex = book.sectionIndex;
    _lastReadingSentenceStart = book.lastReadingSentenceStart;
    _lastReadingSentenceEnd = book.lastReadingSentenceEnd;
    _lastScrollPosition = book.scrollPosition;
    _chapterProgress = 0.0;
    unawaited(loadMobi());
  }

  Future<void> loadMobi() async {
    await measureAsync('mobi_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;
        
        // Fetch chapters from Rust backend
        final rustChapters = await rust_mobi.getMobiChapters(path: resolved.path);

        // Lazily heal author/title in database if book was imported with defaults
        if (book.author == 'Unknown Author' || book.title.isEmpty) {
          try {
            final realTitle = await rust_mobi.getMobiTitle(path: resolved.path);
            final realAuthor = await rust_mobi.getMobiAuthor(path: resolved.path);
            final updatedTitle = (realTitle.isNotEmpty && realTitle != 'Unknown Title') ? realTitle : book.title;
            final updatedAuthor = (realAuthor.isNotEmpty && realAuthor != 'Unknown Author') ? realAuthor : book.author;
            if (updatedTitle != book.title || updatedAuthor != book.author) {
              await repository.updateBook(book.copyWith(title: updatedTitle, author: updatedAuthor));
            }
          } catch (_) {}
        }

        // If the book does not have an existing cover file, extract in background
        final currentCover = book.coverPath;
        if (currentCover == null || currentCover.isEmpty || !File(currentCover).existsSync()) {
          unawaited(() async {
            try {
              final appDir = await getApplicationDocumentsDirectory();
              final coversDir = Directory('${appDir.path}/covers');
              if (!await coversDir.exists()) {
                await coversDir.create(recursive: true);
              }
              final coverPath = '${coversDir.path}/${book.id}.png';
              await covers_api.extractCover(bookPath: resolved.path, savePath: coverPath);
              if (await File(coverPath).exists()) {
                await repository.updateCoverPath(book.id, coverPath);
                notifyListeners();
              }
            } catch (_) {}
          }());
        }

        if (rustChapters.isEmpty) {
          DiagnosticLogger.instance.log('MOBI', 'No sections found in MOBI', level: LogLevel.error);
          _error = "No sections found in MOBI";
          _isLoading = false;
          notifyListeners();
          return;
        }

        // Run CPU-intensive HTML/sentence parsing in isolate
        final parsedBook = await compute(_parseMobiIsolated, rustChapters);

        final allKeys = List.generate(parsedBook.chapters.length, (_) => GlobalKey());

        if (_currentChapterIndex >= parsedBook.chapters.length) {
          _currentChapterIndex = 0;
        }

        _chapters = parsedBook.chapters;
        _allChapterContents = parsedBook.contents;
        _allChapterPlainTexts = parsedBook.plainTexts;
        _allChapterSentenceSpans = parsedBook.sentenceSpans;
        _allChapterChunks = parsedBook.chapterChunks;
        _allChapterChunkOffsets = parsedBook.chapterChunkOffsets;
        _chapterKeys = allKeys;
        _currentContent = parsedBook.contents[_currentChapterIndex];
        _currentPlainText = parsedBook.plainTexts[_currentChapterIndex];
        _sentenceSpans = parsedBook.sentenceSpans[_currentChapterIndex];
        final anchor = _readingAnchorOffset();
        _chapterProgress = anchor >= 0 ? _fractionForTextOffset(_currentChapterIndex, anchor) : 0.0;
        _isLoading = false;
        notifyListeners();
      } catch (e, stack) {
        DiagnosticLogger.instance.logError('MOBI', e, stack);
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  static ParsedMobiBook _parseMobiIsolated(List<rust_mobi.MobiChapter> rawChapters) {
    final chapters = <MobiChapterInfo>[];
    final contents = <String>[];
    final plainTexts = <String>[];
    final sentenceSpans = <List<SentenceSpan>>[];
    final chapterChunks = <List<String>>[];
    final chapterChunkOffsets = <List<int>>[];
    String? previousContent;

    for (var i = 0; i < rawChapters.length; i++) {
      final rawChapter = rawChapters[i];
      var title = rawChapter.title.trim();
      final content = rawChapter.htmlContent;
      final trimmed = content.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == previousContent) continue;
      previousContent = trimmed;
      
      final doc = html_parser.parse(content);
      HtmlDefragmenter.defragmentDocument(doc);
      if (title.isEmpty) {
        final heading = doc.querySelector('h1, h2, h3, h4, title')?.text.trim();
        if (heading != null && heading.isNotEmpty) {
          title = heading;
        } else {
          title = 'Section ${i + 1}';
        }
      }

      final plainText = DomTextUtils.extractPlainText(doc.body ?? doc.documentElement);
      final spans = splitIntoSentences(plainText);
      final defragmentedHtml = doc.body?.innerHtml ?? content;
      final contentWithIndent = HyphenationHelper.injectIndentTags(defragmentedHtml);

      // DOM-Level Chunking to keep GPU textures bounded (<4,096px)
      final chunkResult = DomChunker.split(contentWithIndent);

      chapters.add(MobiChapterInfo(title: title));
      contents.add(contentWithIndent);
      plainTexts.add(plainText);
      sentenceSpans.add(spans);
      chapterChunks.add(chunkResult.chunks);
      chapterChunkOffsets.add(chunkResult.chunkStartOffsets);
    }

    if (chapters.isEmpty && rawChapters.isNotEmpty) {
      final first = rawChapters.first;
      final doc = html_parser.parse(first.htmlContent);
      HtmlDefragmenter.defragmentDocument(doc);
      final plainText = DomTextUtils.extractPlainText(doc.body ?? doc.documentElement);
      final spans = splitIntoSentences(plainText);
      final defragmentedHtml = doc.body?.innerHtml ?? first.htmlContent;
      final firstWithIndent = HyphenationHelper.injectIndentTags(defragmentedHtml);
      final chunkResult = DomChunker.split(firstWithIndent);
      chapters.add(MobiChapterInfo(title: first.title));
      contents.add(firstWithIndent);
      plainTexts.add(plainText);
      sentenceSpans.add(spans);
      chapterChunks.add(chunkResult.chunks);
      chapterChunkOffsets.add(chunkResult.chunkStartOffsets);
    }

    return ParsedMobiBook(
      chapters: chapters,
      contents: contents,
      plainTexts: plainTexts,
      sentenceSpans: sentenceSpans,
      chapterChunks: chapterChunks,
      chapterChunkOffsets: chapterChunkOffsets,
    );
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

  void setChapterProgress(double progress) {
    _chapterProgress = progress.clamp(0.0, 1.0);
    final span = _sentenceSpanForFraction(_currentChapterIndex, _chapterProgress);
    _lastReadingSentenceStart = span.start;
    _lastReadingSentenceEnd = span.end;
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

  @visibleForTesting
  void setMockChapters({
    required List<String> contents,
    required List<String> plainTexts,
  }) {
    _chapters = List.generate(
      contents.length,
      (i) => MobiChapterInfo(title: 'Chapter ${i + 1}'),
    );
    _allChapterContents = contents;
    _allChapterPlainTexts = plainTexts;
    _allChapterSentenceSpans = List.generate(contents.length, (_) => []);
    _chapterKeys = List.generate(contents.length, (i) => GlobalKey(debugLabel: 'mock-mobi-chapter-$i'));
    _currentContent = contents.isNotEmpty ? contents[_currentChapterIndex.clamp(0, contents.length - 1)] : '';
    _currentPlainText = plainTexts.isNotEmpty ? plainTexts[_currentChapterIndex.clamp(0, plainTexts.length - 1)] : '';
  }

  double estimateScrollOffsetForChapter(int chapterIndex, [double progress = 0.0]) {
    if (chapterIndex <= 0 && progress <= 0.0) return 0.0;

    double totalMeasuredHeight = 0.0;
    int totalMeasuredChars = 0;
    for (final entry in _chapterHeights.entries) {
      final idx = entry.key;
      if (idx >= 0 && idx < _allChapterPlainTexts.length) {
        final chars = _allChapterPlainTexts[idx].length;
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
      final measured = _chapterHeights[i];
      if (measured != null && measured > 0) {
        offset += measured + chapterSpacing;
      } else if (i < _allChapterPlainTexts.length) {
        final chars = _allChapterPlainTexts[i].length;
        offset += (chars * avgPxPerChar) + chapterSpacing;
      } else {
        offset += 2000.0 + chapterSpacing;
      }
    }

    if (progress > 0.0) {
      final currentHeight = _chapterHeights[chapterIndex] ??
          (chapterIndex < _allChapterPlainTexts.length
              ? _allChapterPlainTexts[chapterIndex].length * avgPxPerChar
              : 2000.0);
      offset += currentHeight * progress.clamp(0.0, 1.0);
    }

    return offset;
  }

  void prepareForContinuousMode(int targetChapter, {double? progress}) {
    _isTransitioningMode = true;
    _isRestoringPosition = true;
    _restoreGeneration++;
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
    _isTransitioningMode = true;
    _isRestoringPosition = true;
    _restoreGeneration++;
    _currentChapterIndex = targetChapter;
    if (progress != null) {
      _chapterProgress = progress.clamp(0.0, 1.0);
    }

    final controller = _chapterScrollControllers[targetChapter];
    if (controller != null && controller.hasClients && controller.position.maxScrollExtent > 0) {
      final target = controller.position.maxScrollExtent * _chapterProgress;
      _chapterScrollOffsets[targetChapter] = target;
      controller.jumpTo(target);
    }
  }

  Future<void> loadChapter(int index, {bool userInitiated = false, VoidCallback? onBeforeLoad}) async {
    if (_chapters == null || index < 0 || index >= _chapters!.length) return;
    if (_allChapterContents.isEmpty) return;

    onBeforeLoad?.call();

    _currentChapterIndex = index;
    _currentContent = _allChapterContents[index];
    _currentPlainText = _allChapterPlainTexts[index];
    _sentenceSpans = _allChapterSentenceSpans[index];
    notifyListeners();

    SentenceSpan? resetSpan;
    if (_currentPlainText.trim().isNotEmpty) {
      resetSpan = _sentenceSpans.isNotEmpty
          ? _sentenceSpans.first
          : SentenceSpan(0, _currentPlainText.length);
      _lastReadingSentenceStart = resetSpan.start;
      _lastReadingSentenceEnd = resetSpan.end;
    } else {
      _lastReadingSentenceStart = -1;
      _lastReadingSentenceEnd = -1;
    }

    if (userInitiated) {
      invalidateScrollBounds();
      _chapterProgress = 0.0;
      _chapterScrollOffsets[index] = 0.0;
      final pagedController = _chapterScrollControllers[index];
      if (pagedController != null && pagedController.hasClients) {
        pagedController.jumpTo(0.0);
      }
      prepareForContinuousMode(index, progress: 0.0);
    } else {
      _chapterProgress = 0.0;
      _lastScrollPosition = estimateScrollOffsetForChapter(index, 0.0);
      book.sectionIndex = index;
      book.scrollPosition = _lastScrollPosition;
    }

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: resetSpan?.start ?? -1,
      lastReadingSentenceEnd: resetSpan?.end ?? -1,
    ));

    if (userInitiated && _chapterKeys.isNotEmpty) {
      _scrollToChapter(index);
    }
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

        if (attempt < 25) {
          _scrollToChapter(index, attempt: attempt + 1);
        } else {
          _isProgrammaticScroll = false;
          _currentChapterIndex = index;
          _chapterProgress = 0.0;
          if (index < _allChapterContents.length) {
            _currentContent = _allChapterContents[index];
            _currentPlainText = _allChapterPlainTexts[index];
            _sentenceSpans = _allChapterSentenceSpans[index];
          }
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
    if (!force && now.difference(_lastScrollCheckTime).inMilliseconds < 150) {
      return;
    }
    _lastScrollCheckTime = now;

    if (force) {
      invalidateScrollBounds();
    }

    final viewportTop = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;
    final viewportMiddle = viewportTop + viewportHeight / 2;

    // Fast Path (O(1)): Viewport is still inside the current tracked chapter bounds.
    // Avoids walking the RenderObject tree and avoids localToGlobal coordinate transformations.
    if (_lastTrackedChapter == _currentChapterIndex &&
        _activeChapterBottom > _activeChapterTop &&
        viewportMiddle >= _activeChapterTop &&
        viewportMiddle < _activeChapterBottom) {
      final chapterHeight = _activeChapterBottom - _activeChapterTop;
      final visibleFraction = chapterHeight > 0
          ? ((viewportMiddle - _activeChapterTop) / chapterHeight).clamp(0.0, 1.0)
          : 0.0;
      _chapterProgress = visibleFraction;
      final span = _sentenceSpanForFraction(_currentChapterIndex, visibleFraction);
      _lastReadingSentenceStart = span.start;
      _lastReadingSentenceEnd = span.end;
      _lastScrollPosition = viewportTop;
      book.scrollPosition = _lastScrollPosition;
      book.lastReadingSentenceStart = span.start;
      book.lastReadingSentenceEnd = span.end;
      return;
    }

    // Slow Path: Viewport has scrolled outside previous chapter bounds or bounds are unmeasured.
    int? visibleChapter;
    double visibleFraction = 0.0;

    try {
      final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
      final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
          ? scrollableBox.localToGlobal(Offset.zero).dy
          : 0.0;

      // 1. Check immediate neighbors first: [current, current + 1, current - 1]
      final candidateIndices = <int>[
        _currentChapterIndex,
        _currentChapterIndex + 1,
        _currentChapterIndex - 1,
      ].where((idx) => idx >= 0 && idx < _chapterKeys.length).toList();

      bool found = false;
      for (final i in candidateIndices) {
        final key = _chapterKeys[i];
        final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.attached || !renderBox.hasSize) continue;

        recordChapterHeight(i, renderBox.size.height);

        final position = renderBox.localToGlobal(Offset.zero);
        final chapterTop = (position.dy - scrollableTop) + viewportTop;
        final chapterBottom = chapterTop + renderBox.size.height;

        if (viewportMiddle >= chapterTop && viewportMiddle < chapterBottom) {
          visibleChapter = i;
          if (renderBox.size.height > 0) {
            visibleFraction = ((viewportMiddle - chapterTop) / renderBox.size.height).clamp(0.0, 1.0);
          }
          _activeChapterTop = chapterTop;
          _activeChapterBottom = chapterBottom;
          _lastTrackedChapter = i;
          found = true;
          break;
        }
      }

      // 2. Fallback: Search all mounted chapter keys (e.g., on fast jump or fling)
      if (!found) {
        for (int i = 0; i < _chapterKeys.length; i++) {
          final key = _chapterKeys[i];
          final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox == null || !renderBox.attached || !renderBox.hasSize) continue;

          recordChapterHeight(i, renderBox.size.height);

          final position = renderBox.localToGlobal(Offset.zero);
          final chapterTop = (position.dy - scrollableTop) + viewportTop;
          final chapterBottom = chapterTop + renderBox.size.height;

          if (viewportMiddle >= chapterTop && viewportMiddle < chapterBottom) {
            visibleChapter = i;
            if (renderBox.size.height > 0) {
              visibleFraction = ((viewportMiddle - chapterTop) / renderBox.size.height).clamp(0.0, 1.0);
            }
            _activeChapterTop = chapterTop;
            _activeChapterBottom = chapterBottom;
            _lastTrackedChapter = i;
            break;
          }
          if (chapterTop > viewportMiddle) {
            visibleChapter ??= (i > 0) ? i - 1 : 0;
            break;
          }
          visibleChapter = i;
        }
      }
    } catch (_) {
      return;
    }

    if (visibleChapter != null &&
        visibleChapter >= 0 &&
        visibleChapter < _allChapterContents.length) {
      _chapterProgress = visibleFraction;
      final span = _sentenceSpanForFraction(visibleChapter, visibleFraction);
      _lastReadingSentenceStart = span.start;
      _lastReadingSentenceEnd = span.end;
      _lastScrollPosition = _scrollController.offset;
      book.scrollPosition = _lastScrollPosition;
      book.lastReadingSentenceStart = span.start;
      book.lastReadingSentenceEnd = span.end;

      if (visibleChapter != _currentChapterIndex) {
        _currentChapterIndex = visibleChapter;
        _currentContent = _allChapterContents[visibleChapter];
        _currentPlainText = _allChapterPlainTexts[visibleChapter];
        _sentenceSpans = _allChapterSentenceSpans[visibleChapter];
        notifyListeners();

        unawaited(repository.updateReadingProgress(
          book.id,
          sectionIndex: visibleChapter,
          totalPages: _chapters?.length ?? 0,
          scrollPosition: _lastScrollPosition,
          lastReadingSentenceStart: span.start,
          lastReadingSentenceEnd: span.end,
        ));
      }
    }
  }

  double getChapterScrollOffset(int index) => _chapterScrollOffsets[index] ?? 0.0;

  void setChapterScrollOffset(int index, double offset) {
    _chapterScrollOffsets[index] = offset;
  }

  ScrollController chapterScrollController(int index) {
    final existing = _chapterScrollControllers[index];
    if (existing != null) {
      return existing;
    }
    final initialOffset = _chapterScrollOffsets[index] ?? 0.0;
    final controller = ScrollController(initialScrollOffset: initialOffset);
    controller.addListener(() {
      if (controller.hasClients) {
        _chapterScrollOffsets[index] = controller.offset;
        final maxScroll = controller.position.maxScrollExtent;
        if (maxScroll > 0) {
          recordChapterHeight(index, maxScroll + controller.position.viewportDimension);
          if (index == _currentChapterIndex && !_isTransitioningMode && !_isRestoringPosition) {
            _chapterProgress = (controller.offset / maxScroll).clamp(0.0, 1.0);
            final span = _sentenceSpanForFraction(index, _chapterProgress);
            _lastReadingSentenceStart = span.start;
            _lastReadingSentenceEnd = span.end;
          }
        }
      }
    });
    _chapterScrollControllers[index] = controller;
    return controller;
  }

  void saveReadingPositionForMode(ReadingMode mode, {bool refreshChapter = false, BuildContext? context}) {
    final isPaged = mode == ReadingMode.vertical || mode == ReadingMode.leftToRight;
    if (isPaged) {
      _saveReadingPositionFromPagedController(_currentChapterIndex);
    } else {
      if (refreshChapter && context != null) {
        updateCurrentChapterFromScroll(context, force: true);
      }
      _saveReadingPositionFromScroll();
    }
  }

  void _saveReadingPositionFromScroll() {
    if (_isTransitioningMode || _isRestoringPosition || _isProgrammaticScroll) return;
    if (!_scrollController.hasClients) return;
    if (_currentChapterIndex < 0 || _currentChapterIndex >= _allChapterPlainTexts.length) return;
    
    final text = _allChapterPlainTexts[_currentChapterIndex];
    if (text.trim().isEmpty) return;

    final fraction = _chapterFractionAtViewportAnchor(_currentChapterIndex) ?? 0.0;
    _chapterProgress = fraction;

    final span = _sentenceSpanForFraction(_currentChapterIndex, fraction);
    _lastScrollPosition = _scrollController.offset;
    _lastReadingSentenceStart = span.start;
    _lastReadingSentenceEnd = span.end;
    book.sectionIndex = _currentChapterIndex;
    book.scrollPosition = _lastScrollPosition;
    book.lastReadingSentenceStart = span.start;
    book.lastReadingSentenceEnd = span.end;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: _currentChapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: span.start,
      lastReadingSentenceEnd: span.end,
    ));
  }

  void onNavigatedToCover() {
    _currentChapterIndex = 0;
    _chapterProgress = 0.0;
    _lastReadingSentenceStart = -1;
    _lastReadingSentenceEnd = -1;
    _lastScrollPosition = 0.0;
    book.sectionIndex = 0;
    book.lastReadingSentenceStart = -1;
    book.lastReadingSentenceEnd = -1;
    book.scrollPosition = 0.0;
    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: 0,
      scrollPosition: 0.0,
      lastReadingSentenceStart: -1,
      lastReadingSentenceEnd: -1,
    ));
    notifyListeners();
  }

  void _saveReadingPositionFromPagedController(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return;
    final controller = _chapterScrollControllers[chapterIndex];
    
    double fraction = 0.0;
    if (controller != null && controller.hasClients) {
      final metrics = controller.position;
      recordChapterHeight(chapterIndex, metrics.maxScrollExtent + metrics.viewportDimension);
      if (metrics.maxScrollExtent > 0) {
        fraction = (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);
      }
      final span = _sentenceSpanForFraction(chapterIndex, fraction);
      _lastReadingSentenceStart = span.start;
      _lastReadingSentenceEnd = span.end;
    }

    _currentChapterIndex = chapterIndex;
    _chapterProgress = fraction;

    // Estimate continuous scroll position corresponding to this chapter and fraction
    _lastScrollPosition = estimateScrollOffsetForChapter(chapterIndex, fraction);

    // Keep in-memory book instance synchronized
    book.sectionIndex = chapterIndex;
    book.scrollPosition = _lastScrollPosition;
    book.lastReadingSentenceStart = _lastReadingSentenceStart;
    book.lastReadingSentenceEnd = _lastReadingSentenceEnd;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: _lastReadingSentenceStart,
      lastReadingSentenceEnd: _lastReadingSentenceEnd,
    ));
  }

  double? _chapterFractionAtViewportAnchor(int chapterIndex) {
    if (!_scrollController.hasClients) return null;
    if (chapterIndex < 0 || chapterIndex >= _chapterKeys.length) return null;

    final key = _chapterKeys[chapterIndex];
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize || renderBox.size.height <= 0) {
      return null;
    }

    try {
      final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
      final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
          ? scrollableBox.localToGlobal(Offset.zero).dy
          : 0.0;

      final viewportHeight = _scrollController.position.viewportDimension;
      final anchorY = _scrollController.offset + viewportHeight * 0.5;
      final chapterTop = _scrollController.offset + (renderBox.localToGlobal(Offset.zero).dy - scrollableTop);
      final localY = (anchorY - chapterTop).clamp(0.0, renderBox.size.height);
      return localY / renderBox.size.height;
    } catch (_) {
      return null;
    }
  }

  SentenceSpan _sentenceSpanForFraction(int chapterIndex, double fraction) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return const SentenceSpan(0, 0);
    final text = _allChapterPlainTexts[chapterIndex];
    if (text.trim().isEmpty) return SentenceSpan(0, text.length);
    final maxIndex = text.length - 1;
    final approxIndex = maxIndex <= 0 ? 0 : (fraction * maxIndex).round().clamp(0, maxIndex);
    final spans = _allChapterSentenceSpans[chapterIndex];
    return sentenceForOffset(spans, approxIndex) ?? SentenceSpan(0, text.length);
  }

  void restoreReadingPosition(ReadingMode mode) {
    final isPaged = mode == ReadingMode.vertical || mode == ReadingMode.leftToRight;
    if (isPaged) {
      _restorePagedPosition();
    } else {
      _restoreContinuousPosition();
    }
  }

  void _restoreContinuousPosition({int attempt = 0}) {
    if (!_scrollController.hasClients || _chapterKeys.isEmpty) {
      endModeTransition();
      return;
    }

    if (attempt == 0) {
      _isRestoringPosition = true;
      _restoreGeneration++;
    }

    final generation = _restoreGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_restoreGeneration != generation || !_scrollController.hasClients) {
        _isRestoringPosition = false;
        _isTransitioningMode = false;
        return;
      }

      final chapterIndex = _currentChapterIndex.clamp(0, _chapterKeys.length - 1);
      final fraction = _chapterProgress;

      if (chapterIndex == 0 && _lastReadingSentenceStart < 0 && _lastScrollPosition <= 0) {
        if (_scrollController.hasClients && _scrollController.offset > 0.0) {
          _scrollController.jumpTo(0.0);
        }
        _markRestoringPosition();
        return;
      }

      final key = _chapterKeys[chapterIndex];
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;

      if (renderBox != null && renderBox.attached && renderBox.hasSize && renderBox.size.height > 0) {
        recordChapterHeight(chapterIndex, renderBox.size.height);
        try {
          final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
          final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
              ? scrollableBox.localToGlobal(Offset.zero).dy
              : 0.0;

          final viewportHeight = _scrollController.position.viewportDimension;
          final chapterTop = _scrollController.offset + (renderBox.localToGlobal(Offset.zero).dy - scrollableTop);
          final anchorY = renderBox.size.height * fraction;
          final idealTarget = fraction == 0.0
              ? chapterTop
              : (chapterTop + anchorY - viewportHeight * 0.5);
          final targetOffset = idealTarget.clamp(0.0, _scrollController.position.maxScrollExtent);

          if ((_scrollController.offset - targetOffset).abs() > 1.0) {
            _scrollController.jumpTo(targetOffset);
          }

          _lastScrollPosition = _scrollController.offset;
          book.scrollPosition = _lastScrollPosition;
          _markRestoringPosition();
          return;
        } catch (_) {}
      }

      if (attempt < 25) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final targetOffset = estimateScrollOffsetForChapter(chapterIndex, fraction);
        final targetJump = targetOffset.clamp(0.0, maxExtent);

        if ((_scrollController.offset - targetJump).abs() > 1.0) {
          _scrollController.jumpTo(targetJump);
        }
        _restoreContinuousPosition(attempt: attempt + 1);
      } else {
        _markRestoringPosition();
      }
    });
  }

  void _restorePagedPosition({int attempt = 0}) {
    if (_allChapterContents.isEmpty) {
      endModeTransition();
      return;
    }
    final chapterIndex = _currentChapterIndex.clamp(0, _allChapterContents.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = chapterScrollController(chapterIndex);
      if (!controller.hasClients) {
        if (attempt < 10) {
          _restorePagedPosition(attempt: attempt + 1);
        } else {
          endModeTransition();
        }
        return;
      }

      final anchorOffset = _readingAnchorOffset();
      final fraction = anchorOffset >= 0 ? _fractionForTextOffset(chapterIndex, anchorOffset) : _chapterProgress;
      final viewportHeight = controller.position.viewportDimension;
      final contentHeight = controller.position.maxScrollExtent + viewportHeight;
      recordChapterHeight(chapterIndex, contentHeight);

      final target = fraction == 0.0
          ? 0.0
          : (contentHeight <= 0
              ? 0.0
              : (contentHeight * fraction - viewportHeight * 0.5).clamp(0.0, controller.position.maxScrollExtent));
      
      controller.jumpTo(target);
      _chapterScrollOffsets[chapterIndex] = target;
      _markRestoringPosition();
    });
  }

  int _readingAnchorOffset() {
    if (_lastReadingSentenceStart >= 0) return _lastReadingSentenceStart;
    if (_lastReadingSentenceEnd >= 0) return _lastReadingSentenceEnd;
    return -1;
  }

  double _fractionForTextOffset(int chapterIndex, int offset) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return 0.0;
    final text = _allChapterPlainTexts[chapterIndex];
    if (text.trim().isEmpty) return 0.0;
    final maxIndex = text.length - 1;
    if (maxIndex <= 0) return 0.0;
    return offset.clamp(0, maxIndex) / maxIndex;
  }

  void _markRestoringPosition() {
    _isRestoringPosition = true;
    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_restoreGeneration == generation) {
        _isRestoringPosition = false;
        _isTransitioningMode = false;
        notifyListeners();
      }
    });
  }

  void cleanup() {
    if (_resolvedFile?.isTemp == true) {
      try {
        unawaited(File(_resolvedFile!.path).delete());
      } catch (_) {}
    }
    if (!_scrollController.hasClients) {
      _scrollController.dispose();
    }
    for (final controller in _chapterScrollControllers.values) {
      if (!controller.hasClients) {
        controller.dispose();
      }
    }
    _chapterScrollControllers.clear();
    _chapterScrollOffsets.clear();
    _chapterHeights.clear();
    invalidateScrollBounds();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
