import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../subscriptions/data/entitlements_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: EntitlementsRepository(Supabase.instance.client).load(),
        builder: (context, snapshot) {
          final entitlements = snapshot.data;
          final canAdmin = entitlements?.role == 'owner' && entitlements?.admin == true;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Nexora Markets AI'),
              actions: [
                if (canAdmin)
                  IconButton(
                    tooltip: 'Administración',
                    onPressed: () => context.go('/admin'),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                  ),
                IconButton(
                  tooltip: 'Planes',
                  onPressed: () => context.go('/plans'),
                  icon: const Icon(Icons.workspace_premium_outlined),
                ),
                IconButton(
                  tooltip: 'Perfil y seguridad',
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bienvenido a Nexora', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Fase 1 activa: identidad, seguridad y permisos.'),
                const SizedBox(height: 24),
                Card(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(entitlements == null
                      ? 'Cargando plan y permisos…'
                      : 'Plan: ${entitlements.plan} · Rol: ${entitlements.role}. Los permisos se validan en el servidor.'),
                )),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go('/plans'),
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Ver planes y límites'),
                ),
                if (canAdmin) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/admin'),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Abrir panel administrativo'),
                  ),
                ],
              ]),
            ),
          );
        },
      );
}
