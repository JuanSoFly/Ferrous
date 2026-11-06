library;

class AppConstants {
  AppConstants._();

  static const String appName = 'Ferrous';
  static const String packageName = 'com.juansofly.ferrous';
}

class DefaultConfig {
  DefaultConfig._();

  static const String defaultReadingMode = 'leftToRight';
  static const double defaultTtsRate = 0.8;
  static const double defaultTtsPitch = 1.0;
}

class CacheConstants {
  CacheConstants._();

  static const int cbzPreloadAhead = 3;
  static const int cbzPreloadBehind = 1;
  static const int maxConcurrentCoverExtractions = 3;
}

class AppRadius {
  AppRadius._();

  static const double pill = 999.0;
  static const double control = 12.0;
  static const double card = 16.0;
  static const double sheet = 24.0;
}

class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration sheet = Duration(milliseconds: 300);
}
