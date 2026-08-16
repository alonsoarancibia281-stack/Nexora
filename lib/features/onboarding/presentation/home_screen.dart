import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/format/simple_text.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../../shared/widgets/nexora_button.dart';
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
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Nexora')),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(marketAssetsProvider);
            await ref.read(marketAssetsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              // Actions come first: the user decides before reading.
              NexoraButton(
                label: 'Ver predicción BTC',
                icon: Icons.bolt,
                expand: true,
                onPressed: () => context.go('/pulse'),
              ),
              const SizedBox(height: 10),
              NexoraButton(
                label: 'Bot de ideas',
                icon: Icons.smart_toy_outlined,
                level: NexoraLevel.secondary,
                expand: true,
                onPressed: () => context.go('/bot'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NexoraButton(
                      label: 'Mercado',
                      icon: Icons.show_chart,
                      level: NexoraLevel.secondary,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/market'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NexoraButton(
                      label: 'Flujo',
                      icon: Icons.swap_vert,
                      level: NexoraLevel.secondary,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/order-book'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NexoraButton(
                      label: 'Riesgo',
                      icon: Icons.shield_outlined,
                      level: NexoraLevel.tertiary,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/risk'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NexoraButton(
                      label: 'Simulador',
                      icon: Icons.science_outlined,
                      level: NexoraLevel.tertiary,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/simulator'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NexoraButton(
                      label: 'Alertas',
                      icon: Icons.notifications_active_outlined,
                      level: NexoraLevel.quiet,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/alerts'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NexoraButton(
                      label: 'Diario',
                      icon: Icons.menu_book_outlined,
                      level: NexoraLevel.quiet,
                      expand: true,
                      compact: true,
                      onPressed: () => context.go('/journal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Resumen del mercado',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Datos públicos de Binance. Lectura educativa, no un consejo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              summary.when(
                loading: () => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No llegan los datos ahora.\n$error'),
                  ),
                ),
                data: (s) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'Activos',
                            value: '${s.totalAssets}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricCard(
                            label: 'Suben',
                            value: '${s.advancing}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricCard(
                            label: 'Bajan',
                            value: '${s.declining}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MetricCard(
                      label: 'Cambio medio 24h',
                      value: Simple.signedPercent(s.averageChange),
                    ),
                    const SizedBox(height: 16),
                    _AssetSection(title: 'Suben más hoy', assets: s.gainers),
                    const SizedBox(height: 12),
                    _AssetSection(title: 'Bajan más hoy', assets: s.losers),
                  ],
                ),
              ),
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ],
          ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...assets.map(
                (a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => context.go('/market/${a.symbol}'),
                  title: Text('${a.baseAsset}/USDT', maxLines: 1),
                  trailing: Text(
                    Simple.signedPercent(a.changePercent24h),
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
