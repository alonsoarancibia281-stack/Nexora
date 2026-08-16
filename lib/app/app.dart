import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/theme/nexora_theme.dart';
import '../shared/theme/theme_controller.dart';
import '../shared/widgets/shader_gradient.dart';
import 'router.dart';

class NexoraApp extends ConsumerWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Nexora',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: NexoraTheme.light(),
      darkTheme: NexoraTheme.dark(),
      // The gradient sits behind every route, so screens stay transparent.
      builder: (context, child) =>
          ShaderGradientBackground(child: child ?? const SizedBox.shrink()),
      routerConfig: appRouter,
    );
  }
}
