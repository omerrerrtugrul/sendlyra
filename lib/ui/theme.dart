import 'package:flutter/material.dart';

/// SendLyra tema ailesi — Material 3, "aurora" aksanlı.
class SendLyraTheme {
  static const List<Color> accents = [
    Color(0xFF7C4DFF), // mor / indigo
    Color(0xFF00BFA5), // turkuaz
    Color(0xFFFF6E6E), // mercan
    Color(0xFF66BB6A), // yeşil
  ];

  static Color accent(int index) =>
      accents[index < 0 || index >= accents.length ? 0 : index];

  static ThemeData light(Color seed) => _build(Brightness.light, seed);

  static ThemeData dark(Color seed) => _build(Brightness.dark, seed);

  static ThemeData _build(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF12101A) : scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1C1926) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
    );
  }
}

/// Kart yüzeyi için ortak dekorasyon.
CardThemeData cardDecoration(ColorScheme scheme, {bool highlighted = false}) {
  return CardThemeData(
    color: highlighted
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : null,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.35)
            : scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    ),
  );
}
