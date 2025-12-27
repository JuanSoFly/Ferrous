import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:reader_app/core/utils/performance.dart';

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

/// Simplified TTS Service with clean offset tracking.
///
/// Key simplifications:
/// - Single offset system: progress offsets are relative to current chunk only
/// - Readers track their own base offset for absolute positioning
/// - Word-level highlighting (not sentence-level)
/// - 50ms debounced UI updates
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
  int _chunkIndex = 0;

  bool _disposed = false;
  bool _stopRequested = false;

  // Getters for current word (absolute offsets)
  int? get currentWordStart =>
      _wordStart != null ? _chunkOffset + _wordStart! : null;
  int? get currentWordEnd => _wordEnd != null ? _chunkOffset + _wordEnd! : null;
  String? get currentWord => _word;
  String get fullText => _fullText;
  
  // Can resume if paused and has chunks to speak
  bool get canResume => _state == TtsState.paused && _chunks.isNotEmpty;

  // Rate control
  double _rate = 1.0;
  double get rate => _rate;

  // Fallback timer for devices where onRangeStart doesn't work
  bool _nativeProgressReceived = false;
  Timer? _fallbackTimer;
  List<WordPosition> _wordPositions = const [];
  int _currentWordIndex = 0;
  static const double _baseWpm = 120.0;

  // UI debouncing
  Timer? _uiBatchTimer;
  static const _uiBatchInterval = Duration(milliseconds: 50);
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
    _chunkIndex = 0;
    _chunkOffset = 0;
    _fullText = '';
    _wordStart = null;
    _wordEnd = null;
    _word = null;
    _wordPositions = const [];
    _currentWordIndex = 0;
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

  int _msPerWord() => (60000 / (_baseWpm * _rate)).round();

  void _startFallbackIfNeeded() {
    if (_nativeProgressReceived || _wordPositions.isEmpty || _disposed) return;

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(Duration(milliseconds: _msPerWord()), (_) {
      if (_disposed ||
          _stopRequested ||
          _currentWordIndex >= _wordPositions.length) {
        _stopFallback();
        return;
      }

      final pos = _wordPositions[_currentWordIndex];
      _wordStart = pos.start;
      _wordEnd = pos.end;
      _word = pos.word;
      _currentWordIndex++;
      _scheduleNotify();
    });
  }

  void _stopFallback() {
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

  List<String> _splitText(String text, int maxChars) {
    if (text.length <= maxChars) return [text];

    final chunks = <String>[];
    final buf = StringBuffer();

    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;

      if (buf.isEmpty) {
        buf.write(word);
      } else if (buf.length + 1 + word.length <= maxChars) {
        buf.write(' ');
        buf.write(word);
      } else {
        chunks.add(buf.toString());
        buf.clear();
        buf.write(word);
      }
    }

    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
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
      _fullText = normalized;

      final maxChars = await _maxChunkSize();
      _chunks = _splitText(normalized, maxChars);
      _chunkIndex = 0;
      _chunkOffset = 0;

      _wordPositions = _parseWords(_chunks[0]);
      _currentWordIndex = 0;

      if (!await _speakChunk(_chunks[0])) {
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
    _chunkOffset += _chunks[_chunkIndex - 1].length + 1;

    // Parse words for fallback
    _wordPositions = _parseWords(_chunks[_chunkIndex]);
    _currentWordIndex = 0;
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
    unawaited(
        _flutterTts.speak('')); // Resume via empty speak triggers continue
    _setState(TtsState.playing);
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
