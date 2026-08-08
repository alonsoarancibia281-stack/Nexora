import 'package:flutter/material.dart';
import 'router.dart';

class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Nexora',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF03070D),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF21E6B1),
            brightness: Brightness.dark,
            surface: const Color(0xFF09131C),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Color(0xFF45F17C),
            linearTrackColor: Color(0xFF17313A),
          ),
          cardTheme: const CardThemeData(color: Color(0xFF09131C)),
        ),
        routerConfig: appRouter,
      );
}
