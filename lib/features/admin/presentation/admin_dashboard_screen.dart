import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../subscriptions/data/entitlements_repository.dart';
import '../data/admin_repository.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminRepository admin;
  late Future<Map<String, dynamic>> metrics;
  late Future<List<Map<String, dynamic>>> users;
  late Future<List<Map<String, dynamic>>> flags;
  final search = TextEditingController();

  @override void initState() {
    super.initState();
    final client = Supabase.instance.client;
    admin = AdminRepository(client);
    metrics = admin.loadMetrics();
    users = admin.listUsers();
    flags = admin.listFeatureFlags();
  }

  Future<bool> _isOwner() async {
    final entitlements = await EntitlementsRepository(Supabase.instance.client).load();
    return entitlements.role == 'owner' && entitlements.admin;
  }

  void _refresh() => setState(() {
        metrics = admin.loadMetrics();
        users = admin.listUsers(query: search.text.trim());
        flags = admin.listFeatureFlags();
      });

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(title), content: Text(message), actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      )) ?? false;

  @override Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _isOwner(),
    builder: (context, access) {
      if (access.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (access.data != true) {
        return const Scaffold(body: Center(child: Text('Acceso no autorizado.')));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Panel administrativo Nexora'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          FutureBuilder<Map<String, dynamic>>(future: metrics, builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final m = snapshot.data!;
            final entries = <String, dynamic>{
              'Usuarios': m['total_users'], 'Verificados': m['verified_users'], 'Suspendidos': m['suspended_users'],
              'Suscripciones activas': m['active_subscriptions'], 'Flags activos': m['feature_flags_enabled'], 'Auditoría 24h': m['audit_events_24h'],
            };
            return Wrap(spacing: 12, runSpacing: 12, children: entries.entries.map((e) => SizedBox(width: 180, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.key), const SizedBox(height: 8), Text('${e.value ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))]))))).toList());
          }),
          const SizedBox(height: 28),
          const Text('Usuarios', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: search, decoration: InputDecoration(labelText: 'Buscar por nombre o UUID', suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _refresh))),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(future: users, builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
            if (snapshot.hasError) return const Text('No se pudieron cargar los usuarios.');
            final rows = snapshot.data ?? const [];
            return Column(children: rows.map((u) {
              final isOwner = u['role'] == 'owner';
              final suspended = u['suspended_at'] != null;
              return Card(child: ExpansionTile(
                title: Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim().isEmpty ? u['user_id'].toString() : '${u['first_name']} ${u['last_name']}'),
                subtitle: Text('Plan ${u['plan']} · Rol ${u['role']} · ${u['email_verified'] == true ? 'Verificado' : 'Pendiente'}'),
                children: [
                  Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('País: ${u['country']} · Nivel: ${u['experience']}'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: ['free','essential','pro','elite'].contains(u['plan']) ? u['plan'] as String : 'free',
                      items: const [DropdownMenuItem(value:'free',child:Text('Free')),DropdownMenuItem(value:'essential',child:Text('Essential')),DropdownMenuItem(value:'pro',child:Text('Pro Trader')),DropdownMenuItem(value:'elite',child:Text('Elite AI'))],
                      onChanged: isOwner ? null : (plan) async { if (plan == null) return; if (!await _confirm('Cambiar plan','¿Cambiar el plan de este usuario a $plan?')) return; await admin.setPlan(u['user_id'].toString(), plan); _refresh(); },
                      decoration: const InputDecoration(labelText: 'Plan'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isOwner ? null : () async { if (!await _confirm(suspended ? 'Reactivar cuenta' : 'Suspender cuenta', suspended ? '¿Reactivar esta cuenta?' : '¿Suspender esta cuenta?')) return; await admin.setSuspension(u['user_id'].toString(), !suspended); _refresh(); },
                      icon: Icon(suspended ? Icons.lock_open : Icons.block), label: Text(suspended ? 'Reactivar cuenta' : 'Suspender cuenta'),
                    )
                  ])),
                ],
              ));
            }).toList());
          }),
          const SizedBox(height: 28),
          const Text('Feature flags', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          FutureBuilder<List<Map<String, dynamic>>>(future: flags, builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No hay feature flags configurados todavía.'));
            return Column(children: rows.map((f) => SwitchListTile(
              title: Text(f['key'].toString()), subtitle: Text((f['description'] ?? '').toString()), value: f['enabled'] == true,
              onChanged: (value) async { if (!await _confirm('Cambiar función','¿${value ? 'Activar' : 'Desactivar'} ${f['key']}?')) return; await admin.setFeatureFlag(f['key'].toString(), value); _refresh(); },
            )).toList());
          }),
        ]),
      );
    },
  );

  @override void dispose() { search.dispose(); super.dispose(); }
}
