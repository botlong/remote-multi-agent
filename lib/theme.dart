import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF5C8A), // OpenCode-ish pink
    brightness: Brightness.light,
  );
  return _withFonts(ThemeData(useMaterial3: true, colorScheme: scheme));
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF5C8A),
    brightness: Brightness.dark,
  );
  return _withFonts(ThemeData(useMaterial3: true, colorScheme: scheme));
}

ThemeData _withFonts(ThemeData base) {
  // SF-ish for body, JetBrains Mono for code blocks. google_fonts caches files
  // on first launch then runs offline.
  final text = GoogleFonts.interTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: base.colorScheme.surface,
      foregroundColor: base.colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: base.colorScheme.surfaceContainerLow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
