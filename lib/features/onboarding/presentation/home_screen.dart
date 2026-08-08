import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Nexora Markets AI'),
          actions: [
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
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('El plan y los permisos se validan en el servidor.'))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/plans'),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Ver planes y límites'),
            ),
          ]),
        ),
      );
}
