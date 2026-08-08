import 'package:flutter/material.dart';
import 'router.dart';

class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Nexora Markets AI',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF090D14),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B8CFF),
            brightness: Brightness.dark,
          ),
        ),
        routerConfig: appRouter,
      );
}
