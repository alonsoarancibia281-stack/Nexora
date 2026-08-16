import 'dart:async';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../domain/market_scanner.dart';
import '../domain/scan_candidate.dart';

/// Reads Binance for the scanner.
///
/// The whole USDT market arrives in one call. Only the shortlist pays for
/// daily candles, and those go out a few at a time so the exchange never sees
/// a burst.
class ScannerService {
  ScannerService({BinanceMarketService? market, this.scanner = const MarketScanner()})
      : _market = market ?? BinanceMarketService();

  final BinanceMarketService _market;
  final MarketScanner scanner;

  /// How many candle requests travel together.
  static const batchSize = 5;

  Future<List<Candle>> dailyCandles(String symbol, {int limit = 220}) =>
      _market.loadCandles(symbol, '1d', limit: limit);

  /// Runs the full scan and reports progress from 0 to 1.
  Future<List<ScanCandidate>> scan({
    ScanFilters filters = const ScanFilters(),
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(.05);
    final universe = await _market.loadUsdtMarket();
    final shortlist = scanner.shortlist(universe, filters: filters);
    if (shortlist.isEmpty) return const [];

    final measured = <ScanCandidate>[];
    for (var start = 0; start < shortlist.length; start += batchSize) {
      final batch = shortlist.skip(start).take(batchSize).toList(growable: false);
      final candles = await Future.wait(
        batch.map(
          (asset) => dailyCandles(asset.symbol, limit: 60).catchError(
            (_) => const <Candle>[],
          ),
        ),
      );
      for (var i = 0; i < batch.length; i++) {
        final candidate = scanner.measure(batch[i], candles[i]);
        if (candidate != null) measured.add(candidate);
      }
      onProgress?.call(
        (.05 + (start + batch.length) / shortlist.length * .9).clamp(0.0, 1.0),
      );
    }

    onProgress?.call(1);
    return scanner.rank(measured, filters: filters);
  }
}
