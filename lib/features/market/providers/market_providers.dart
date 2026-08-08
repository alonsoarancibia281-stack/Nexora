import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/binance_market_service.dart';
import '../data/favorites_repository.dart';
import '../domain/market_asset.dart';

final binanceMarketServiceProvider=Provider((_)=>BinanceMarketService());
final favoritesRepositoryProvider=Provider((_)=>FavoritesRepository());
final marketAssetsProvider=FutureProvider<List<MarketAsset>>((ref)=>ref.watch(binanceMarketServiceProvider).loadUsdtMarket());
final favoritesProvider=FutureProvider<Set<String>>((ref)=>ref.watch(favoritesRepositoryProvider).load());
final marketSearchProvider=StateProvider<String>((_)=>'');
