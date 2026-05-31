import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppTheme {
  ferrous,
  console,
  sepia,
  light,
}

class AppThemes {
  static final Map<AppTheme, ThemeData> themeData = {
    AppTheme.ferrous: _ferrousTheme,
    AppTheme.console: _consoleTheme,
    AppTheme.sepia: _sepiaTheme,
    AppTheme.light: _lightTheme,
  };

  // 1. Ferrous (default) - Dark, Warm Charcoal, Premium Rust accents
  static final ThemeData _ferrousTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE0623A),
      brightness: Brightness.dark,
      primary: const Color(0xFFE0623A),
      onPrimary: Colors.white,
      secondary: const Color(0xFFD67B5E),
      surface: const Color(0xFF1E1C19),
      onSurface: const Color(0xFFECE6E2),
      surfaceContainerLowest: const Color(0xFF131210),
      surfaceContainerLow: const Color(0xFF191715),
      surfaceContainer: const Color(0xFF1E1C19),
      surfaceContainerHigh: const Color(0xFF262420),
      surfaceContainerHighest: const Color(0xFF2F2C28),
    ),
    scaffoldBackgroundColor: const Color(0xFF12110F),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      bodyLarge: GoogleFonts.outfit(height: 1.5),
      bodyMedium: GoogleFonts.outfit(height: 1.4),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1C19),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF2B2824), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFFE0623A).withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.outfit(color: const Color(0xFFE0623A), fontWeight: FontWeight.w600, fontSize: 12);
        }
        return GoogleFonts.outfit(color: Colors.grey, fontSize: 12);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFFE0623A), size: 24);
        }
        return const IconThemeData(color: Colors.grey, size: 24);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1C19),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: const Color(0xFFE0623A),
      labelColor: const Color(0xFFE0623A),
      unselectedLabelColor: Colors.grey,
      labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E1C19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2B2824), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2B2824), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0623A), width: 1.5),
      ),
    ),
  );

  // 2. Console - Cyberpunk/Hacker theme, Neon Green, Tech details
  static final ThemeData _consoleTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00FF41),
      onPrimary: Colors.black,
      secondary: Color(0xFF008F11),
      surface: Color(0xFF0D0208),
      onSurface: Color(0xFF00FF41),
      surfaceContainer: Color(0xFF12050E),
      surfaceContainerHigh: Color(0xFF1B0A16),
      surfaceContainerHighest: Color(0xFF240D1D),
    ),
    scaffoldBackgroundColor: Colors.black,
    textTheme: GoogleFonts.jetBrainsMonoTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: const Color(0xFF00FF41),
      displayColor: const Color(0xFF00FF41),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF00FF41)),
      titleTextStyle: TextStyle(color: Color(0xFF00FF41), fontFamily: 'JetBrains Mono', fontSize: 20, fontWeight: FontWeight.bold),
    ),
    cardTheme: CardThemeData(
      color: Colors.black,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF00FF41), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFF00FF41).withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return const TextStyle(color: Color(0xFF00FF41), fontFamily: 'JetBrains Mono', fontSize: 12);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return const IconThemeData(color: Color(0xFF00FF41), size: 24);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0D0208),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Color(0xFF00FF41), width: 1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: Color(0xFF00FF41),
      labelColor: Color(0xFF00FF41),
      unselectedLabelColor: Color(0xFF008F11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF00FF41), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF008F11), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF00FF41), width: 1.5),
      ),
    ),
  );

  // 3. Sepia - Soft Warm Paper, Comfortable Serif
  static final ThemeData _sepiaTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF5D4037),
      brightness: Brightness.light,
      primary: const Color(0xFF5D4037),
      onPrimary: Colors.white,
      secondary: const Color(0xFF8D6E63),
      surface: const Color(0xFFF4ECD8),
      onSurface: const Color(0xFF4E342E),
      surfaceContainer: const Color(0xFFE9E0C9),
      surfaceContainerHigh: const Color(0xFFDDD2B8),
    ),
    scaffoldBackgroundColor: const Color(0xFFF4ECD8),
    textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.light().textTheme).copyWith(
      titleLarge: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.merriweather(fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: const Color(0xFF4E342E),
      displayColor: const Color(0xFF3E2723),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF5D4037)),
      titleTextStyle: TextStyle(color: Color(0xFF3E2723), fontSize: 20, fontWeight: FontWeight.bold),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFE9E0C9),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFDFD4B7), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFF5D4037).withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.merriweather(color: const Color(0xFF5D4037), fontWeight: FontWeight.w600, fontSize: 12);
        }
        return GoogleFonts.merriweather(color: const Color(0xFF8D6E63), fontSize: 12);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF5D4037), size: 24);
        }
        return const IconThemeData(color: Color(0xFF8D6E63), size: 24);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFF4ECD8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: const Color(0xFF5D4037),
      labelColor: const Color(0xFF5D4037),
      unselectedLabelColor: const Color(0xFF8D6E63),
      labelStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFE9E0C9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDFD4B7), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDFD4B7), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF5D4037), width: 1.5),
      ),
    ),
  );

  // 4. Light - Crisp Minimalist Light, Cool Blue accents
  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2B5C8F),
      brightness: Brightness.light,
      primary: const Color(0xFF2B5C8F),
      onPrimary: Colors.white,
      secondary: const Color(0xFF4A7FB5),
      surface: const Color(0xFFF8F9FA),
      onSurface: const Color(0xFF212529),
      surfaceContainer: const Color(0xFFEDF1F5),
      surfaceContainerHigh: const Color(0xFFE2E7ED),
    ),
    scaffoldBackgroundColor: const Color(0xFFFFFFFF),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      bodyLarge: GoogleFonts.outfit(height: 1.5),
      bodyMedium: GoogleFonts.outfit(height: 1.4),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF2B5C8F)),
      titleTextStyle: TextStyle(color: Color(0xFF212529), fontSize: 20, fontWeight: FontWeight.bold),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFF8F9FA),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E7ED), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFF2B5C8F).withValues(alpha: 0.1),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.outfit(color: const Color(0xFF2B5C8F), fontWeight: FontWeight.w600, fontSize: 12);
        }
        return GoogleFonts.outfit(color: Colors.grey, fontSize: 12);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF2B5C8F), size: 24);
        }
        return const IconThemeData(color: Colors.grey, size: 24);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: const Color(0xFF2B5C8F),
      labelColor: const Color(0xFF2B5C8F),
      unselectedLabelColor: Colors.grey,
      labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E7ED), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E7ED), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2B5C8F), width: 1.5),
      ),
    ),
  );
}
