import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/src/rust/api/crop.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/features/reader/tts_controls_sheet.dart';
import 'package:reader_app/features/reader/pdf_text_picker_sheet.dart';

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

String _normalizePlainText(String text) {
  return text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u200B', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

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

class _PdfReaderScreenState extends State<PdfReaderScreen> {
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
  String _currentPageText = '';
  _NormalizedTextMap? _pageTextMap;
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

  @override
  void initState() {
    super.initState();
    _ttsService.setOnFinished(_handleTtsFinished);
    _ttsService.addListener(_handleTtsProgress);
    _pageIndex = widget.book.currentPage;
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final count = await getPdfPageCount(path: widget.book.path);
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
        detectPdfWhitespace(path: widget.book.path, pageIndex: index)
            .then((margins) {
          if (mounted) {
            setState(() {
              _marginsCache[index] = margins;
            });
          }
        }).catchError((e) {
          debugPrint("Crop error: $e");
        });
      }

      // Render at 2x screen resolution for sharpness
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final width = (screenWidth * 2).toInt();
      final height = (screenHeight * 2).toInt();

      final bytes = await renderPdfPage(
        path: widget.book.path,
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
        _pageTextMap = _buildNormalizedTextMap(cached);
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
        path: widget.book.path,
        pageIndex: index,
      );
      final text = await future;
      _pageTextInFlight.remove(index);

      if (!mounted || requestId != _textRequestId) return;

      setState(() {
        _pageTextCache[index] = text;
        _currentPageText = text;
        _pageTextMap = _buildNormalizedTextMap(text);
        _isTextLoading = false;
        _textError = null;
      });
    } catch (e) {
      _pageTextInFlight.remove(index);
      if (!mounted || requestId != _textRequestId) return;
      setState(() {
        _isTextLoading = false;
        _textError = e.toString();
        _currentPageText = '';
        _pageTextMap = null;
      });
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
        path: widget.book.path,
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

    final start = _ttsService.currentStartOffset;
    final end = _ttsService.currentEndOffset;
    if (start == null || end == null) return;
    if (start == _lastHighlightStart && end == _lastHighlightEnd) return;

    _lastHighlightStart = start;
    _lastHighlightEnd = end;
    unawaited(_updateHighlightForRange(start, end));
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

  Future<void> _updateHighlightForRange(int start, int end) async {
    final map = _pageTextMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;

    final normalizedStart = _ttsNormalizedBaseOffset + start;
    final normalizedEnd = _ttsNormalizedBaseOffset + end;
    if (normalizedStart < 0 || normalizedEnd <= normalizedStart) return;
    if (normalizedStart >= map.normalizedToRaw.length) return;

    final clampedEnd =
        normalizedEnd.clamp(0, map.normalizedToRaw.length) as int;
    if (clampedEnd <= normalizedStart) return;

    final rawStart = map.normalizedToRaw[normalizedStart];
    final rawEnd = map.normalizedToRaw[clampedEnd - 1] + 1;

    final requestId = ++_highlightRequestId;
    try {
      final rects = await extractPdfPageTextBounds(
        path: widget.book.path,
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

    final normalized = _normalizePlainText(ttsText);
    if (normalized.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return;
    }

    final index = map.normalized.indexOf(normalized);
    _ttsNormalizedBaseOffset = index >= 0 ? index : 0;
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
      ..translate(translation.dx, translation.dy)
      ..scale(scale);
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

  void _toggleTts() {
    setState(() {
      _showTtsControls = !_showTtsControls;
    });

    if (_showTtsControls) {
      unawaited(_loadPageText(_pageIndex));
    } else {
      _ttsAdvanceRequestId++;
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
      unawaited(_ttsService.stop());
    }
  }

  void _closeTtsControls() {
    _ttsAdvanceRequestId++;
    _ttsStartOverrideText = null;
    _ttsHighlightRects = const [];
    setState(() => _showTtsControls = false);
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
    _ttsService.setOnFinished(null);
    _ttsService.removeListener(_handleTtsProgress);
    _ttsService.dispose();
    _pdfTransformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ttsEmptyMessage = _textError != null
        ? 'Unable to extract readable text for this page.'
        : 'No readable text on this page.';

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
            icon: const Icon(Icons.text_snippet),
            onPressed: _openTextPicker,
            tooltip: 'Text view',
          ),
          IconButton(
            icon: Icon(_autoCrop ? Icons.crop : Icons.crop_free),
            tooltip: _autoCrop ? "Disable Auto-Crop" : "Enable Auto-Crop",
            onPressed: () {
              setState(() {
                _autoCrop = !_autoCrop;
                if (_autoCrop && !_marginsCache.containsKey(_pageIndex)) {
                  // Trigger reload to fetch margins
                  _renderPage(_pageIndex);
                }
              });
            },
          ),
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("${_pageIndex + 1} / $_pageCount"),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_showTtsControls)
            TtsControlsSheet(
              ttsService: _ttsService,
              textToSpeak: _currentPageText,
              resolveTextToSpeak: () {
                final text = _ttsStartOverrideText ?? _currentPageText;
                _setNormalizedBaseOffset(text);
                return text;
              },
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
              onClose: _closeTtsControls,
            ),
        ],
      ),
      bottomNavigationBar: _buildControls(),
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
                            .withOpacity(0.65),
                        borderColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.9),
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

      final pdfViewer = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _startTtsFromTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
            return InteractiveViewer(
              transformationController: _pdfTransformController,
              maxScale: 5.0,
              child: Center(
                child: RepaintBoundary(
                  key: _pageImageKey,
                  child: pageLayer,
                ),
              ),
            );
          },
        ),
      );

      return pdfViewer;
    }

    return const Center(child: Text("Initializing..."));
  }

  Widget? _buildControls() {
    if (_pageCount <= 1) return null;

    return BottomAppBar(
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
