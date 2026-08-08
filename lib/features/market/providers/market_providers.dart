import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/binance_market_service.dart';
import '../data/favorites_repository.dart';
import '../domain/market_asset.dart';
import '../domain/market_summary.dart';

final binanceMarketServiceProvider = Provider((_) => BinanceMarketService());
final favoritesRepositoryProvider = Provider((_) => FavoritesRepository());
final marketAssetsProvider = FutureProvider<List<MarketAsset>>(
  (ref) => ref.watch(binanceMarketServiceProvider).loadUsdtMarket(),
);
final favoritesProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(favoritesRepositoryProvider).load(),
);
final marketSummaryProvider = FutureProvider<MarketSummary>((ref) async {
  final assets = await ref.watch(marketAssetsProvider.future);
  return MarketSummary.fromAssets(assets);
});
final favoriteAssetsProvider = FutureProvider<List<MarketAsset>>((ref) async {
  final assets = await ref.watch(marketAssetsProvider.future);
  final favorites = await ref.watch(favoritesProvider.future);
  return assets.where((asset) => favorites.contains(asset.symbol)).toList();
});
final marketSearchProvider = StateProvider<String>((_) => '');
