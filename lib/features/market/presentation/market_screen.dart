import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/market_providers.dart';

class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(marketAssetsProvider);
    final favorites = ref.watch(favoritesProvider).value ?? {};
    final query = ref.watch(marketSearchProvider).trim().toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mercado'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(marketAssetsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => ref.read(marketSearchProvider.notifier).state = value,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar BTC, ETH, SOL…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: assets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No pudimos cargar el mercado.\n$error', textAlign: TextAlign.center),
                ),
              ),
              data: (items) {
                final filtered = items
                    .where((asset) => query.isEmpty || asset.symbol.contains(query) || asset.baseAsset.contains(query))
                    .take(100)
                    .toList();
                if (filtered.isEmpty) return const Center(child: Text('No encontramos ese activo.'));

                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(marketAssetsProvider.future),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final asset = filtered[index];
                      final favorite = favorites.contains(asset.symbol);
                      final initials = asset.baseAsset.length <= 3 ? asset.baseAsset : asset.baseAsset.substring(0, 3);

                      return ListTile(
                        onTap: () => context.go('/market/${asset.symbol}'),
                        leading: CircleAvatar(child: Text(initials)),
                        title: Text('${asset.baseAsset}/${asset.quoteAsset}'),
                        subtitle: Text('Volumen 24h: ${_compact(asset.volume24h)} USDT'),
                        trailing: SizedBox(
                          width: 130,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_price(asset.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      '${asset.changePercent24h >= 0 ? '+' : ''}${asset.changePercent24h.toStringAsFixed(2)}%',
                                      style: TextStyle(color: asset.changePercent24h >= 0 ? Colors.greenAccent : Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: favorite ? 'Quitar de favoritos' : 'Agregar a favoritos',
                                onPressed: () async {
                                  await ref.read(favoritesRepositoryProvider).toggle(asset.symbol);
                                  ref.invalidate(favoritesProvider);
                                },
                                icon: Icon(favorite ? Icons.star : Icons.star_border),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _price(double value) => value >= 1000
      ? value.toStringAsFixed(2)
      : value >= 1
          ? value.toStringAsFixed(4)
          : value.toStringAsPrecision(6);

  String _compact(double value) => value >= 1e9
      ? '${(value / 1e9).toStringAsFixed(2)}B'
      : value >= 1e6
          ? '${(value / 1e6).toStringAsFixed(2)}M'
          : value >= 1e3
              ? '${(value / 1e3).toStringAsFixed(1)}K'
              : value.toStringAsFixed(0);
}
