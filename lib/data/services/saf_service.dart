import 'package:flutter/services.dart';

/// Service for handling Storage Access Framework (SAF) operations on Android.
///
/// This service communicates with native Kotlin code via platform channel
/// to properly handle Android 10+ scoped storage requirements.
class SafService {
  static const _channel = MethodChannel('com.antigravity.reader/saf');

  /// Opens the SAF folder picker and copies ebook files to internal storage.
  ///
  /// Returns a list of absolute paths to the copied files in internal storage.
  /// These paths are accessible by the Rust backend for scanning.
  ///
  /// Returns empty list if user cancels or no supported files found.
  Future<List<String>> pickAndImportFolder() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickFolder');
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw SafException('Failed to pick folder: ${e.message}');
    }
  }

  /// Rescans all previously granted folders for new ebook files.
  ///
  /// This uses persisted URI permissions to access folders that were
  /// previously selected by the user without prompting again.
  ///
  /// Returns list of paths to any newly copied files.
  Future<List<String>> rescanPersistedFolders() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('rescanFolders');
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw SafException('Failed to rescan folders: ${e.message}');
    }
  }

  /// Gets list of persisted folder URIs for display purposes.
  ///
  /// Returns the content:// URIs of folders the user has previously granted access to.
  Future<List<String>> getPersistedFolders() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPersistedFolders');
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw SafException('Failed to get persisted folders: ${e.message}');
    }
  }

  /// Removes a persisted folder permission.
  ///
  /// The user will need to re-select the folder to access it again.
  Future<void> removePersistedFolder(String uri) async {
    try {
      await _channel.invokeMethod('removePersistedFolder', {'uri': uri});
    } on PlatformException catch (e) {
      throw SafException('Failed to remove folder: ${e.message}');
    }
  }
}

/// Exception thrown by SAF operations.
class SafException implements Exception {
  final String message;
  SafException(this.message);

  @override
  String toString() => 'SafException: $message';
}
