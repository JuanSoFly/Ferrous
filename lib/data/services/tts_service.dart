import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:reader_app/core/utils/performance.dart';
import 'package:reader_app/src/rust/api/tts_text.dart';

enum TtsState { stopped, playing, paused }

/// Simplified word position for highlighting
class WordPosition {
  final int start;
  final int end;
  final String word;

  const WordPosition({
    required this.start,
    required this.end,
    required this.word,
  });
}

/// Optimized TTS Service with clean offset tracking.
///
/// Key improvements:
/// - Integrates Rust FFI precomputeTextHighlights for perfect multilingual word segmenting
/// - Chunking splits at natural sentence boundaries
/// - Dynamic-duration fallback word highlighting based on word character length
/// - 500ms startup delay for fallback to avoid double-highlighting jank
class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  late final Future<void> _ready;
  bool _isReady = false;
  VoidCallback? _onFinished;

  TtsState _state = TtsState.stopped;
  TtsState get state => _state;

  // Current word being spoken (relative to chunk)
  int? _wordStart;
  int? _wordEnd;
  String? _word;

  // Chunk tracking
  int _chunkOffset = 0; // Where current chunk starts in full text
  String _fullText = '';
  List<String> _chunks = const [];
  List<int> _chunkOffsets = const [];
  int _chunkIndex = 0;

  bool _disposed = false;
  bool _stopRequested = false;

  // Precomputed Rust highlight data
  TextHighlightData? _highlightData;

  // Getters for current word (absolute offsets)
  int? get currentWordStart =>
      _wordStart != null ? _chunkOffset + _wordStart! : null;
  int? get currentWordEnd => _wordEnd != null ? _chunkOffset + _wordEnd! : null;
  String? get currentWord => _word;
  String get fullText => _fullText;
  
  // Can resume if paused and has chunks to speak
  bool get canResume => _state == TtsState.paused && _chunks.isNotEmpty;

  // Rate control
  double _rate = 0.8;
  double get rate => _rate;

  // Fallback timer for devices where onRangeStart doesn't work
  bool _nativeProgressReceived = false;
  Timer? _fallbackStartTimeout;
  Timer? _fallbackTimer;
  List<WordPosition> _wordPositions = const [];
  int _currentWordIndex = 0;

  // UI debouncing
  Timer? _uiBatchTimer;
  static const _uiBatchInterval = Duration(milliseconds: 16); // One frame at 60fps for smooth highlighting
  bool _pendingNotify = false;

  TtsService() {
    _ready = _init();
  }

  void setOnFinished(VoidCallback? callback) => _onFinished = callback;

  Future<void> _ensureReady() async {
    if (_isReady) return;
    await _ready;
  }

  Future<void> _init() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_engineRate());
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setStartHandler(() {
      _setState(TtsState.playing);
      _startFallbackIfNeeded();
    });

    _flutterTts.setCompletionHandler(() {
      unawaited(_onChunkComplete());
    });

    _flutterTts.setCancelHandler(() {
      _stopFallback();
      _clear();
      _setState(TtsState.stopped);
    });

    _flutterTts.setPauseHandler(() {
      _stopFallback();
      _setState(TtsState.paused);
    });

    _flutterTts.setContinueHandler(() {
      _resumeFallback();
      _setState(TtsState.playing);
    });

    _flutterTts.setErrorHandler((_) {
      _stopFallback();
      _clear();
      _setState(TtsState.stopped);
    });

    _flutterTts
        .setProgressHandler((String text, int start, int end, String word) {
      if (_disposed) return;

      // Native progress is working - disable fallback
      if (!_nativeProgressReceived) {
        _nativeProgressReceived = true;
        _stopFallback();
        debugPrint('TTS: Native progress working');
      }

      _wordStart = start;
      _wordEnd = end;
      _word = word;
      _scheduleNotify();
    });

    _isReady = true;
  }

  void _setState(TtsState next) {
    if (_disposed || _state == next) return;
    _state = next;
    notifyListeners();
  }

  void _clear() {
    _chunks = const [];
    _chunkOffsets = const [];
    _chunkIndex = 0;
    _chunkOffset = 0;
    _fullText = '';
    _wordStart = null;
    _wordEnd = null;
    _word = null;
    _wordPositions = const [];
    _currentWordIndex = 0;
    _highlightData = null;
    _cancelBatchTimer();
  }

  // Engine rate: flutter_tts uses 0.0-1.0 range where 0.5 = normal
  double _engineRate() => 0.5 * _rate;

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 4.0);
    notifyListeners(); // Notify immediately for UI update
    await _ensureReady();
    await _flutterTts.setSpeechRate(_engineRate());

    // Restart fallback timer with new rate
    if (!_nativeProgressReceived && _state == TtsState.playing) {
      _stopFallback();
      _startFallbackIfNeeded();
    }
  }

  // --- Fallback Timer ---

  void _startFallbackIfNeeded() {
    if (_nativeProgressReceived || _wordPositions.isEmpty || _disposed) return;

    _stopFallback();

    // Startup timeout of 500ms to allow native progress to trigger
    _fallbackStartTimeout = Timer(const Duration(milliseconds: 500), () {
      if (_nativeProgressReceived || _disposed || _stopRequested) return;
      debugPrint('TTS: Native progress not received, starting dynamic fallback loop');
      _runFallbackLoop();
    });
  }

  void _runFallbackLoop() {
    if (_disposed || _stopRequested || _currentWordIndex >= _wordPositions.length) {
      _stopFallback();
      return;
    }

    final pos = _wordPositions[_currentWordIndex];
    _wordStart = pos.start;
    _wordEnd = pos.end;
    _word = pos.word;
    _currentWordIndex++;
    _scheduleNotify();

    // Dynamic timing calculation: duration = (baseMs + (charCount * msPerChar)) / rate
    const baseMs = 150.0;
    const msPerChar = 70.0;
    final scale = 1.0 / _rate;
    final wordDurationMs = ((baseMs + (pos.word.length * msPerChar)) * scale).round().clamp(100, 3000);

    _fallbackTimer = Timer(Duration(milliseconds: wordDurationMs), _runFallbackLoop);
  }

  void _stopFallback() {
    _fallbackStartTimeout?.cancel();
    _fallbackStartTimeout = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  void _resumeFallback() {
    if (!_nativeProgressReceived && _wordPositions.isNotEmpty) {
      _startFallbackIfNeeded();
    }
  }

  // --- UI Debouncing ---

  void _scheduleNotify() {
    if (_pendingNotify) return;
    _pendingNotify = true;

    _uiBatchTimer ??= Timer(_uiBatchInterval, () {
      _uiBatchTimer = null;
      _pendingNotify = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _cancelBatchTimer() {
    _uiBatchTimer?.cancel();
    _uiBatchTimer = null;
    _pendingNotify = false;
  }

  // --- Text Splitting ---

  Future<int> _maxChunkSize() async {
    try {
      final max = await _flutterTts.getMaxSpeechInputLength;
      if (max != null && max > 100) return max - 50;
    } catch (_) {}
    return 3500;
  }

  void _splitTextAndOffsets(String normalized, int maxChars) {
    if (_highlightData == null) {
      _chunks = [normalized];
      _chunkOffsets = [0];
      return;
    }

    final data = _highlightData!;
    if (normalized.length <= maxChars) {
      _chunks = [normalized];
      _chunkOffsets = [0];
      return;
    }

    final chunks = <String>[];
    final offsets = <int>[];
    var currentChunkStart = 0;
    var currentSentenceIndex = 0;

    while (currentSentenceIndex < data.sentences.length) {
      final sentence = data.sentences[currentSentenceIndex];
      final sentenceLength = sentence.end - sentence.start;

      if (sentenceLength > maxChars) {
        // Yield any accumulated text before this sentence
        if (sentence.start > currentChunkStart) {
          final text = normalized.substring(currentChunkStart, sentence.start).trim();
          if (text.isNotEmpty) {
            chunks.add(text);
            offsets.add(currentChunkStart);
          }
        }
        
        // Split the long sentence by words
        final sentenceWords = data.words.where((w) => w.start >= sentence.start && w.end <= sentence.end).toList();
        currentChunkStart = sentence.start;
        
        for (var i = 0; i < sentenceWords.length; i++) {
          final word = sentenceWords[i];
          if (word.end - currentChunkStart > maxChars) {
            final yieldEnd = i > 0 ? sentenceWords[i - 1].end : word.start;
            if (yieldEnd > currentChunkStart) {
              chunks.add(normalized.substring(currentChunkStart, yieldEnd).trim());
              offsets.add(currentChunkStart);
              currentChunkStart = yieldEnd;
            }
          }
        }
        
        // Yield the rest of the sentence
        if (sentence.end > currentChunkStart) {
          chunks.add(normalized.substring(currentChunkStart, sentence.end).trim());
          offsets.add(currentChunkStart);
        }
        
        currentChunkStart = sentence.end;
        currentSentenceIndex++;
        continue;
      }

      // Group sentences together
      var nextSentenceIndex = currentSentenceIndex + 1;
      while (nextSentenceIndex < data.sentences.length &&
             data.sentences[nextSentenceIndex].end - currentChunkStart <= maxChars) {
        nextSentenceIndex = nextSentenceIndex + 1;
      }

      final chunkEnd = data.sentences[nextSentenceIndex - 1].end;
      final text = normalized.substring(currentChunkStart, chunkEnd).trim();
      if (text.isNotEmpty) {
        chunks.add(text);
        offsets.add(currentChunkStart);
      }
      currentChunkStart = chunkEnd;
      currentSentenceIndex = nextSentenceIndex;
    }

    // Add any remaining text
    if (currentChunkStart < normalized.length) {
      final remaining = normalized.substring(currentChunkStart).trim();
      if (remaining.isNotEmpty) {
        chunks.add(remaining);
        offsets.add(currentChunkStart);
      }
    }

    _chunks = chunks;
    _chunkOffsets = offsets;
  }

  void _updateWordPositionsForCurrentChunk() {
    final chunkText = _chunks[_chunkIndex];
    final chunkStart = _chunkOffset;
    
    if (_highlightData != null) {
      final chunkEnd = chunkStart + chunkText.length;
      final spans = _highlightData!.words
          .where((w) => w.start >= chunkStart && w.end <= chunkEnd)
          .toList();
          
      _wordPositions = spans.map((w) => WordPosition(
        start: w.start - chunkStart,
        end: w.end - chunkStart,
        word: w.text,
      )).toList();
    } else {
      _wordPositions = _parseWords(chunkText);
    }
    
    _currentWordIndex = 0;
  }

  List<WordPosition> _parseWords(String text) {
    final words = <WordPosition>[];
    for (final m in RegExp(r'\S+').allMatches(text)) {
      words.add(WordPosition(start: m.start, end: m.end, word: m.group(0)!));
    }
    return words;
  }

  String _normalize(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // --- Public API ---

  Future<void> speak(String text) async {
    await measureAsync('tts_speak', () async {
      await _ensureReady();
      final normalized = _normalize(text);
      if (normalized.isEmpty) return;

      // Stop existing speech (non-blocking)
      _stopFallback();
      if (_state != TtsState.stopped) {
        _stopRequested = true;
        unawaited(_flutterTts.stop());
        await Future.delayed(const Duration(milliseconds: 50));
      }

      _clear();
      _stopRequested = false;
      _nativeProgressReceived = false;

      // Compute word highlights using Rust FFI
      try {
        _highlightData = await precomputeTextHighlights(text: normalized);
        _fullText = _highlightData!.normalizedText;
      } catch (e) {
        debugPrint("TTS: Rust precompute failed: $e");
        _highlightData = null;
        _fullText = normalized;
      }

      final maxChars = await _maxChunkSize();
      _splitTextAndOffsets(_fullText, maxChars);
      _chunkIndex = 0;
      _chunkOffset = _chunkOffsets.isNotEmpty ? _chunkOffsets[0] : 0;

      _updateWordPositionsForCurrentChunk();

      if (_chunks.isEmpty || !await _speakChunk(_chunks[0])) {
        _clear();
        _setState(TtsState.stopped);
        return;
      }

      _setState(TtsState.playing);
    }, metadata: {'text_length': text.length});
  }

  Future<bool> _speakChunk(String chunk) async {
    try {
      final result = await _flutterTts
          .speak(chunk)
          .timeout(const Duration(seconds: 2), onTimeout: () => 0);
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onChunkComplete() async {
    if (_disposed || _stopRequested) return;

    _chunkIndex++;
    if (_chunkIndex >= _chunks.length) {
      // All chunks complete
      _clear();
      _setState(TtsState.stopped);
      _onFinished?.call();
      return;
    }

    // Update chunk offset for next chunk
    _chunkOffset = _chunkOffsets[_chunkIndex];

    _updateWordPositionsForCurrentChunk();
    _nativeProgressReceived = false;

    await _speakChunk(_chunks[_chunkIndex]);
  }

  Future<void> stop() async {
    await _ensureReady();
    _stopRequested = true;
    _stopFallback();
    _clear();
    _setState(TtsState.stopped);
    unawaited(_flutterTts.stop());
  }

  Future<void> pause() async {
    await _ensureReady();
    if (_state != TtsState.playing) return;
    _stopFallback();
    _setState(TtsState.paused);
    unawaited(_flutterTts.pause());
  }

  Future<void> resume() async {
    await _ensureReady();
    if (_state != TtsState.paused) return;
    _stopRequested = false;

    // Slice current chunk at paused word index
    if (_chunkIndex >= 0 && _chunkIndex < _chunks.length) {
      final currentChunk = _chunks[_chunkIndex];
      final pauseOffset = _wordStart ?? 0;
      
      if (pauseOffset > 0 && pauseOffset < currentChunk.length) {
        final remainingText = currentChunk.substring(pauseOffset);
        _chunkOffset += pauseOffset;
        
        final updatedChunks = List<String>.from(_chunks);
        updatedChunks[_chunkIndex] = remainingText;
        _chunks = updatedChunks;
        
        _updateWordPositionsForCurrentChunk();
      }
    }

    _nativeProgressReceived = false;
    _setState(TtsState.playing);
    
    // Speak remaining chunk
    if (_chunks.isNotEmpty && _chunkIndex < _chunks.length) {
      await _speakChunk(_chunks[_chunkIndex]);
    } else {
      _setState(TtsState.stopped);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopFallback();
    _cancelBatchTimer();
    unawaited(_flutterTts.stop());
    super.dispose();
  }
}
