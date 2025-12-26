import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// A singleton logger that writes performance events to a JSONL file.
class PerfLogger {
  static final PerfLogger _instance = PerfLogger._internal();
  factory PerfLogger() => _instance;
  PerfLogger._internal();

  File? _logFile;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final perfDir = Directory('${docsDir.path}/perf_logs');
      if (!await perfDir.exists()) {
        await perfDir.create(recursive: true);
      }
      
      final now = DateTime.now();
      final fileName = 'session_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.jsonl';
      _logFile = File('${perfDir.path}/$fileName');
      _initialized = true;
      
      // Rotate logs: keep last 10 sessions
      final files = await perfDir.list().where((e) => e is File).toList();
      if (files.length > 10) {
        files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        for (var i = 0; i < files.length - 10; i++) {
          await files[i].delete();
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize PerfLogger: $e');
    }
  }

  Future<void> logEvent({
    required String event,
    required int durationMs,
    Map<String, dynamic>? metadata,
  }) async {
    await _init();
    if (_logFile == null) return;

    final entry = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'event': event,
      'duration_ms': durationMs,
      ...?metadata,
    };

    try {
      await _logFile!.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('Failed to write perf log: $e');
    }
  }
}
