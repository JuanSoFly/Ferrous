import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { stopped, playing, paused }

class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  late final Future<void> _ready;
  VoidCallback? _onFinished;

  TtsState _state = TtsState.stopped;
  TtsState get state => _state;

  // UI-friendly playback rate (shown as "1.0x" etc). This is *not* the same as the
  // platform TTS engine's speech-rate scale.
  //
  // For flutter_tts on Android, `setSpeechRate()` is commonly treated as:
  //   0.0 = slowest ... 1.0 = fastest.
  //
  // To make "1.0x" feel like a sane default, we map it to an engine rate of ~0.5.
  double _rate = 1.0;
  double get rate => _rate;

  List<String> _chunks = const [];
  int _chunkIndex = 0;
  bool _disposed = false;
  bool _stopRequested = false;

  TtsService() {
    _ready = _init();
  }

  /// Called when `speak()` finishes all queued chunks naturally.
  ///
  /// This is not called for manual `stop()` / cancellation.
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
    });

    _flutterTts.setCompletionHandler(() {
      unawaited(_handleCompletion());
    });

    _flutterTts.setCancelHandler(() {
      _clearQueue();
      _setState(TtsState.stopped);
    });

    _flutterTts.setPauseHandler(() {
      _setState(TtsState.paused);
    });

    _flutterTts.setContinueHandler(() {
      _setState(TtsState.playing);
    });

    _flutterTts.setErrorHandler((_) {
      _clearQueue();
      _setState(TtsState.stopped);
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
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<int> _maxChunkSize() async {
    // Android has a hard max input length (TextToSpeech.getMaxSpeechInputLength).
    // On other platforms this call isn't implemented; fall back to a safe size.
    try {
      final max = await _flutterTts.getMaxSpeechInputLength;
      if (max != null && max > 0) {
        // Leave a bit of headroom for engine quirks.
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
        // Extremely long token (e.g., URL). Split hard to avoid deadlocks.
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
    // Guard against an Android failure mode where invalid input can leave the
    // Future unresolved (e.g., text > max input length).
    dynamic result;
    try {
      result = await _flutterTts
          .speak(chunk)
          .timeout(const Duration(seconds: 5), onTimeout: () => 0);
    } catch (_) {
      result = 0;
    }

    // Android returns 1 on success (0 on failure). Other platforms may return
    // bool/int, so accept common "truthy" values.
    return result == 1 || result == true;
  }

  Future<void> speak(String text) async {
    await _ready;
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return;

    await stop();
    _stopRequested = false;

    final maxChars = await _maxChunkSize();
    _chunks = _splitByWords(normalized, maxChars);
    _chunkIndex = 0;

    final ok = await _speakChunk(_chunks[_chunkIndex]);
    if (!ok) {
      _clearQueue();
      _setState(TtsState.stopped);
      return;
    }

    _setState(TtsState.playing);
  }

  Future<void> stop() async {
    await _ready;
    _stopRequested = true;
    _clearQueue();
    _setState(TtsState.stopped);
    await _flutterTts.stop();
  }

  Future<void> pause() async {
    await _ready;
    _setState(TtsState.paused);
    await _flutterTts.pause();
  }

  Future<void> setRate(double newRate) async {
    await _ready;
    _rate = newRate;
    notifyListeners();
    await _flutterTts.setSpeechRate(_engineRateFromUiRate(_rate));
  }

  double _engineRateFromUiRate(double uiRate) {
    // Map UI multiplier => engine scale (0.0..1.0). Keep within the plugin's
    // expected range, even if callers provide out-of-range values.
    //
    // Examples:
    //   0.5x => 0.25
    //   1.0x => 0.5  (default)
    //   2.0x => 1.0
    return (uiRate * 0.5).clamp(0.0, 1.0);
  }

  Future<void> _handleCompletion() async {
    if (_disposed) return;
    if (_stopRequested) return;
    if (_state != TtsState.playing) return;

    if (_chunks.isEmpty) {
      _setState(TtsState.stopped);
      return;
    }

    final nextIndex = _chunkIndex + 1;
    if (nextIndex >= _chunks.length) {
      _clearQueue();
      _setState(TtsState.stopped);
      final callback = _onFinished;
      if (callback != null) {
        scheduleMicrotask(callback);
      }
      return;
    }

    _chunkIndex = nextIndex;
    final ok = await _speakChunk(_chunks[_chunkIndex]);
    if (!ok) {
      _clearQueue();
      _setState(TtsState.stopped);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_flutterTts.stop());
    super.dispose();
  }
}
