import 'dart:math' as math;

import '../../market/domain/candle.dart';
import 'prediction_horizon.dart';

/// Live order book numbers.
class BookSnapshotMetrics {
  const BookSnapshotMetrics({
    required this.bidVolume,
    required this.askVolume,
    required this.spreadBps,
    required this.micropriceEdgeBps,
  });

  const BookSnapshotMetrics.empty()
      : bidVolume = 0,
        askVolume = 0,
        spreadBps = 0,
        micropriceEdgeBps = 0;

  final double bidVolume;
  final double askVolume;
  final double spreadBps;
  final double micropriceEdgeBps;
}

/// Live trade flow numbers.
class TradeFlowMetrics {
  const TradeFlowMetrics({
    required this.aggressorImbalance,
    required this.signedVolume,
    required this.tradeAcceleration,
    required this.priceImpulseBps,
  });

  const TradeFlowMetrics.empty()
      : aggressorImbalance = 0,
        signedVolume = 0,
        tradeAcceleration = 0,
        priceImpulseBps = 0;

  final double aggressorImbalance;
  final double signedVolume;
  final double tradeAcceleration;
  final double priceImpulseBps;
}

/// Everything the agents read, already normalised.
///
/// Most fields land between -1 and 1, and they are measured in units of the
/// current volatility. That way the same agent works on a 5 minute round and
/// on a 1 hour round without changing its thresholds.
class MarketReading {
  const MarketReading({
    required this.horizon,
    required this.price,
    required this.startPrice,
    required this.secondsLeft,
    required this.elapsed,
    required this.momentum,
    required this.acceleration,
    required this.trend,
    required this.slope,
    required this.contextTrend,
    required this.persistence,
    required this.bodyPressure,
    required this.wickNoise,
    required this.rangePosition,
    required this.zPrice,
    required this.rsi,
    required this.vwapDistance,
    required this.atrPercent,
    required this.volatilityPerBar,
    required this.driftPerBar,
    required this.autocorrelation,
    required this.volumeRatio,
    required this.rangeExpansion,
    required this.bookImbalance,
    required this.micropriceEdge,
    required this.spreadBps,
    required this.flowImbalance,
    required this.flowAcceleration,
    required this.signedVolume,
    required this.priceImpulse,
    required this.expectedMovePercent,
    required this.roundDistancePercent,
    required this.instability,
    required this.liquidityQuality,
    required this.bars,
  });

  final PredictionHorizon horizon;

  /// Last traded price.
  final double price;

  /// Price the round opened at.
  final double startPrice;

  final int secondsLeft;

  /// Share of the round already gone, 0 to 1.
  final double elapsed;

  final double momentum;
  final double acceleration;
  final double trend;
  final double slope;
  final double contextTrend;
  final double persistence;
  final double bodyPressure;
  final double wickNoise;
  final double rangePosition;
  final double zPrice;
  final double rsi;
  final double vwapDistance;
  final double atrPercent;
  final double volatilityPerBar;
  final double driftPerBar;
  final double autocorrelation;
  final double volumeRatio;
  final double rangeExpansion;
  final double bookImbalance;
  final double micropriceEdge;
  final double spreadBps;
  final double flowImbalance;
  final double flowAcceleration;
  final double signedVolume;
  final double priceImpulse;

  /// How far the price can still travel before the round closes.
  final double expectedMovePercent;

  /// Distance from the round open, in percent.
  final double roundDistancePercent;

  /// 0 calm, 100 wild.
  final double instability;

  /// 0 thin book, 1 deep and tight book.
  final double liquidityQuality;

  /// Base candles used.
  final int bars;

  /// Distance already covered, measured against what is still possible.
  /// Above 1 means the move is bigger than what the rest of the round
  /// usually produces.
  double get roundEdge => expectedMovePercent <= 0
      ? 0
      : (roundDistancePercent / expectedMovePercent).clamp(-3.0, 3.0).toDouble();

  bool get isUpSoFar => price > startPrice;
}

/// Turns raw Binance data into a [MarketReading].
class MarketReadingBuilder {
  const MarketReadingBuilder();

  static const minimumBars = 40;

