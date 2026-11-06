import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Information about an available update
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final String htmlUrl;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.htmlUrl,
  });

  bool get isUpdateAvailable => _compareVersions(latestVersion, currentVersion) > 0;
}

/// Service to check for app updates via GitHub Releases API
class UpdateService {
  static const String _owner = 'JuanSoFly';
  static const String _repo = 'Ferrous';
  static const String _apiUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const MethodChannel _appInfoChannel = MethodChannel('com.juansofly.ferrous/app_info');

  /// Check for updates
  /// Returns [UpdateInfo] if check succeeds, null if it fails
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final releaseNotes = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final assets = data['assets'] as List<dynamic>? ?? [];

      // Find the correct APK for this device's ABI
      final downloadUrl = await _findDownloadUrl(assets);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        htmlUrl: htmlUrl,
      );
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  /// Find the download URL for the device's ABI
  static Future<String> _findDownloadUrl(List<dynamic> assets) async {
    // Determine device ABI
    final abi = await _getDeviceAbi();
    
    if (abi.isNotEmpty) {
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String? ?? '';
        
        if (name.contains(abi) && name.endsWith('.apk')) {
          return url;
        }
      }
    }

    // Fallback: return first APK found
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      
      if (name.endsWith('.apk')) {
        return url;
      }
    }

    return '';
  }

  /// Get device ABI string
  static Future<String> _getDeviceAbi() async {
    if (!Platform.isAndroid) return '';
    
    try {
      final abis = await _appInfoChannel.invokeMethod<List<dynamic>>('getSupportedAbis');
      if (abis != null && abis.isNotEmpty) {
        final abiList = abis.map((e) => e.toString().toLowerCase()).toList();
        if (abiList.contains('arm64-v8a')) {
          return 'arm64-v8a';
        } else if (abiList.contains('armeabi-v7a')) {
          return 'armeabi-v7a';
        } else if (abiList.contains('x86_64')) {
          return 'x86_64';
        }
      }
    } catch (e) {
      debugPrint('Error getting device ABI via platform channel: $e');
    }

    // Default to arm64-v8a (most common for modern devices)
    return 'arm64-v8a';
  }
}

/// Compare semantic versions
/// Returns positive if v1 > v2, negative if v1 < v2, 0 if equal
int _compareVersions(String v1, String v2) {
  // Remove any suffix like -beta.2
  final clean1 = v1.split('-').first;
  final clean2 = v2.split('-').first;
  
  final parts1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final parts2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  // Pad to same length
  while (parts1.length < 3) {
    parts1.add(0);
  }
  while (parts2.length < 3) {
    parts2.add(0);
  }

  for (var i = 0; i < 3; i++) {
    if (parts1[i] > parts2[i]) return 1;
    if (parts1[i] < parts2[i]) return -1;
  }

  // Check pre-release suffix (beta < stable)
  final hasSuffix1 = v1.contains('-');
  final hasSuffix2 = v2.contains('-');
  
  if (hasSuffix1 && !hasSuffix2) return -1; // v1 is pre-release, v2 is stable
  if (!hasSuffix1 && hasSuffix2) return 1;  // v1 is stable, v2 is pre-release
  
  if (hasSuffix1 && hasSuffix2) {
    final s1 = v1.substring(v1.indexOf('-') + 1);
    final s2 = v2.substring(v2.indexOf('-') + 1);
    return _compareSuffixes(s1, s2);
  }

  return 0;
}

int _compareSuffixes(String s1, String s2) {
  final parts1 = s1.split('.');
  final parts2 = s2.split('.');
  final minLen = parts1.length < parts2.length ? parts1.length : parts2.length;

  for (var i = 0; i < minLen; i++) {
    final p1 = parts1[i];
    final p2 = parts2[i];
    final num1 = int.tryParse(p1);
    final num2 = int.tryParse(p2);

    if (num1 != null && num2 != null) {
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    } else {
      final comp = p1.compareTo(p2);
      if (comp != 0) return comp > 0 ? 1 : -1;
    }
  }

  if (parts1.length > parts2.length) return 1;
  if (parts1.length < parts2.length) return -1;
  return 0;
}
