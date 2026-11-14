/// Shared typography metrics and formulas ensuring mathematical parity between
/// SafeScreenPaginator measurement and FlutterHtml rendering.
class ReaderTypographyMetrics {
  /// Font size scale multiplier for HTML headings relative to body font size.
  static double headingScale(String tag) {
    switch (tag.toLowerCase()) {
      case 'h1':
        return 2.0;
      case 'h2':
        return 1.5;
      case 'h3':
        return 1.17;
      case 'h4':
        return 1.0;
      case 'h5':
        return 0.83;
      case 'h6':
        return 0.67;
      default:
        return 1.0;
    }
  }

  /// Top margin for HTML headings.
  /// In paged mode, top margin is 0.0 to prevent top-of-page vertical drift.
  static double headingTopMargin(String tag, bool isPaged, double fontSize) {
    if (isPaged) return 0.0;
    return headingScale(tag) * fontSize * 0.67;
  }

  /// Bottom margin for HTML headings.
  /// In paged mode, matches paragraphSpacing directly.
  static double headingBottomMargin(String tag, bool isPaged, double paragraphSpacing) {
    return paragraphSpacing;
  }

  /// Exact paragraph indentation width matching the inline WidgetSpan in EpubContentViewer.
  static double computeIndentWidth(double fontSize) {
    return (fontSize * 1.6).clamp(18.0, 42.0);
  }
}
