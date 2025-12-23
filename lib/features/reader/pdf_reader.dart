import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/crop.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:reader_app/features/reader/pdf_text_picker_sheet.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/utils/sentence_utils.dart';
import 'package:reader_app/utils/normalized_text_map.dart';
import 'package:reader_app/utils/text_normalization.dart';

// Text normalization utilities imported from shared lib/utils/

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const PdfReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with WidgetsBindingObserver {
  final GlobalKey _pageImageKey = GlobalKey();
  final TransformationController _pdfTransformController =
      TransformationController();
  Uint8List? _currentPageImage;
  bool _isLoading = true;
  String? _error;
  int _pageIndex = 0;
  int _pageCount = 0;
  bool _autoCrop = false;
  final Map<int, CropMargins> _marginsCache = {};
  Size _renderedPageSize = Size.zero;
  Size _viewerSize = Size.zero;
  bool _showChrome = false;
  bool _lockMode = false;
  Offset? _lastDoubleTapDown;
  late ReadingMode _readingMode;

  // TTS
  final TtsService _ttsService = TtsService();
  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;
  int _ttsAdvanceRequestId = 0;
  String? _ttsStartOverrideText;
  final Map<int, String> _pageTextCache = {};
  final Map<int, Future<String>> _pageTextInFlight = {};
  // Pre-computed character bounds for TTS highlighting (eliminates per-word FFI)
  final Map<int, List<PdfTextRect>> _pageCharBoundsCache = {};
  String _currentPageText = '';
  NormalizedTextMap? _pageTextMap;
  List<SentenceSpan> _pageSentenceSpans = const [];
  int _ttsNormalizedBaseOffset = 0;
  List<PdfTextRect> _ttsHighlightRects = const [];
  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  DateTime _lastAutoPanAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _highlightRequestId = 0;
  bool _isTextLoading = false;
  bool _isTapToStartLoading = false;
  String? _textError;
  int _textRequestId = 0;
  int _tapToStartRequestId = 0;
  ResolvedBookFile? _resolvedFile;
  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;
  late int _lastTtsPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ttsService.setOnFinished(_handleTtsFinished);
    _ttsService.addListener(_handleTtsProgress);
    _pageIndex = widget.book.currentPage;
    _lastTtsSentenceStart = widget.book.lastTtsSentenceStart;
    _lastTtsSentenceEnd = widget.book.lastTtsSentenceEnd;
    _lastTtsPage = widget.book.lastTtsPage;
    _readingMode = widget.book.readingMode;
    _loadDocument();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSystemUiMode();
    });
  }

  Future<void> _loadDocument() async {
    try {
      final resolver = BookFileResolver();
      final resolved = await resolver.resolve(widget.book);
      _resolvedFile = resolved;
      final count = await getPdfPageCount(path: resolved.path);
      final safeIndex =
          count <= 0 ? 0 : widget.book.currentPage.clamp(0, count - 1);
      setState(() {
        _pageCount = count;
        _pageIndex = safeIndex;
      });
      await _renderPage(safeIndex);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _renderPage(int index, {bool userInitiated = false}) async {
    if (userInitiated) {
      _ttsAdvanceRequestId++;
    }

    final previousIndex = _pageIndex;
    final isPageChanging = index != previousIndex;

    setState(() {
      _isLoading = true;
      _error = null;
      _pageIndex = index;
    });

    if (isPageChanging) {
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
    }

    if (_showTtsControls && isPageChanging) {
      unawaited(_ttsService.stop());
      unawaited(_loadPageText(index));
    } else if (!_showTtsControls) {
      setState(() {
        _currentPageText = _pageTextCache[index] ?? '';
        _isTextLoading = false;
        _textError = null;
      });
    }

    // Save progress
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: index,
      totalPages: _pageCount,
    );

    try {
      // Start margin detection in parallel if auto-crop is on
      if (_autoCrop && !_marginsCache.containsKey(index)) {
        final path = _resolvedFile?.path;
        if (path != null) {
          detectPdfWhitespace(path: path, pageIndex: index).then((margins) {
            if (mounted) {
              setState(() {
                _marginsCache[index] = margins;
              });
            }
          }).catchError((e) {
            debugPrint("Crop error: $e");
          });
        }
      }

      // Render at 2x screen resolution for sharpness
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final width = (screenWidth * 2).toInt();
      final height = (screenHeight * 2).toInt();

      final bytes = await renderPdfPage(
        path: _resolvedFile!.path,
        pageIndex: index,
        width: width,
        height: height,
      );

      setState(() {
        _currentPageImage = bytes;
        _renderedPageSize = Size(width.toDouble(), height.toDouble());
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Render Error: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPageText(int index) async {
    final cached = _pageTextCache[index];
    if (cached != null) {
      setState(() {
        _currentPageText = cached;
        _pageTextMap = buildNormalizedTextMap(cached);
        _pageSentenceSpans = _pageTextMap == null
            ? const []
            : splitIntoSentences(_pageTextMap!.normalized);
        _isTextLoading = false;
        _textError = null;
      });
      return;
    }

    final requestId = ++_textRequestId;
    setState(() {
      _isTextLoading = true;
      _textError = null;
      _currentPageText = '';
    });

    try {
      final future = _pageTextInFlight[index] ??= extractPdfPageText(
        path: _resolvedFile!.path,
        pageIndex: index,
      );
      final text = await future;
      _pageTextInFlight.remove(index);

      if (!mounted || requestId != _textRequestId) return;

      setState(() {
        _pageTextCache[index] = text;
        _currentPageText = text;
        _pageTextMap = buildNormalizedTextMap(text);
        _pageSentenceSpans = _pageTextMap == null
            ? const []
            : splitIntoSentences(_pageTextMap!.normalized);
        _isTextLoading = false;
        _textError = null;
      });

      // Pre-compute character bounds for TTS (non-blocking)
      if (!_pageCharBoundsCache.containsKey(index)) {
        unawaited(_precomputeCharacterBounds(index));
      }
    } catch (e) {
      _pageTextInFlight.remove(index);
      if (!mounted || requestId != _textRequestId) return;
      setState(() {
        _isTextLoading = false;
        _textError = e.toString();
        _currentPageText = '';
        _pageTextMap = null;
        _pageSentenceSpans = const [];
      });
    }
  }

  /// Pre-compute all character bounds for instant TTS highlighting
  Future<void> _precomputeCharacterBounds(int pageIndex) async {
    if (_resolvedFile == null) return;
    try {
      final bounds = await extractAllPageCharacterBounds(
        path: _resolvedFile!.path,
        pageIndex: pageIndex,
      );
      if (!mounted) return;
      _pageCharBoundsCache[pageIndex] = bounds;
    } catch (e) {
      debugPrint('TTS: Failed to precompute bounds for page $pageIndex: $e');
    }
  }

  Future<void> _startTtsFromTap(TapUpDetails details) async {
    if (!_showTtsControls || !_tapToStartEnabled) return;

    final imageContext = _pageImageKey.currentContext;
    if (imageContext == null) return;

    final imageBox = imageContext.findRenderObject();
    if (imageBox is! RenderBox) return;

    final size = imageBox.size;
    if (size.width <= 0 || size.height <= 0) return;

    final local = imageBox.globalToLocal(details.globalPosition);
    final xNormVisible = local.dx / size.width;
    final yNormVisible = local.dy / size.height;

    if (xNormVisible < 0 ||
        xNormVisible > 1 ||
        yNormVisible < 0 ||
        yNormVisible > 1) {
      return;
    }

    var xNorm = xNormVisible;
    var yNorm = yNormVisible;

    if (_autoCrop && _marginsCache.containsKey(_pageIndex)) {
      final margins = _marginsCache[_pageIndex]!;
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;

      if (visibleWidth > 0) {
        xNorm = margins.left + xNormVisible * visibleWidth;
      }
      if (visibleHeight > 0) {
        yNorm = margins.top + yNormVisible * visibleHeight;
      }
    }

    _ttsAdvanceRequestId++;
    await _ttsService.stop();

    final requestId = ++_tapToStartRequestId;
    setState(() {
      _isTapToStartLoading = true;
      _textError = null;
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
    });

    try {
      final text = await extractPdfPageTextFromPoint(
        path: _resolvedFile!.path,
        pageIndex: _pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );

      if (!mounted || requestId != _tapToStartRequestId) return;

      final trimmed = text.trim();
      setState(() {
        _isTapToStartLoading = false;
        _textError = null;
        _ttsStartOverrideText = trimmed.isEmpty ? null : trimmed;
      });

      if (trimmed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No readable text near that spot.')),
        );
        return;
      }

      _setNormalizedBaseOffset(trimmed);
      unawaited(_ttsService.speak(trimmed));
    } catch (e) {
      if (!mounted || requestId != _tapToStartRequestId) return;
      setState(() {
        _isTapToStartLoading = false;
        _textError = e.toString();
        _ttsStartOverrideText = null;
        _ttsHighlightRects = const [];
      });
    }
  }

  void _handleTtsFinished() {
    if (!mounted) return;
    if (!_showTtsControls || !_ttsContinuous) return;
    unawaited(_advanceToNextReadablePageAndSpeak());
  }

  void _handleTtsProgress() {
    if (!mounted) return;
    if (!_showTtsControls || _ttsService.state != TtsState.playing) {
      if (_ttsHighlightRects.isNotEmpty) {
        setState(() => _ttsHighlightRects = const []);
      }
      return;
    }

    if (_pageTextMap == null && !_isTextLoading) {
      unawaited(_loadPageText(_pageIndex));
      return;
    }

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;

    // Calculate absolute position in page text
    final highlightStart = _ttsNormalizedBaseOffset + wordStart;
    final highlightEnd = _ttsNormalizedBaseOffset + wordEnd;

    // Skip if same highlight
    if (highlightStart == _lastHighlightStart &&
        highlightEnd == _lastHighlightEnd) {
      return;
    }

    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;
    unawaited(_updateHighlightForNormalizedRange(highlightStart, highlightEnd));
  }

  Future<void> _advanceToNextReadablePageAndSpeak() async {
    if (_pageCount <= 0) return;

    final startIndex = _pageIndex + 1;
    if (startIndex >= _pageCount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reached end of document.')),
        );
      }
      return;
    }

    final requestId = ++_ttsAdvanceRequestId;

    for (var index = startIndex; index < _pageCount; index++) {
      _ttsStartOverrideText = null;
      await _renderPage(index, userInitiated: false);
      if (!mounted || requestId != _ttsAdvanceRequestId) return;

      await _loadPageText(index);
      if (!mounted || requestId != _ttsAdvanceRequestId) return;

      final text = _currentPageText.trim();
      if (text.isEmpty) {
        continue;
      }

      _setNormalizedBaseOffset(text);
      await _ttsService.speak(text);
      return;
    }

    if (mounted && requestId == _ttsAdvanceRequestId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more readable text found.')),
      );
    }
  }

  Future<void> _updateHighlightForNormalizedRange(
    int normalizedStart,
    int normalizedEnd,
  ) async {
    final map = _pageTextMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;
    if (normalizedStart < 0 || normalizedEnd <= normalizedStart) return;
    if (normalizedStart >= map.normalizedToRaw.length) return;

    final clampedEnd = normalizedEnd.clamp(0, map.normalizedToRaw.length);
    if (clampedEnd <= normalizedStart) return;

    final rawStart = map.normalizedToRaw[normalizedStart];
    final rawEnd = map.normalizedToRaw[clampedEnd - 1] + 1;

    // Use pre-computed bounds cache if available (instant lookup)
    final cachedBounds = _pageCharBoundsCache[_pageIndex];
    if (cachedBounds != null && cachedBounds.isNotEmpty) {
      // Extract only non-empty rects in the range
      final clampedRawEnd = rawEnd.clamp(0, cachedBounds.length);
      final clampedRawStart = rawStart.clamp(0, clampedRawEnd);

      final rects = <PdfTextRect>[];
      for (var i = clampedRawStart; i < clampedRawEnd; i++) {
        final rect = cachedBounds[i];
        // Skip empty placeholder rects (whitespace)
        if (rect.left != 0 ||
            rect.top != 0 ||
            rect.right != 0 ||
            rect.bottom != 0) {
          rects.add(rect);
        }
      }

      setState(() {
        _ttsHighlightRects = rects;
      });
      _maybeAutoPanToHighlight(rects);
      return;
    }

    // Fallback: FFI call if cache miss
    final requestId = ++_highlightRequestId;
    try {
      final rects = await extractPdfPageTextBounds(
        path: _resolvedFile!.path,
        pageIndex: _pageIndex,
        startIndex: rawStart,
        endIndex: rawEnd,
      );

      if (!mounted || requestId != _highlightRequestId) return;
      setState(() {
        _ttsHighlightRects = rects;
      });
      _maybeAutoPanToHighlight(rects);
    } catch (_) {
      if (!mounted || requestId != _highlightRequestId) return;
      setState(() {
        _ttsHighlightRects = const [];
      });
    }
  }

  void _setNormalizedBaseOffset(String ttsText) {
    final map = _pageTextMap;
    if (map == null || map.normalized.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return;
    }

    final normalized = normalizePlainText(ttsText);
    if (normalized.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return;
    }

    final index = map.normalized.indexOf(normalized);
    _ttsNormalizedBaseOffset = index >= 0 ? index : 0;
  }

  void _saveTtsSentenceSpan(SentenceSpan span) {
    _lastTtsSentenceStart = span.start;
    _lastTtsSentenceEnd = span.end;
    _lastTtsPage = _pageIndex;
    unawaited(
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: _pageIndex,
        totalPages: _pageCount,
        lastTtsSentenceStart: span.start,
        lastTtsSentenceEnd: span.end,
        lastTtsPage: _pageIndex,
      ),
    );
  }

  void _saveCurrentTtsSentence() {
    final start = _ttsService.currentWordStart;
    if (start == null) return;
    if (_pageTextMap == null) return;

    final absoluteOffset = _ttsNormalizedBaseOffset + start;
    final span = sentenceForOffset(_pageSentenceSpans, absoluteOffset);
    if (span == null) return;
    _saveTtsSentenceSpan(span);
  }

  String _resolveTtsText() {
    final map = _pageTextMap;
    final text = _currentPageText;
    if (text.trim().isEmpty) return '';

    if (map != null &&
        _lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsPage == _pageIndex) {
      final normalized = map.normalized;
      if (normalized.isNotEmpty) {
        final start = _lastTtsSentenceStart.clamp(0, normalized.length);
        _ttsNormalizedBaseOffset = start;
        return normalized.substring(start);
      }
    }

    final override = _ttsStartOverrideText;
    if (override != null && override.trim().isNotEmpty) {
      _setNormalizedBaseOffset(override);
      return override;
    }

    _setNormalizedBaseOffset(text);
    return text;
  }

  void _maybeAutoPanToHighlight(List<PdfTextRect> rects) {
    if (!_ttsFollowMode) return;
    if (rects.isEmpty) return;
    if (_viewerSize.isEmpty || _renderedPageSize.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoPanAt) < const Duration(milliseconds: 80)) {
      return;
    }

    final bounds = _unionHighlightRects(rects);
    final highlightRect = Rect.fromLTRB(
      bounds.left * _renderedPageSize.width,
      bounds.top * _renderedPageSize.height,
      bounds.right * _renderedPageSize.width,
      bounds.bottom * _renderedPageSize.height,
    );

    final matrix = _pdfTransformController.value;
    Matrix4 inverse;
    try {
      inverse = Matrix4.inverted(matrix);
    } catch (_) {
      return;
    }

    final visibleTopLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final visibleBottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(_viewerSize.width, _viewerSize.height),
    );
    final visibleRect = Rect.fromPoints(visibleTopLeft, visibleBottomRight);

    final scale = matrix.getMaxScaleOnAxis();
    final padding = 32.0 / scale;
    final paddedVisible = visibleRect.deflate(padding);

    if (paddedVisible.contains(highlightRect.topLeft) &&
        paddedVisible.contains(highlightRect.bottomRight)) {
      return;
    }

    final center = highlightRect.center;
    final viewportCenter =
        Offset(_viewerSize.width / 2, _viewerSize.height / 2);
    final translation = Offset(
      viewportCenter.dx - center.dx * scale,
      viewportCenter.dy - center.dy * scale,
    );

    _lastAutoPanAt = now;
    _pdfTransformController.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  PdfTextRect _unionHighlightRects(List<PdfTextRect> rects) {
    var left = rects.first.left;
    var right = rects.first.right;
    var top = rects.first.top;
    var bottom = rects.first.bottom;

    for (final rect in rects.skip(1)) {
      if (rect.left < left) left = rect.left;
      if (rect.right > right) right = rect.right;
      if (rect.top < top) top = rect.top;
      if (rect.bottom > bottom) bottom = rect.bottom;
    }

    return PdfTextRect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
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
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
      unawaited(_ttsService.stop());
      return;
    }

    if (_lastTtsSentenceStart >= 0 &&
        _pageCount > 0 &&
        _lastTtsPage >= 0 &&
        _lastTtsPage < _pageCount &&
        _lastTtsPage != _pageIndex) {
      await _renderPage(_lastTtsPage, userInitiated: false);
    }

    await _loadPageText(_pageIndex);
    if (_lastTtsSentenceStart < 0 && _ttsStartOverrideText == null) {
      unawaited(_primeTtsFromViewport());
    }
  }

  Future<void> _primeTtsFromViewport() async {
    if (_viewerSize.isEmpty || _renderedPageSize.isEmpty) return;
    if (_resolvedFile == null) return;

    final matrix = _pdfTransformController.value;
    Matrix4 inverse;
    try {
      inverse = Matrix4.inverted(matrix);
    } catch (_) {
      return;
    }

    final viewportCenter = Offset(
      _viewerSize.width / 2,
      _viewerSize.height / 2,
    );
    final scenePoint = MatrixUtils.transformPoint(inverse, viewportCenter);

    var xNormVisible = scenePoint.dx / _renderedPageSize.width;
    var yNormVisible = scenePoint.dy / _renderedPageSize.height;
    if (xNormVisible < 0 ||
        xNormVisible > 1 ||
        yNormVisible < 0 ||
        yNormVisible > 1) {
      return;
    }

    var xNorm = xNormVisible;
    var yNorm = yNormVisible;

    if (_autoCrop && _marginsCache.containsKey(_pageIndex)) {
      final margins = _marginsCache[_pageIndex]!;
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;

      if (visibleWidth > 0) {
        xNorm = margins.left + xNormVisible * visibleWidth;
      }
      if (visibleHeight > 0) {
        yNorm = margins.top + yNormVisible * visibleHeight;
      }
    }

    try {
      final text = await extractPdfPageTextFromPoint(
        path: _resolvedFile!.path,
        pageIndex: _pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );

      if (!mounted) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      setState(() {
        _ttsStartOverrideText = trimmed;
      });
      _setNormalizedBaseOffset(trimmed);
    } catch (_) {
      // Ignore probe failures
    }
  }

  void _closeTtsControls() {
    _ttsAdvanceRequestId++;
    _ttsStartOverrideText = null;
    _ttsHighlightRects = const [];
    setState(() => _showTtsControls = false);
    _updateSystemUiMode();
  }

  void _openTextPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return PdfTextPickerSheet(
          pageIndex: _pageIndex,
          pageCount: _pageCount <= 0 ? 1 : _pageCount,
          loadText: () async {
            await _loadPageText(_pageIndex);
            return _pageTextCache[_pageIndex] ?? '';
          },
          onListenFromHere: (text) {
            final trimmed = text.trim();
            if (trimmed.isEmpty) return;

            _ttsAdvanceRequestId++;
            setState(() {
              _showTtsControls = true;
              _ttsStartOverrideText = trimmed;
              _ttsHighlightRects = const [];
            });

            _setNormalizedBaseOffset(trimmed);
            unawaited(_ttsService.speak(trimmed));
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _cleanupTempFile();
    _ttsService.setOnFinished(null);
    _ttsService.removeListener(_handleTtsProgress);
    _ttsService.dispose();
    _pdfTransformController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(
        widget.repository.updateReadingProgress(
          widget.book.id,
          currentPage: _pageIndex,
          totalPages: _pageCount,
        ),
      );
      _saveCurrentTtsSentence();
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

  void _handleTapUp(TapUpDetails details) {
    if (_isCenterTap(details.globalPosition)) {
      _toggleChrome();
      return;
    }
    if (_lockMode) return;
    _startTtsFromTap(details);
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

  bool get _useHorizontalSwipe =>
      _readingMode == ReadingMode.leftToRight ||
      _readingMode == ReadingMode.horizontalContinuous;

  bool get _useVerticalSwipe =>
      _readingMode == ReadingMode.vertical ||
      _readingMode == ReadingMode.verticalContinuous ||
      _readingMode == ReadingMode.webtoon;

  bool _canSwipePages() {
    final scale = _pdfTransformController.value.getMaxScaleOnAxis();
    return (scale - 1.0).abs() < 0.01;
  }

  void _swipeToPage(int delta) {
    final next = _pageIndex + delta;
    if (next < 0 || next >= _pageCount) return;
    unawaited(_renderPage(next, userInitiated: true));
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_useHorizontalSwipe || !_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    // Positive velocity = swipe right = go to previous page
    // Negative velocity = swipe left = go to next page
    if (velocity > 0) {
      _swipeToPage(-1);
    } else {
      _swipeToPage(1);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_useVerticalSwipe || !_canSwipePages()) return;
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 220) return;
    // Positive velocity = swipe down = go to previous page
    // Negative velocity = swipe up = go to next page
    if (velocity > 0) {
      _swipeToPage(-1);
    } else {
      _swipeToPage(1);
    }
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.pdf,
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

  @override
  Widget build(BuildContext context) {
    final ttsEmptyMessage = _textError != null
        ? 'Unable to extract readable text for this page.'
        : 'No readable text on this page.';

    final showChrome = _showChrome && !_lockMode;
    final showTtsControls = showChrome && _showTtsControls;
    final showBottomControls = showChrome && !_showTtsControls;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
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
                  textToSpeak: _currentPageText,
                  resolveTextToSpeak: _resolveTtsText,
                  isTextLoading: _isTextLoading || _isTapToStartLoading,
                  emptyTextMessage: ttsEmptyMessage,
                  isContinuous: _ttsContinuous,
                  onContinuousChanged: (value) {
                    _ttsAdvanceRequestId++;
                    setState(() => _ttsContinuous = value);
                  },
                  isFollowMode: _ttsFollowMode,
                  onFollowModeChanged: (value) {
                    setState(() => _ttsFollowMode = value);
                  },
                  isTapToStart: _tapToStartEnabled,
                  onTapToStartChanged: (value) {
                    setState(() => _tapToStartEnabled = value);
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

    if (_isLoading && _currentPageImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentPageImage != null) {
      Widget imageWidget = Image.memory(
        _currentPageImage!,
        fit: BoxFit.contain,
      );

      Widget pageLayer;
      if (_renderedPageSize.isEmpty) {
        pageLayer = imageWidget;
      } else {
        pageLayer = SizedBox(
          width: _renderedPageSize.width,
          height: _renderedPageSize.height,
          child: Stack(
            children: [
              Positioned.fill(child: imageWidget),
              if (_showTtsControls &&
                  _ttsService.state == TtsState.playing &&
                  _ttsHighlightRects.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PdfHighlightPainter(
                        rects: _ttsHighlightRects,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.65),
                        borderColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }

      if (_autoCrop && _marginsCache.containsKey(_pageIndex)) {
        final margins = _marginsCache[_pageIndex]!;
        // Use FittedBox + ClipRect to zoom into the cropped area
        pageLayer = FittedBox(
          fit: BoxFit.contain,
          child: ClipRect(
            clipper: MarginClipper(margins),
            child: pageLayer,
          ),
        );
      }

      // No animation - instant page switch to avoid flashing
      final animatedPage = KeyedSubtree(
        key: ValueKey(_pageIndex),
        child: RepaintBoundary(
          key: _pageImageKey,
          child: pageLayer,
        ),
      );

      final pdfViewer = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _handleTapUp,
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
            return InteractiveViewer(
              transformationController: _pdfTransformController,
              maxScale: 5.0,
              child: Center(
                child: animatedPage,
              ),
            );
          },
        ),
      );

      return pdfViewer;
    }

    return const Center(child: Text("Initializing..."));
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
                  icon: const Icon(Icons.text_snippet),
                  tooltip: 'Text view',
                  onPressed: _openTextPicker,
                ),
                IconButton(
                  icon: Icon(_autoCrop ? Icons.crop : Icons.crop_free),
                  tooltip: _autoCrop ? 'Disable Auto-Crop' : 'Enable Auto-Crop',
                  onPressed: () {
                    setState(() {
                      _autoCrop = !_autoCrop;
                      if (_autoCrop && !_marginsCache.containsKey(_pageIndex)) {
                        _renderPage(_pageIndex);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildControls() {
    if (_pageCount <= 1) return null;

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
                icon: const Icon(Icons.first_page),
                onPressed: _pageIndex > 0
                    ? () => _renderPage(0, userInitiated: true)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _pageIndex > 0
                    ? () => _renderPage(_pageIndex - 1, userInitiated: true)
                    : null,
              ),
              Text("${_pageIndex + 1} / $_pageCount"),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _pageIndex < _pageCount - 1
                    ? () => _renderPage(_pageIndex + 1, userInitiated: true)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _pageIndex < _pageCount - 1
                    ? () => _renderPage(_pageCount - 1, userInitiated: true)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarginClipper extends CustomClipper<Rect> {
  final CropMargins margins;

  MarginClipper(this.margins);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      size.width * margins.left,
      size.height * margins.top,
      size.width * (1.0 - margins.left - margins.right),
      size.height * (1.0 - margins.top - margins.bottom),
    );
  }

  @override
  bool shouldReclip(covariant MarginClipper oldClipper) {
    return margins.top != oldClipper.margins.top ||
        margins.bottom != oldClipper.margins.bottom ||
        margins.left != oldClipper.margins.left ||
        margins.right != oldClipper.margins.right;
  }
}

class _PdfHighlightPainter extends CustomPainter {
  final List<PdfTextRect> rects;
  final Color fillColor;
  final Color borderColor;

  _PdfHighlightPainter({
    required this.rects,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || size.isEmpty) return;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final rect in rects) {
      final left = (rect.left * size.width).clamp(0.0, size.width);
      final right = (rect.right * size.width).clamp(0.0, size.width);
      final top = (rect.top * size.height).clamp(0.0, size.height);
      final bottom = (rect.bottom * size.height).clamp(0.0, size.height);

      if (right <= left || bottom <= top) continue;

      final highlightRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, bottom),
        const Radius.circular(3),
      );
      canvas.drawRRect(highlightRect, fillPaint);
      canvas.drawRRect(highlightRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PdfHighlightPainter oldDelegate) {
    return oldDelegate.rects != rects ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }
}
