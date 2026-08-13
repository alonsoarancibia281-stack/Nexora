import 'package:flutter/material.dart';

import '../features/pulse/presentation/widgets/liquid_widgets.dart';
import 'router.dart';

/// Application theme built from the Nexora UI styleguide: warm paper canvas,
/// white surfaces, hairline borders and a single orange primary.
class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: LiquidPalette.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: LiquidPalette.primary,
      surface: LiquidPalette.surface,
      onSurface: LiquidPalette.ink,
      error: LiquidPalette.fall,
    );

    return MaterialApp.router(
      title: 'Nexora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: LiquidPalette.paper,
        canvasColor: LiquidPalette.paper,
        dividerColor: LiquidPalette.border,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: LiquidPalette.ink,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: LiquidType.title,
        ),
        cardTheme: CardThemeData(
          color: LiquidPalette.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: LiquidPalette.border),
          ),
          margin: EdgeInsets.zero,
        ),
        textTheme: const TextTheme(
          displaySmall: LiquidType.display,
          titleLarge: LiquidType.title,
          titleMedium: LiquidType.subtitle,
          bodyMedium: LiquidType.body,
          bodySmall: LiquidType.caption,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: LiquidPalette.primary,
          linearTrackColor: LiquidPalette.paperDeep,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: LiquidPalette.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: LiquidPalette.disabled,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: LiquidPalette.ink,
            side: const BorderSide(color: LiquidPalette.border),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: LiquidPalette.surface,
          hintStyle: const TextStyle(color: LiquidPalette.inkFaint),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LiquidPalette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LiquidPalette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: LiquidPalette.primary, width: 1.6),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: LiquidPalette.paperDeep,
          selectedColor: LiquidPalette.primary,
          side: const BorderSide(color: LiquidPalette.border),
          labelStyle: LiquidType.caption.copyWith(color: LiquidPalette.ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: LiquidPalette.primary,
          textColor: LiquidPalette.ink,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: LiquidPalette.ink,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
