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

  // 1. Ferrous (default) - Dark, Rust accents
  static final ThemeData _ferrousTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepOrange,
      brightness: Brightness.dark,
      surface: const Color(0xFF1E1E1E),
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      elevation: 0,
    ),
  );

  // 2. Console - Hacker aesthetic, Monospace, Green on Black
  static final ThemeData _consoleTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00FF41), // Phosphor Green
      secondary: Color(0xFF008F11),
      surface: Color(0xFF0D0208),
      onPrimary: Colors.black,
      onSurface: Color(0xFF00FF41),
    ),
    textTheme: GoogleFonts.jetBrainsMonoTextTheme(ThemeData.dark().textTheme)
        .apply(bodyColor: const Color(0xFF00FF41), displayColor: const Color(0xFF00FF41)),
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF00FF41)),
      titleTextStyle: TextStyle(color: Color(0xFF00FF41), fontFamily: 'JetBrains Mono', fontSize: 20),
    ),
    cardTheme: CardThemeData(
      color: Colors.black,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF003B00), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF00FF41)),
    dividerTheme: const DividerThemeData(color: Color(0xFF003B00)),
  );

  // 3. Sepia - Warm, Reader friendly, Serif
  static final ThemeData _sepiaTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.brown,
      brightness: Brightness.light,
      surface: const Color(0xFFF4ECD8),
      onSurface: const Color(0xFF5D4037),
    ),
    textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.light().textTheme)
        .apply(bodyColor: const Color(0xFF5D4037), displayColor: const Color(0xFF3E2723)),
    scaffoldBackgroundColor: const Color(0xFFF4ECD8),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFE9E0C9),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF5D4037)),
      titleTextStyle: TextStyle(color: Color(0xFF3E2723), fontSize: 20, fontWeight: FontWeight.bold),
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFFE9E0C9),
      elevation: 0,
    ),
  );

  // 4. Light - Standard Material 3 Light
  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
    // Standard scaffold background
  );
}
