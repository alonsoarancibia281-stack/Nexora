import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../market/domain/market_asset.dart';
import '../../market/providers/market_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(marketSummaryProvider);
    return MainNavigationScaffold(
      currentIndex: 0,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nexora Markets AI')),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(marketAssetsProvider);
            await ref.read(marketAssetsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Resumen del mercado', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Datos públicos de Binance. Lectura educativa y probabilística, no una recomendación de inversión.'),
              const SizedBox(height: 20),
              summary.when(
                loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
                error: (error, _) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('No pudimos cargar el resumen.\n$error'))),
                data: (s) => Column(children: [
                  Row(children: [
                    Expanded(child: _MetricCard(label: 'Activos', value: '${s.totalAssets}')),
                    const SizedBox(width: 10),
                    Expanded(child: _MetricCard(label: 'Subiendo', value: '${s.advancing}')),
                    const SizedBox(width: 10),
                    Expanded(child: _MetricCard(label: 'Bajando', value: '${s.declining}')),
                  ]),
                  const SizedBox(height: 10),
                  _MetricCard(label: 'Cambio medio 24h', value: '${s.averageChange >= 0 ? '+' : ''}${s.averageChange.toStringAsFixed(2)}%'),
                  const SizedBox(height: 18),
                  _AssetSection(title: 'Mayores subidas 24h', assets: s.gainers),
                  const SizedBox(height: 14),
                  _AssetSection(title: 'Mayores caídas 24h', assets: s.losers),
                ]),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: () => context.go('/pulse'), icon: const Icon(Icons.bolt), label: const Text('Nexora Pulse · Predicción 4 min')),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: () => context.push('/futures'), icon: const Icon(Icons.candlestick_chart), label: const Text('Nexora Futures · Plan BTCUSDT 3x')),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: () => context.go('/market'), icon: const Icon(Icons.show_chart), label: const Text('Explorar mercado')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () => context.go('/risk'), icon: const Icon(Icons.shield_outlined), label: const Text('Calcular gestión de riesgo')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () => context.go('/simulator'), icon: const Icon(Icons.science_outlined), label: const Text('Abrir simulador educativo')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () => context.go('/alerts'), icon: const Icon(Icons.notifications_active_outlined), label: const Text('Alertas locales')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () => context.go('/journal'), icon: const Icon(Icons.menu_book_outlined), label: const Text('Diario de trading')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

class _AssetSection extends StatelessWidget {
  const _AssetSection({required this.title, required this.assets});
  final String title;
  final List<MarketAsset> assets;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...assets.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => context.go('/market/${a.symbol}'),
                  title: Text('${a.baseAsset}/USDT'),
                  trailing: Text('${a.changePercent24h >= 0 ? '+' : ''}${a.changePercent24h.toStringAsFixed(2)}%'),
                )),
          ]),
        ),
      );
}
