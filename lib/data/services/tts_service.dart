import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { stopped, playing, paused }

/// Word position info for highlighting
class WordPosition {
  final int startOffset;
  final int endOffset;
  final String word;

  const WordPosition({
    required this.startOffset,
    required this.endOffset,
    required this.word,
  });
}

class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  late final Future<void> _ready;
  VoidCallback? _onFinished;

  TtsState _state = TtsState.stopped;
  TtsState get state => _state;

  // Progress tracking for text highlighting
  int? _currentStartOffset;
  int? _currentEndOffset;
  String? _currentWord;
  String _currentFullText = '';
  int _chunkStartOffset = 0; // Tracks cumulative offset for multi-chunk text
  int _chunkResumeOffset = 0; // Offset into current chunk when resuming

  int? get currentStartOffset => _currentStartOffset;
  int? get currentEndOffset => _currentEndOffset;
  String? get currentWord => _currentWord;
  String get currentFullText => _currentFullText;

  // UI-friendly playback rate (shown as "1.0x" etc). This is *not* the same as the
  // platform TTS engine's speech-rate scale.
  double _rate = 1.0;
  double get rate => _rate;

  List<String> _chunks = const [];
  int _chunkIndex = 0;
  bool _disposed = false;
  bool _stopRequested = false;

  // Fallback word estimation for devices where progress handler doesn't work
  bool _nativeProgressReceived = false;
  Timer? _fallbackTimer;
  List<WordPosition> _wordPositions = const [];
  int _currentWordIndex = 0;

  // Estimated words per minute for fallback calculation
  // This should be tuned based on TTS engine speed
  static const double _baseWordsPerMinute = 150.0;

  TtsService() {
    _ready = _init();
  }

  /// Called when `speak()` finishes all queued chunks naturally.
  void setOnFinished(VoidCallback? callback) {
    _onFinished = callback;
  }

  Future<void> _init() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_engineRateFromUiRate(_rate));
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setStartHandler(() {
      _setState(TtsState.playing);
      // Start fallback timer if native progress hasn't been received
      _startFallbackTimerIfNeeded();
    });

    _flutterTts.setCompletionHandler(() {
      unawaited(_handleCompletion());
    });

    _flutterTts.setCancelHandler(() {
      _stopFallbackTimer();
      _clearQueue();
      _setState(TtsState.stopped);
    });

    _flutterTts.setPauseHandler(() {
      _pauseFallbackTimer();
      _setState(TtsState.paused);
    });

    _flutterTts.setContinueHandler(() {
      _resumeFallbackTimer();
      _setState(TtsState.playing);
    });

    _flutterTts.setErrorHandler((_) {
      _stopFallbackTimer();
      _clearQueue();
      _setState(TtsState.stopped);
    });

    _flutterTts
        .setProgressHandler((String text, int start, int end, String word) {
      if (_disposed) return;

      // Mark that native progress is working - disable fallback
      if (!_nativeProgressReceived) {
        _nativeProgressReceived = true;
        _stopFallbackTimer();
        debugPrint('TTS: Native progress handler is working');
      }

      // Adjust offsets relative to the full text (accounting for chunk position)
      _currentStartOffset = _chunkStartOffset + _chunkResumeOffset + start;
      _currentEndOffset = _chunkStartOffset + _chunkResumeOffset + end;
      _currentWord = word;
      notifyListeners();
    });
  }

  void _setState(TtsState next) {
    if (_disposed) return;
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _clearQueue() {
    _chunks = const [];
    _chunkIndex = 0;
    _chunkStartOffset = 0;
    _chunkResumeOffset = 0;
  }

  void _clearProgress() {
    _currentStartOffset = null;
    _currentEndOffset = null;
    _currentWord = null;
    _currentFullText = '';
    _chunkStartOffset = 0;
    _chunkResumeOffset = 0;
    _wordPositions = const [];
    _currentWordIndex = 0;
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Parse text into word positions for fallback highlighting
  List<WordPosition> _parseWordPositions(String text) {
    final positions = <WordPosition>[];
    final wordPattern = RegExp(r'\S+');

    for (final match in wordPattern.allMatches(text)) {
      positions.add(WordPosition(
        startOffset: match.start,
        endOffset: match.end,
        word: match.group(0)!,
      ));
    }

    return positions;
  }

  /// Calculate estimated milliseconds per word based on rate
  int _msPerWord() {
    // At rate 1.0x, use base words per minute
    // Higher rate = faster = less ms per word
    final adjustedWpm = _baseWordsPerMinute * _rate;
    return (60000 / adjustedWpm).round();
  }

  void _startFallbackTimerIfNeeded() {
    // Only use fallback if native progress hasn't been received yet
    if (_nativeProgressReceived) return;
    if (_wordPositions.isEmpty) return;
    if (_disposed || _stopRequested) return;

    final msPerWord = _msPerWord();
    debugPrint('TTS: Starting fallback timer with ${msPerWord}ms per word');

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(Duration(milliseconds: msPerWord), (_) {
      if (_disposed || _stopRequested || _state != TtsState.playing) {
        _stopFallbackTimer();
        return;
      }

      // If native progress started working mid-speech, stop fallback
      if (_nativeProgressReceived) {
        _stopFallbackTimer();
        return;
      }

      _advanceFallbackWord();
    });

    // Immediately show the first word
    if (_currentWordIndex < _wordPositions.length) {
      _updateProgressFromFallback(_wordPositions[_currentWordIndex]);
    }
  }

  void _advanceFallbackWord() {
    if (_wordPositions.isEmpty) return;

    _currentWordIndex++;
    if (_currentWordIndex >= _wordPositions.length) {
      // Reached end of words for this chunk
      _stopFallbackTimer();
      return;
    }

    _updateProgressFromFallback(_wordPositions[_currentWordIndex]);
  }

  void _updateProgressFromFallback(WordPosition pos) {
    _currentStartOffset = _chunkStartOffset + pos.startOffset;
    _currentEndOffset = _chunkStartOffset + pos.endOffset;
    _currentWord = pos.word;
    notifyListeners();
  }

  void _stopFallbackTimer() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  void _pauseFallbackTimer() {
    _stopFallbackTimer();
  }

  void _resumeFallbackTimer() {
    if (!_nativeProgressReceived && _wordPositions.isNotEmpty) {
      _startFallbackTimerIfNeeded();
    }
  }

  Future<int> _maxChunkSize() async {
    try {
      final max = await _flutterTts.getMaxSpeechInputLength;
      if (max != null && max > 0) {
        return max > 100 ? max - 50 : max;
      }
    } catch (_) {}

    return 3500;
  }

  List<String> _splitByWords(String text, int maxChars) {
    if (text.length <= maxChars) return [text];

    final chunks = <String>[];
    var current = StringBuffer();

    void flush() {
      final s = current.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      current = StringBuffer();
    }

    for (final rawWord in text.split(RegExp(r'\s+'))) {
      final word = rawWord.trim();
      if (word.isEmpty) continue;

      if (word.length > maxChars) {
        if (current.length > 0) flush();
        for (var i = 0; i < word.length; i += maxChars) {
          final end = (i + maxChars).clamp(0, word.length);
          chunks.add(word.substring(i, end));
        }
        continue;
      }

      if (current.length == 0) {
        current.write(word);
        continue;
      }

      if (current.length + 1 + word.length <= maxChars) {
        current.write(' ');
        current.write(word);
      } else {
        flush();
        current.write(word);
      }
    }

    if (current.length > 0) flush();
    return chunks;
  }

  Future<bool> _speakChunk(String chunk) async {
    dynamic result;
    try {
      result = await _flutterTts
          .speak(chunk)
          .timeout(const Duration(seconds: 5), onTimeout: () => 0);
    } catch (_) {
      result = 0;
    }

    return result == 1 || result == true;
  }

  Future<void> speak(String text) async {
    await _ready;
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return;

    await stop();
    _stopRequested = false;

    // Reset native progress flag for each new speech
    _nativeProgressReceived = false;

    // Store full text for highlighting
    _currentFullText = normalized;
    _chunkStartOffset = 0;
    _chunkResumeOffset = 0;

    final maxChars = await _maxChunkSize();
    _chunks = _splitByWords(normalized, maxChars);
    _chunkIndex = 0;

    // Parse word positions for fallback highlighting
    _wordPositions = _parseWordPositions(_chunks[_chunkIndex]);
    _currentWordIndex = 0;

    final ok = await _speakChunk(_chunks[_chunkIndex]);
    if (!ok) {
      _clearQueue();
      _clearProgress();
      _setState(TtsState.stopped);
      return;
    }

    _setState(TtsState.playing);
  }

  Future<void> stop() async {
    await _ready;
    _stopRequested = true;
    _stopFallbackTimer();
    _clearQueue();
    _clearProgress();
    _setState(TtsState.stopped);
    await _flutterTts.stop();
  }

  Future<void> pause() async {
    await _ready;
    if (_state != TtsState.playing) return;
    _chunkResumeOffset = _currentChunkOffsetForResume();
    _pauseFallbackTimer();
    _setState(TtsState.paused);
    await _flutterTts.pause();
  }

  Future<void> resume() async {
    await _ready;
    if (_state != TtsState.paused) return;
    if (_chunks.isEmpty || _chunkIndex >= _chunks.length) return;
    _stopRequested = false;

    final ok = await _speakChunk(_chunks[_chunkIndex]);
    if (!ok) {
      _clearQueue();
      _clearProgress();
      _setState(TtsState.stopped);
      return;
    }

    _setState(TtsState.playing);
  }

  bool get canResume => _state == TtsState.paused && _chunks.isNotEmpty;

  Future<void> setRate(double newRate) async {
    await _ready;
    _rate = newRate;
    notifyListeners();
    await _flutterTts.setSpeechRate(_engineRateFromUiRate(_rate));
  }

  double _engineRateFromUiRate(double uiRate) {
    return (uiRate * 0.5).clamp(0.0, 1.0);
  }

  Future<void> _handleCompletion() async {
    if (_disposed) return;
    if (_stopRequested) return;
    if (_state != TtsState.playing) return;

    _stopFallbackTimer();

    if (_chunks.isEmpty) {
      _setState(TtsState.stopped);
      return;
    }

    final nextIndex = _chunkIndex + 1;
    if (nextIndex >= _chunks.length) {
      _clearQueue();
      _clearProgress();
      _setState(TtsState.stopped);
      final callback = _onFinished;
      if (callback != null) {
        scheduleMicrotask(callback);
      }
      return;
    }

    // Update chunk offset for correct progress tracking
    _chunkStartOffset += _chunks[_chunkIndex].length + 1;
    _chunkResumeOffset = 0;

    _chunkIndex = nextIndex;

    // Parse word positions for next chunk
    _wordPositions = _parseWordPositions(_chunks[_chunkIndex]);
    _currentWordIndex = 0;

    final ok = await _speakChunk(_chunks[_chunkIndex]);
    if (!ok) {
      _clearQueue();
      _clearProgress();
      _setState(TtsState.stopped);
    }
  }

  int _currentChunkOffsetForResume() {
    if (_chunks.isEmpty || _chunkIndex >= _chunks.length) return 0;
    final chunkLength = _chunks[_chunkIndex].length;
    final fullOffset =
        _currentEndOffset ?? _currentStartOffset ?? _chunkStartOffset;
    final offsetInChunk = fullOffset - _chunkStartOffset;
    return offsetInChunk.clamp(0, chunkLength);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopFallbackTimer();
    unawaited(_flutterTts.stop());
    super.dispose();
  }
}
