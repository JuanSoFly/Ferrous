import 'dart:async';
import 'package:flutter/foundation.dart';
import 'perf_logger.dart';

Future<T> measureAsync<T>(String label, Future<T> Function() fn, {Map<String, dynamic>? metadata}) async {
  final sw = Stopwatch()..start();
  try {
    final result = await fn();
    final duration = sw.elapsedMilliseconds;
    
    debugPrint('⏱️ $label: ${duration}ms');
    
    unawaited(PerfLogger().logEvent(
      event: label,
      durationMs: duration,
      metadata: metadata,
    ));
    
    return result;
  } catch (e) {
    debugPrint('❌ $label failed: $e');
    rethrow;
  }
}

T measureSync<T>(String label, T Function() fn, {Map<String, dynamic>? metadata}) {
  final sw = Stopwatch()..start();
  try {
    final result = fn();
    final duration = sw.elapsedMilliseconds;
    
    debugPrint('⏱️ $label: ${duration}ms');
    
    unawaited(PerfLogger().logEvent(
      event: label,
      durationMs: duration,
      metadata: metadata,
    ));
    
    return result;
  } catch (e) {
    debugPrint('❌ $label failed: $e');
    rethrow;
  }
}

class Semaphore {
  final int max;
  int _current = 0;
  final List<Completer<void>> _waiters = [];

  Semaphore(this.max);

  Future<void> acquire() async {
    if (_current < max) {
      _current++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _current--;
    }
  }
}
