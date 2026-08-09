import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../providers/market_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteAssetsProvider);
    return MainNavigationScaffold(
      currentIndex: 4,
      child: Scaffold(
        appBar: AppBar(title: const Text('Favoritos')),
        body: favorites.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('No pudimos cargar tus favoritos.\n$error', textAlign: TextAlign.center)),
          data: (assets) {
            if (assets.isEmpty) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Todavía no tienes favoritos. Marca una estrella en Mercado para guardar activos en este dispositivo.', textAlign: TextAlign.center),
              ));
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(marketAssetsProvider);
                await ref.read(marketAssetsProvider.future);
              },
              child: ListView.separated(
                itemCount: assets.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final asset = assets[index];
                  return ListTile(
                    onTap: () => context.go('/market/${asset.symbol}'),
                    title: Text('${asset.baseAsset}/${asset.quoteAsset}'),
                    subtitle: Text('Volumen 24h: ${asset.volume24h.toStringAsFixed(0)} USDT'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(asset.price.toStringAsPrecision(7), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${asset.changePercent24h >= 0 ? '+' : ''}${asset.changePercent24h.toStringAsFixed(2)}%',
                          style: TextStyle(color: asset.changePercent24h >= 0 ? Colors.greenAccent : Colors.redAccent),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
