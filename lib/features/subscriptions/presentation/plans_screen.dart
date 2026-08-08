import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/entitlements_repository.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = EntitlementsRepository(Supabase.instance.client);
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      body: FutureBuilder(
        future: repository.load(),
        builder: (context, snapshot) {
          final currentPlan = snapshot.data?.plan ?? 'free';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Tu plan actual: ${currentPlan.toUpperCase()}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              const _PlanCard(name: 'Free', price: 'Gratis', features: ['3 análisis diarios', '1 alerta activa', 'Academia básica']),
              const _PlanCard(name: 'Essential', price: 'USD 9.99/mes', features: ['Más análisis', '20 alertas', 'Datos en tiempo real']),
              const _PlanCard(name: 'Pro Trader', price: 'USD 29.99/mes', features: ['IA avanzada', 'Múltiples temporalidades', 'Diario y estadísticas']),
              const _PlanCard(name: 'Elite AI', price: 'USD 79.99/mes', features: ['Backtesting', 'Reportes automáticos', 'Funciones experimentales']),
              const SizedBox(height: 12),
              const Text('Los planes superiores ofrecen más herramientas, profundidad y soporte. No garantizan ganancias ni resultados financieros.'),
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.name, required this.price, required this.features});
  final String name;
  final String price;
  final List<String> features;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(price, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [const Icon(Icons.check, size: 18), const SizedBox(width: 8), Expanded(child: Text(feature))]),
                )),
          ]),
        ),
      );
}
