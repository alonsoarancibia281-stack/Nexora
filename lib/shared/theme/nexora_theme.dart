import 'package:flutter/material.dart';

/// One visual language for the whole app.
///
/// Buttons share the same height, the same corner and the same weight, so the
/// hierarchy comes from colour and fill, never from size accidents.
class NexoraTheme {
  const NexoraTheme._();

  static const brand = Color(0xFF16E0A3);
  static const brandDeep = Color(0xFF0B8F73);
  static const accent = Color(0xFF5B8CFF);
  static const up = Color(0xFF17C98B);
  static const down = Color(0xFFFF5C7A);
  static const warn = Color(0xFFFFB020);

  static const radius = 16.0;
  static const buttonHeight = 48.0;
  static const compactButtonHeight = 40.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      surface: isDark ? const Color(0xFF0B141B) : const Color(0xFFF7FAF9),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    const buttonText = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 14.5,
      height: 1.1,
      letterSpacing: .1,
    );

    return base.copyWith(
      // The animated gradient lives behind every screen. Only the scaffold is
      // transparent: menus and sheets keep a solid surface.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark
            ? const Color(0xFF101C25).withValues(alpha: .82)
            : Colors.white.withValues(alpha: .86),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? .35 : .55),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: scheme.outline.withValues(alpha: .6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, compactButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          textStyle: buttonText,
          minimumSize: const Size(0, buttonHeight),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 4),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: .05)
            : Colors.black.withValues(alpha: .04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius - 2),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF0B141B).withValues(alpha: .92)
            : Colors.white.withValues(alpha: .92),
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 2),
        ),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: scheme.outlineVariant.withValues(alpha: .4),
        linearMinHeight: 6,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .5),
        space: 24,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius - 2),
        ),
      ),
    );
  }

  /// Colour for a direction, kept identical everywhere.
  static Color toneUp(BuildContext context) => up;
  static Color toneDown(BuildContext context) => down;
}
