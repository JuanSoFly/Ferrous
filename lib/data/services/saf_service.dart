import 'package:flutter/services.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/core/errors/exceptions.dart';


enum SafStorageMode { linked, imported }

class SafBookRef {
  final BookSourceType sourceType;
  final String? filePath;
  final String? sourceUri;
  final String displayName;
  final String format;
  final int? size;
  final int? lastModified;

  const SafBookRef({
    required this.sourceType,
    required this.filePath,
    required this.sourceUri,
    required this.displayName,
    required this.format,
    required this.size,
    required this.lastModified,
  });

  factory SafBookRef.fromMap(Map<dynamic, dynamic> map) {
    final displayName = (map['displayName'] as String?) ?? '';
    final rawFormat = (map['format'] as String?) ?? _formatFromName(displayName);
    final sourceTypeValue = map['sourceType'] as String?;
    var sourceType = parseBookSourceType(sourceTypeValue);
    if (sourceTypeValue == null && map['uri'] != null) {
      sourceType = BookSourceType.linked;
    }
    return SafBookRef(
      sourceType: sourceType,
      filePath: map['filePath'] as String?,
      sourceUri: map['uri'] as String?,
      displayName: displayName,
      format: rawFormat.toLowerCase(),
      size: _toInt(map['size']),
      lastModified: _toInt(map['lastModified']),
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _formatFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }
}

/// Service for handling Storage Access Framework (SAF) operations on Android.
///
/// This service communicates with native Kotlin code via platform channel
/// to properly handle Android 10+ scoped storage requirements.
class SafService {
  static const _channel = MethodChannel('com.juansofly.ferrous/saf');

  /// Opens the SAF folder picker and scans or imports ebook files based on [mode].
  ///
  /// Returns a list of book references for either linked (URI) or imported (file path) files.
  /// Returns empty list if user cancels or no supported files found.
  Future<List<SafBookRef>> pickFolder({required SafStorageMode mode}) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickFolder', {
        'mode': mode.name,
      });
      final list = result ?? const [];
      return list
          .map((item) => SafBookRef.fromMap(Map<dynamic, dynamic>.from(item as Map)))
          .toList();
    } on PlatformException catch (e) {
      throw SafException('Failed to pick folder: ${e.message}');
    }
  }

  /// Rescans all previously granted folders for new ebook files.
  ///
  /// This uses persisted URI permissions to access folders that were
  /// previously selected by the user without prompting again.
  ///
  /// Returns list of book references for any newly discovered files.
  Future<List<SafBookRef>> rescanPersistedFolders() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('rescanFolders');
      final list = result ?? const [];
      return list
          .map((item) => SafBookRef.fromMap(Map<dynamic, dynamic>.from(item as Map)))
          .toList();
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

  /// Copies a single linked document URI into cache and returns the temp path.
  Future<String> copyUriToCache({
    required String uri,
    String? suggestedName,
    bool force = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('copyUriToCache', {
        'uri': uri,
        'suggestedName': suggestedName,
        'force': force,
      });
      if (result == null || result.isEmpty) {
        throw SafException('Failed to copy linked file to cache.');
      }
      return result;
    } on PlatformException catch (e) {
      throw SafException('Failed to copy linked file: ${e.message}');
    }
  }
  /// Validates if a URI still has valid persisted permission.
  ///
  /// Returns true if the app can still access the URI, false if permission
  /// has been revoked (e.g., after app reinstall).
  Future<bool> validateUriPermission(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('validateUriPermission', {
        'uri': uri,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Cleans up stale URI permissions that are no longer valid.
  ///
  /// This should be called on app startup to remove references to URIs
  /// that were persisted but are no longer accessible (e.g., after reinstall).
  /// Returns the number of stale entries removed.
  Future<int> cleanupStalePermissions() async {
    try {
      final result = await _channel.invokeMethod<int>('cleanupStalePermissions');
      return result ?? 0;
    } on PlatformException catch (e) {
      throw SafException('Failed to cleanup stale permissions: ${e.message}');
    }
  }
}
