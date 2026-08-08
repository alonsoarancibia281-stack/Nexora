import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/session_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final SessionRepository repository;
  late Future<List<Map<String, dynamic>>> devices;
  bool signingOut = false;

  @override
  void initState() {
    super.initState();
    repository = SessionRepository(Supabase.instance.client);
    devices = repository.listDevices();
  }

  Future<void> _signOutAll() async {
    setState(() => signingOut = true);
    try {
      await repository.signOutAllDevices();
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil y seguridad')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(user?.email ?? '', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          const Text('Dispositivos y sesiones', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: devices,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text('No pudimos cargar tus dispositivos.');
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) return const Text('Aún no hay dispositivos registrados.');
              return Column(
                children: rows.map((row) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.devices),
                    title: Text((row['platform'] ?? 'Dispositivo').toString()),
                    subtitle: Text('Última actividad: ${(row['last_seen_at'] ?? '').toString()}'),
                    trailing: row['revoked_at'] == null ? const Text('Activo') : const Text('Revocado'),
                  ),
                )).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: signingOut ? null : _signOutAll,
            icon: const Icon(Icons.logout),
            label: Text(signingOut ? 'Cerrando sesiones…' : 'Cerrar sesión en todos los dispositivos'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await repository.signOutCurrent();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Cerrar esta sesión'),
          ),
        ],
      ),
    );
  }
}
