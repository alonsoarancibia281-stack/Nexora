import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/nexora_theme.dart';
import '../../../shared/theme/theme_controller.dart';
import '../../../shared/widgets/nexora_button.dart';
import '../../../shared/widgets/nexora_shell.dart';

/// Look and feel of the app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final brightness = Theme.of(context).brightness;
    return NexoraShell(
      currentIndex: 7,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Ajustes')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            NexoraSegmented<ThemeMode>(
              values: ThemeMode.values,
              selected: mode,
              labelOf: (value) => value.label,
              iconOf: (value) => value.icon,
              onSelected: (value) =>
                  ref.read(themeModeProvider.notifier).select(value),
            ),
            const SizedBox(height: 10),
            NexoraButton(
              label: brightness == Brightness.dark
                  ? 'Cambiar a modo claro'
                  : 'Cambiar a modo oscuro',
              icon: brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              level: NexoraLevel.secondary,
              expand: true,
              onPressed: () =>
                  ref.read(themeModeProvider.notifier).toggle(brightness),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tema',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sistema sigue al teléfono. Claro y oscuro mandan siempre.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(),
                    const Text(
                      'Avisos',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'La pantalla de predicción avisa cuando abre una señal, '
                      'cuando cambia de lado y cuando toca salir antes del cierre.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(),
                    const Text(
                      'Colores',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: const [
                        _Swatch(color: NexoraTheme.up, label: 'Sube'),
                        _Swatch(color: NexoraTheme.down, label: 'Baja'),
                        _Swatch(color: NexoraTheme.warn, label: 'Espera'),
                        _Swatch(color: NexoraTheme.brand, label: 'Nexora'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      );
}
