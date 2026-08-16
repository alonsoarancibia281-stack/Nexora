import 'dart:math' as math;

import '../../market/domain/candle.dart';
import '../../market/domain/market_asset.dart';
import 'scan_candidate.dart';

/// What the scanner keeps and what it throws away.
class ScanFilters {
  const ScanFilters({
    this.minQuoteVolume = 8000000,
    this.minWeekChangePercent = 3,
    this.minMonthChangePercent = 8,
    this.shortlistSize = 45,
    this.resultSize = 12,
  });

  /// Money traded in 24h. Below this the pair is too thin to trade.
  final double minQuoteVolume;

  /// The week has to be going up.
  final double minWeekChangePercent;

  /// The month has to be going up too.
  final double minMonthChangePercent;

  /// How many pairs get the deeper look with daily candles.
  final int shortlistSize;

  /// How many candidates the screen shows.
  final int resultSize;
}

/// Step 01: read the whole Binance USDT market and keep only the pairs that
/// climb with strength in the week and in the month.
///
/// The scan runs in two passes because one call returns the whole market but
/// weekly and monthly strength needs daily candles per pair. The first pass
/// throws away everything cheap: no volume, falling on the day, stablecoins
/// and leveraged tokens. Only the survivors pay for a second call.
class MarketScanner {
  const MarketScanner();

  static const _stableAssets = {
    'USDC', 'FDUSD', 'TUSD', 'DAI', 'USDP', 'BUSD', 'EUR', 'EURI',
    'AEUR', 'PAX', 'USDD', 'USTC', 'XUSD', 'PYUSD',
  };

  static const _leveragedMarkers = ['UP', 'DOWN', 'BULL', 'BEAR'];

  /// Minimum daily candles needed to measure a month.
  static const minimumDays = 32;

  bool isTradable(MarketAsset asset) {
    if (asset.quoteAsset != 'USDT') return false;
    if (asset.price <= 0 || asset.volume24h <= 0) return false;
    final base = asset.baseAsset;
    if (_stableAssets.contains(base)) return false;
    for (final marker in _leveragedMarkers) {
      if (base.length > marker.length && base.endsWith(marker)) return false;
    }
    return true;
  }

  /// First pass: the pairs worth a closer look, biggest money first.
  List<MarketAsset> shortlist(
    List<MarketAsset> universe, {
    ScanFilters filters = const ScanFilters(),
  }) {
    final kept = universe
        .where(isTradable)
        .where((asset) => asset.volume24h >= filters.minQuoteVolume)
        .where((asset) => asset.changePercent24h > 0)
        .toList()
      ..sort((a, b) => b.volume24h.compareTo(a.volume24h));
    return kept.take(filters.shortlistSize).toList(growable: false);
  }

  /// Second pass: measure one pair with its daily candles.
  ///
  /// Returns null when there is not enough history to judge a month.
  ScanCandidate? measure(MarketAsset asset, List<Candle> dailyCandles) {
    if (dailyCandles.length < minimumDays) return null;
    final candles = dailyCandles.length <= 60
        ? dailyCandles
        : dailyCandles.sublist(dailyCandles.length - 60);
    final closes = candles.map((c) => c.close).toList(growable: false);
    final price = closes.last;
    if (price <= 0) return null;

    double changeOver(int days) {
      if (closes.length <= days) return 0;
      final from = closes[closes.length - 1 - days];
      return from <= 0 ? 0 : (price - from) / from * 100;
    }

    final weekChange = changeOver(7);
    final monthChange = changeOver(30);

    final monthWindow = candles.sublist(math.max(0, candles.length - 30));
    final monthHigh = monthWindow.map((c) => c.high).reduce(math.max);
    final distanceFromHigh =
        monthHigh <= 0 ? 0.0 : ((monthHigh - price) / monthHigh * 100).clamp(0.0, 100.0);

    final volumes = monthWindow.map((c) => c.volume).toList(growable: false);
    final recentVolume =
        volumes.sublist(math.max(0, volumes.length - 5)).reduce((a, b) => a + b) /
            math.min(5, volumes.length);
    final baseVolume = volumes.reduce((a, b) => a + b) / volumes.length;
    final volumeSurge = baseVolume <= 0 ? 1.0 : recentVolume / baseVolume;

    final recentDays = candles.sublist(math.max(0, candles.length - 20));
    final upDays = recentDays.where((c) => c.close > c.open).length;
    final upDayRatio = upDays / recentDays.length;

    final atrPercent = _atrPercent(candles, 14);

    return ScanCandidate(
      symbol: asset.symbol,
      baseAsset: asset.baseAsset,
      price: price,
      changePercent24h: asset.changePercent24h,
      quoteVolume24h: asset.volume24h,
      weekChangePercent: weekChange,
      monthChangePercent: monthChange,
      distanceFromMonthHighPercent: distanceFromHigh.toDouble(),
      volumeSurge: volumeSurge,
      upDayRatio: upDayRatio,
      atrPercent: atrPercent,
      strength: _strength(
        weekChange: weekChange,
        monthChange: monthChange,
        distanceFromHigh: distanceFromHigh.toDouble(),
        volumeSurge: volumeSurge,
        upDayRatio: upDayRatio,
        atrPercent: atrPercent,
      ),
    );
  }

  /// Keeps only the candidates that pass the filters, strongest first.
  List<ScanCandidate> rank(
    List<ScanCandidate> candidates, {
    ScanFilters filters = const ScanFilters(),
  }) {
    final kept = candidates
        .where((c) => c.weekChangePercent >= filters.minWeekChangePercent)
        .where((c) => c.monthChangePercent >= filters.minMonthChangePercent)
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    return kept.take(filters.resultSize).toList(growable: false);
  }

  /// 0 to 100. Strength is not just "it went up": a move with volume behind
  /// it, close to its highs and built on many green days is worth more than
  /// one big spike.
  double _strength({
    required double weekChange,
    required double monthChange,
    required double distanceFromHigh,
    required double volumeSurge,
    required double upDayRatio,
    required double atrPercent,
  }) {
    // Moves are measured against the asset's own daily range, so a calm coin
    // and a wild one are judged on the same scale.
    final unit = math.max(atrPercent, .5);
    final week = (weekChange / (unit * 3)).clamp(0.0, 1.0);
    final month = (monthChange / (unit * 7)).clamp(0.0, 1.0);
    final nearHigh = (1 - distanceFromHigh / 12).clamp(0.0, 1.0);
    final volume = ((volumeSurge - .9) / .8).clamp(0.0, 1.0);
    final steady = ((upDayRatio - .4) / .35).clamp(0.0, 1.0);

    return ((week * .28 +
                month * .24 +
                nearHigh * .20 +
                volume * .16 +
                steady * .12) *
            100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  double _atrPercent(List<Candle> candles, int period) {
    final start = math.max(1, candles.length - period);
    var total = 0.0;
    var count = 0;
    for (var i = start; i < candles.length; i++) {
      final candle = candles[i];
      final previousClose = candles[i - 1].close;
      total += math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
      count++;
    }
    final last = candles.last.close;
    if (count == 0 || last <= 0) return 0;
    return (total / count) / last * 100;
  }
}
