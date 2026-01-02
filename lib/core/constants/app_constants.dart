library;

class AppConstants {
  AppConstants._();

  static const String appName = 'Ferrous';
  static const String packageName = 'com.juansofly.ferrous';
}

class DefaultConfig {
  DefaultConfig._();

  static const String defaultReadingMode = 'verticalContinuous';
  static const double defaultTtsRate = 1.0;
  static const double defaultTtsPitch = 1.0;
}

class CacheConstants {
  CacheConstants._();

  static const int cbzPreloadAhead = 3;
  static const int cbzPreloadBehind = 1;
  static const int maxConcurrentCoverExtractions = 3;
}
