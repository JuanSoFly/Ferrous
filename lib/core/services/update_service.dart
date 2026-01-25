import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
      final downloadUrl = _findDownloadUrl(assets);

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
  static String _findDownloadUrl(List<dynamic> assets) {
    // Determine device ABI
    final abi = _getDeviceAbi();
    
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      
      if (name.contains(abi) && name.endsWith('.apk')) {
        return url;
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
  static String _getDeviceAbi() {
    if (!Platform.isAndroid) return '';
    
    // Get supported ABIs from environment
    // Most devices will be arm64-v8a
    final supportedAbis = Platform.environment['SUPPORTED_ABIS'] ?? '';
    
    if (supportedAbis.contains('arm64-v8a')) {
      return 'arm64-v8a';
    } else if (supportedAbis.contains('armeabi-v7a')) {
      return 'armeabi-v7a';
    } else if (supportedAbis.contains('x86_64')) {
      return 'x86_64';
    }
    
    // Default to arm64-v8a (most common)
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
  while (parts1.length < 3) parts1.add(0);
  while (parts2.length < 3) parts2.add(0);

  for (var i = 0; i < 3; i++) {
    if (parts1[i] > parts2[i]) return 1;
    if (parts1[i] < parts2[i]) return -1;
  }

  // Check pre-release suffix (beta < stable)
  final hasSuffix1 = v1.contains('-');
  final hasSuffix2 = v2.contains('-');
  
  if (hasSuffix1 && !hasSuffix2) return -1; // v1 is pre-release
  if (!hasSuffix1 && hasSuffix2) return 1;  // v2 is pre-release
  
  return 0;
}
