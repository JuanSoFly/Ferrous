import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reader_app/core/services/diagnostic_logger.dart';

/// Context-free service to launch GitHub issue templates and discussions,
/// copying full diagnostic logs to clipboard to overcome URI length limitations.
class FeedbackService {
  FeedbackService._();

  static const String _owner = 'JuanSoFly';
  static const String _repo = 'Ferrous';
  static const String _githubBase = 'https://github.com/$_owner/$_repo';

  /// Launches a pre-filled GitHub Bug Report issue in an external browser.
  /// Automatically places the full, sanitized diagnostic trace onto the user's
  /// clipboard and instructs them to paste it into the issue template.
  static Future<bool> openBugReport({
    String? formatContext,
    String? errorMessage,
    String? currentTheme,
  }) async {
    // 1. Copy sanitized diagnostic logs to clipboard
    final fullLogs = DiagnosticLogger.instance.formatPlainText(includeStack: true);
    await Clipboard.setData(ClipboardData(text: fullLogs));

    // 2. Gather device metadata
    String appVersion = 'Unknown';
    String buildNumber = '';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
    } catch (_) {}

    final osVersion = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final sanitizedError = errorMessage != null
        ? DiagnosticLogger.sanitize(errorMessage).trim()
        : null;

    final title = sanitizedError != null
        ? '[Bug]: ${sanitizedError.split('\n').first}'
        : (formatContext != null ? '[Bug]: Issue loading $formatContext' : '[Bug]: Issue Report');

    // 3. Assemble Markdown body with clear instructions to paste clipboard
    final bodyBuffer = StringBuffer();
    bodyBuffer.writeln('### Environment');
    bodyBuffer.writeln('- **Ferrous Version:** $appVersion ($buildNumber)');
    bodyBuffer.writeln('- **Platform OS:** $osVersion');
    if (currentTheme != null) {
      bodyBuffer.writeln('- **Theme:** $currentTheme');
    }
    if (formatContext != null) {
      bodyBuffer.writeln('- **Document Format:** $formatContext');
    }
    if (sanitizedError != null) {
      bodyBuffer.writeln('- **Error Summary:** `$sanitizedError`');
    }
    bodyBuffer.writeln();
    bodyBuffer.writeln('### Diagnostic Logs');
    bodyBuffer.writeln('> 📋 **Logs Auto-Copied:** Diagnostic logs were automatically copied to your clipboard.');
    bodyBuffer.writeln('> Please **paste (Ctrl+V / Long-Press Paste)** inside the code block below:');
    bodyBuffer.writeln();
    bodyBuffer.writeln('```text');
    bodyBuffer.writeln('<PASTE_LOGS_HERE>');
    bodyBuffer.writeln('```');
    bodyBuffer.writeln();
    bodyBuffer.writeln('### What Happened?');
    bodyBuffer.writeln('<!-- Describe what you were doing when the issue occurred -->');
    bodyBuffer.writeln();
    bodyBuffer.writeln('### Steps to Reproduce');
    bodyBuffer.writeln('1. Open document...');
    bodyBuffer.writeln('2. Turn page / change setting...');

    final uri = Uri.parse('$_githubBase/issues/new').replace(
      queryParameters: {
        'title': title.length > 120 ? '${title.substring(0, 117)}...' : title,
        'body': bodyBuffer.toString(),
      },
    );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Launches GitHub Discussions or Feature Request in an external browser.
  static Future<bool> openFeatureRequest() async {
    final uri = Uri.parse('$_githubBase/issues/new').replace(
      queryParameters: {
        'title': '[Feature]: ',
        'body': '### Proposed Feature / Improvement\n\n### Use Case\n',
      },
    );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens the community GitHub repository in an external browser.
  static Future<bool> openRepository() async {
    final uri = Uri.parse(_githubBase);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
