import 'package:flutter/material.dart';

/// SmartSpend brand color palette.
///
/// All UI surfaces must source their colors from here — never inline hex
/// literals in widgets. Adjust the palette here and the entire app follows.
abstract class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF1B5E20); // Deep green
  static const Color primaryLight = Color(0xFF43A047);
  static const Color primaryDark = Color(0xFF003D00);
  // Text/icons on the deep-green [primary] surface. Fixed white in both
  // light and dark, because [primary] is forced deep green in both
  // brightnesses — letting fromSeed derive onPrimary yields a dark tone in
  // dark mode (M3 expects a light primary), which is unreadable on green.
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFFB300); // Amber — important numbers

  // Semantic
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
  static const Color info = Color(0xFF1976D2);

  // Light surfaces
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color onSurfaceLight = Color(0xFF1C1B1F);
  static const Color outlineLight = Color(0xFFE0E0E0);

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color onSurfaceDark = Color(0xFFEDEDED);
  static const Color outlineDark = Color(0xFF2A2A2A);

  // Category palette — order matches default categories seed.
  static const List<Color> categoryPalette = <Color>[
    Color(0xFF4CAF50), // Market
    Color(0xFFFF5722), // Restoran
    Color(0xFF795548), // Kahve
    Color(0xFF2196F3), // Ulaşım
    Color(0xFF607D8B), // Yakıt
    Color(0xFF9C27B0), // Faturalar
    Color(0xFF3F51B5), // Kira
    Color(0xFFF44336), // Sağlık
    Color(0xFFE91E63), // Giyim
    Color(0xFFFF9800), // Eğlence
    Color(0xFF00BCD4), // Elektronik
    Color(0xFF8BC34A), // Spor
    Color(0xFFFFEB3B), // Evcil Hayvan
    Color(0xFFCE93D8), // Hediye
    Color(0xFF9E9E9E), // Diğer
  ];
}
