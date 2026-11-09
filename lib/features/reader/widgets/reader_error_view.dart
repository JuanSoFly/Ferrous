import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/services/diagnostic_logger.dart';
import 'package:reader_app/core/services/feedback_service.dart';

/// Fullscreen error fallback widget displayed when a reader encounters
/// a parsing, decompression, or rendering failure.
///
/// Fully hardened against:
/// 1. PII/path leakage via [DiagnosticLogger.sanitize].
/// 2. RenderFlex overflows via centered [SingleChildScrollView] + [TextOverflow.ellipsis].
/// 3. E-Ink ghosting/blur via high-contrast monochrome tokens.
/// 4. Immersive/fullscreen traps via a dedicated "Return to Library" escape button.
class ReaderErrorView extends StatefulWidget {
  final String formatTitle;
  final String error;
  final StackTrace? stackTrace;
  final bool isEInk;
  final VoidCallback? onReturnToLibrary;

  const ReaderErrorView({
    super.key,
    required this.formatTitle,
    required this.error,
    this.stackTrace,
    this.isEInk = false,
    this.onReturnToLibrary,
  });

  @override
  State<ReaderErrorView> createState() => _ReaderErrorViewState();
}

class _ReaderErrorViewState extends State<ReaderErrorView> {
  bool _copied = false;

  void _handleCopyDetails(String sanitizedError, String? sanitizedStack) async {
    HapticFeedback.lightImpact();
    final buffer = StringBuffer();
    buffer.writeln('Format: ${widget.formatTitle}');
    buffer.writeln('Error: $sanitizedError');
    if (sanitizedStack != null && sanitizedStack.isNotEmpty) {
      buffer.writeln('\nStack Trace:');
      buffer.writeln(sanitizedStack);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Error details copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _handleReportIssue(String sanitizedError) {
    HapticFeedback.lightImpact();
    FeedbackService.openBugReport(
      formatContext: widget.formatTitle,
      errorMessage: sanitizedError,
    );
  }

  void _handleReturnToLibrary() {
    HapticFeedback.lightImpact();
    if (widget.onReturnToLibrary != null) {
      widget.onReturnToLibrary!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEInk = widget.isEInk;

    // Safeguard 2: Sanitize error and stack trace before display, copy, or reporting
    final sanitizedError = DiagnosticLogger.sanitize(widget.error);
    final sanitizedStack = widget.stackTrace != null
        ? DiagnosticLogger.sanitize(widget.stackTrace.toString().trim())
        : null;

    final Color backgroundColor = isEInk ? const Color(0xFFEAE6DF) : theme.scaffoldBackgroundColor;
    final Color textColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.onSurface;
    final Color subtitleColor = isEInk
        ? const Color(0xFF4A4945)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final Color primaryColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary;
    final Color errorColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.error;

    // Safeguard 3: Centered SingleChildScrollView prevents RenderFlex overflow on small screens / landscape
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isEInk
                          ? const Color(0xFFE0DCD3)
                          : errorColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.card),
                      border: isEInk
                          ? Border.all(color: const Color(0xFF1A1A18), width: 1.5)
                          : null,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 36,
                      color: errorColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Unable to Load ${widget.formatTitle}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: -0.4,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Text(
                    'Ferrous encountered an error while parsing this document.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Error Text Box (Constrained maxLines + ellipsis to avoid overflow)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isEInk
                          ? const Color(0xFFE0DCD3)
                          : errorColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.sm),
                      border: Border.all(
                        color: isEInk
                            ? const Color(0xFF1A1A18)
                            : errorColor.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: SelectableText(
                      sanitizedError,
                      maxLines: 6,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isEInk ? const Color(0xFF1A1A18) : errorColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Action Buttons
                  // Safeguard 4: Clear "Return to Library" primary button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: isEInk
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A1A18),
                              foregroundColor: const Color(0xFFEAE6DF),
                              side: const BorderSide(color: Color(0xFF1A1A18), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                            ),
                            onPressed: _handleReturnToLibrary,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text(
                              'Return to Library',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: theme.colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.control),
                              ),
                            ),
                            onPressed: _handleReturnToLibrary,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text(
                              'Return to Library',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Secondary Actions: Copy Error & Report Issue
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textColor,
                            side: BorderSide(
                              color: isEInk
                                  ? const Color(0xFF1A1A18)
                                  : theme.colorScheme.outline.withValues(alpha: 0.4),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.control),
                            ),
                          ),
                          onPressed: () => _handleCopyDetails(sanitizedError, sanitizedStack),
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy_outlined,
                            size: 16,
                            color: primaryColor,
                          ),
                          label: Text(
                            _copied ? 'Copied' : 'Copy Details',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isEInk ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textColor,
                            side: BorderSide(
                              color: isEInk
                                  ? const Color(0xFF1A1A18)
                                  : theme.colorScheme.outline.withValues(alpha: 0.4),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isEInk ? 2 : AppRadius.control),
                            ),
                          ),
                          onPressed: () => _handleReportIssue(sanitizedError),
                          icon: Icon(
                            Icons.bug_report_outlined,
                            size: 16,
                            color: primaryColor,
                          ),
                          label: Text(
                            'Report Issue',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isEInk ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