  /// Returns null when there is not enough history to say anything honest.
  MarketReading? build({
    required PredictionHorizon horizon,
    required List<Candle> baseCandles,
    required List<Candle> contextCandles,
    required double startPrice,
    required int secondsLeft,
    BookSnapshotMetrics book = const BookSnapshotMetrics.empty(),
    TradeFlowMetrics flow = const TradeFlowMetrics.empty(),
  }) {
    if (baseCandles.length < minimumBars || startPrice <= 0) return null;

    final candles = baseCandles.length <= 90
        ? baseCandles
        : baseCandles.sublist(baseCandles.length - 90);
    final closes = candles.map((c) => c.close).toList(growable: false);
    final price = closes.last;
    if (price <= 0) return null;

    final safeSeconds = secondsLeft.clamp(0, horizon.totalSeconds);
    final elapsed =
        (1 - safeSeconds / horizon.totalSeconds).clamp(0.0, 1.0).toDouble();

    final atrPercent = math.max(_atrPercent(candles, 14), 0.005);
    // One unit of "normal move" for this market, in percent.
    double byAtr(double percentMove, double bars) =>
        (percentMove / (atrPercent * math.sqrt(math.max(bars, 1))))
            .clamp(-1.0, 1.0)
            .toDouble();

    double changePct(int back) {
      if (closes.length <= back) return 0;
      final from = closes[closes.length - 1 - back];
      return from == 0 ? 0 : (price - from) / from * 100;
    }

    final momentum = byAtr(changePct(3), 3);
    final previousLeg = closes.length <= 6
        ? 0.0
        : (closes[closes.length - 4] - closes[closes.length - 7]) /
            closes[closes.length - 7] *
            100;
    final acceleration = byAtr(changePct(3) - previousLeg, 3);

    final emaFast = _ema(closes, 8);
    final emaSlow = _ema(closes, 21);
    final trend =
        emaSlow == 0 ? 0.0 : byAtr((emaFast - emaSlow) / emaSlow * 100, 6);
    final slope = byAtr(
      _slopePercentPerBar(closes.sublist(math.max(0, closes.length - 12))) * 6,
      6,
    );

    var contextTrend = 0.0;
    if (contextCandles.length >= 12) {
      final ctxCloses = contextCandles.map((c) => c.close).toList();
      final fast = _ema(ctxCloses, 6);
      final slow = _ema(ctxCloses, 18);
      final ctxAtr = math.max(_atrPercent(contextCandles, 14), 0.01);
      contextTrend = slow == 0
          ? 0.0
          : (((fast - slow) / slow * 100) / (ctxAtr * 1.4))
              .clamp(-1.0, 1.0)
              .toDouble();
    }

    final recentSeven = candles.sublist(math.max(0, candles.length - 7));
    var persistence = 0.0;
    for (final candle in recentSeven) {
      if (candle.close > candle.open) {
        persistence++;
      } else if (candle.close < candle.open) {
        persistence--;
      }
    }
    persistence =
        (persistence / recentSeven.length).clamp(-1.0, 1.0).toDouble();

    final pressureCandles = candles.sublist(math.max(0, candles.length - 6));
    var bodyPressure = 0.0;
    var wickNoise = 0.0;
    for (final candle in pressureCandles) {
      final range = candle.high - candle.low;
      if (range <= 0) continue;
      final body = (candle.close - candle.open).abs();
      bodyPressure += ((candle.close - candle.open) / range).clamp(-1.0, 1.0);
      wickNoise += (1 - body / range).clamp(0.0, 1.0);
    }
    bodyPressure =
        (bodyPressure / pressureCandles.length).clamp(-1.0, 1.0).toDouble();
    wickNoise =
        (wickNoise / pressureCandles.length).clamp(0.0, 1.0).toDouble();

    final rangeCandles = candles.sublist(math.max(0, candles.length - 14));
    final rangeHigh = rangeCandles.map((c) => c.high).reduce(math.max);
    final rangeLow = rangeCandles.map((c) => c.low).reduce(math.min);
    final span = rangeHigh - rangeLow;
    final rangePosition = span <= 0
        ? 0.0
        : (((price - rangeLow) / span) * 2 - 1).clamp(-1.0, 1.0).toDouble();

    final window = candles.sublist(math.max(0, candles.length - 20));
    final mean = window.map((c) => c.close).reduce((a, b) => a + b) /
        window.length;
    final variance = window
            .map((c) => math.pow(c.close - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        window.length;
    final sigma = math.sqrt(variance);
    final zPrice = sigma <= 0
        ? 0.0
        : (((price - mean) / sigma) / 2.5).clamp(-1.0, 1.0).toDouble();

    final rsi = _rsi(closes, 14);
    final vwap = _vwap(window);
    final vwapDistance =
        vwap <= 0 ? 0.0 : byAtr((price - vwap) / vwap * 100, 4);

    final volumes = candles.map((c) => c.volume).toList(growable: false);
    final recentVolume =
        volumes.sublist(volumes.length - 4).reduce((a, b) => a + b) / 4;
    final baselineWindow = volumes.sublist(math.max(0, volumes.length - 20));
    final baselineVolume =
        baselineWindow.reduce((a, b) => a + b) / baselineWindow.length;
    final volumeRatio = baselineVolume <= 0 ? 1.0 : recentVolume / baselineVolume;

    final ranges = window.map((c) => c.high - c.low).toList(growable: false);
    final averageRange = ranges.reduce((a, b) => a + b) / ranges.length;
    final lastRange = candles.last.high - candles.last.low;
    final rangeExpansion = averageRange <= 0
        ? 0.0
        : ((lastRange / averageRange) - 1).clamp(-1.0, 1.0).toDouble();

    final logReturns = <double>[];
    for (var i = 1; i < closes.length; i++) {
      if (closes[i - 1] > 0 && closes[i] > 0) {
        logReturns.add(math.log(closes[i] / closes[i - 1]));
      }
    }
    final driftPerBar = _expWeightedMean(logReturns, .92);
    final volatilityPerBar = math.sqrt(_ewmaVariance(logReturns, .94));
    final autocorrelation = _lag1Correlation(logReturns).clamp(-.5, .5).toDouble();

    final depthTotal = book.bidVolume + book.askVolume;
    final bookImbalance = depthTotal <= 0
        ? 0.0
        : ((book.bidVolume - book.askVolume) / depthTotal)
            .clamp(-1.0, 1.0)
            .toDouble();
    final micropriceEdge =
        (book.micropriceEdgeBps / 2.0).clamp(-1.0, 1.0).toDouble();
    final liquidityQuality = depthTotal <= 0
        ? 0.0
        : (1 / (1 + book.spreadBps / 2.5)).clamp(0.0, 1.0).toDouble();

    final priceImpulse = (flow.priceImpulseBps / 10).clamp(-1.0, 1.0).toDouble();

    // How far price can still travel before the round closes.
    final barsLeft = math.max(safeSeconds / 60.0 / horizon.baseMinutes, .15);
    final expectedMovePercent =
        math.max(atrPercent * math.sqrt(barsLeft) * .72, .02);
    final roundDistancePercent = (price - startPrice) / startPrice * 100;

    var flips = 0;
    final flipCandles = candles.sublist(math.max(0, candles.length - 9));
    int direction(Candle c) => c.close > c.open
        ? 1
        : c.close < c.open
            ? -1
            : 0;
    var previous = direction(flipCandles.first);
    for (final candle in flipCandles.skip(1)) {
      final current = direction(candle);
      if (previous != 0 && current != 0 && previous != current) flips++;
      if (current != 0) previous = current;
    }
    final atrInstability = ((atrPercent - .10) / .55).clamp(0.0, 1.0).toDouble();
    final volumeShock = ((volumeRatio - 1.25) / 1.75).clamp(0.0, 1.0).toDouble();
    final instability = ((atrInstability * .34 +
                (flips / math.max(flipCandles.length - 1, 1)) * .26 +
                wickNoise * .22 +
                volumeShock * .08 +
                (1 - liquidityQuality) * .10) *
            100)
        .clamp(0.0, 100.0)
        .toDouble();

    return MarketReading(
      horizon: horizon,
      price: price,
      startPrice: startPrice,
      secondsLeft: safeSeconds,
      elapsed: elapsed,
      momentum: momentum,
      acceleration: acceleration,
      trend: trend,
      slope: slope,
      contextTrend: contextTrend,
      persistence: persistence,
      bodyPressure: bodyPressure,
      wickNoise: wickNoise,
      rangePosition: rangePosition,
      zPrice: zPrice,
      rsi: rsi,
      vwapDistance: vwapDistance,
      atrPercent: atrPercent,
      volatilityPerBar: volatilityPerBar,
      driftPerBar: driftPerBar,
      autocorrelation: autocorrelation,
      volumeRatio: volumeRatio,
      rangeExpansion: rangeExpansion,
      bookImbalance: bookImbalance,
      micropriceEdge: micropriceEdge,
      spreadBps: book.spreadBps,
      flowImbalance: flow.aggressorImbalance.clamp(-1.0, 1.0).toDouble(),
      flowAcceleration: flow.tradeAcceleration.clamp(-1.0, 1.0).toDouble(),
      signedVolume: flow.signedVolume.clamp(-1.0, 1.0).toDouble(),
      priceImpulse: priceImpulse,
      expectedMovePercent: expectedMovePercent,
      roundDistancePercent: roundDistancePercent,
      instability: instability,
      liquidityQuality: liquidityQuality,
      bars: candles.length,
    );
  }

  double _ema(List<double> values, int period) {
    final k = 2 / (period + 1);
    var value = values.first;
    for (final next in values.skip(1)) {
      value = next * k + value * (1 - k);
    }
    return value;
  }

  double _rsi(List<double> closes, int period) {
    if (closes.length <= period) return 50;
    var gain = 0.0;
    var loss = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      final delta = closes[i] - closes[i - 1];
      if (delta > 0) {
        gain += delta;
      } else {
        loss -= delta;
      }
    }
    if (loss == 0) return gain == 0 ? 50 : 100;
    return 100 - (100 / (1 + gain / loss));
  }

  double _vwap(List<Candle> candles) {
    var weighted = 0.0;
    var volume = 0.0;
    for (final candle in candles) {
      weighted += ((candle.high + candle.low + candle.close) / 3) * candle.volume;
      volume += candle.volume;
    }
    return volume <= 0 ? candles.last.close : weighted / volume;
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

  double _slopePercentPerBar(List<double> values) {
    if (values.length < 2 || values.last == 0) return 0;
    final n = values.length.toDouble();
    var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < values.length; i++) {
      final x = i.toDouble();
      final y = values[i];
      sx += x;
      sy += y;
      sxy += x * y;
      sxx += x * x;
    }
    final denominator = n * sxx - sx * sx;
    if (denominator == 0) return 0;
    return ((n * sxy - sx * sy) / denominator) / values.last * 100;
  }

  double _expWeightedMean(List<double> values, double lambda) {
    if (values.isEmpty) return 0;
    var weight = 1.0;
    var weighted = 0.0;
    var total = 0.0;
    for (final value in values.reversed) {
      weighted += value * weight;
      total += weight;
      weight *= lambda;
    }
    return total == 0 ? 0 : weighted / total;
  }

  double _ewmaVariance(List<double> values, double lambda) {
    if (values.isEmpty) return 0;
    var variance = values.first * values.first;
    for (final value in values.skip(1)) {
      variance = lambda * variance + (1 - lambda) * value * value;
    }
    return variance;
  }

  double _lag1Correlation(List<double> values) {
    if (values.length < 3) return 0;
    final a = values.sublist(0, values.length - 1);
    final b = values.sublist(1);
    final meanA = a.reduce((x, y) => x + y) / a.length;
    final meanB = b.reduce((x, y) => x + y) / b.length;
    var covariance = 0.0, varianceA = 0.0, varianceB = 0.0;
    for (var i = 0; i < a.length; i++) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      covariance += da * db;
      varianceA += da * da;
      varianceB += db * db;
    }
    final denominator = math.sqrt(varianceA * varianceB);
    return denominator <= 1e-12 ? 0 : covariance / denominator;
  }
}
