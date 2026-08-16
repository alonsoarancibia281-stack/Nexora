import 'package:flutter/material.dart';

import 'nexora_shell.dart';

/// Kept for the screens that already use it. The frame now comes from
/// [NexoraShell], so the side bar and the bottom pills stay in one place.
class MainNavigationScaffold extends StatelessWidget {
  const MainNavigationScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  final Widget child;
  final int currentIndex;

  @override
  Widget build(BuildContext context) =>
      NexoraShell(currentIndex: currentIndex, child: child);
}
