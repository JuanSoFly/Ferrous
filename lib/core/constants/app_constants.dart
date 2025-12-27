/// App-wide constants for the Ferrous e-reader application.
library;

/// Application metadata
class AppConstants {
  AppConstants._();

  /// Application name
  static const String appName = 'Ferrous';

  /// Application package name
  static const String packageName = 'com.juansofly.ferrous';
}

/// Default configuration values
class DefaultConfig {
  DefaultConfig._();

  /// Default reading mode for new books
  static const String defaultReadingMode = 'verticalContinuous';

  /// Default TTS speaking rate
  static const double defaultTtsRate = 1.0;

  /// Default TTS pitch
  static const double defaultTtsPitch = 1.0;
}

/// Cache and performance constants
class CacheConstants {
  CacheConstants._();

  /// Number of pages to preload ahead in CBZ reader
  static const int cbzPreloadAhead = 3;

  /// Number of pages to preload behind in CBZ reader
  static const int cbzPreloadBehind = 1;

  /// Maximum concurrent cover extraction processes
  static const int maxConcurrentCoverExtractions = 3;
}
