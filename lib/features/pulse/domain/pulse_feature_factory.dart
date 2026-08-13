import 'dart:math' as math;

import '../../market/domain/candle.dart';
import 'pulse_ensemble_100.dart';
import 'pulse_math_council.dart';
import 'pulse_signal.dart';
import 'pulse_statistical_engine.dart';

/// Everything observed in a single market review cycle.
class PulseMarketFrame {
  const PulseMarketFrame({
    required this.candles,
    required this.referenceCandles,
    required this.bidVolume,
    required this.askVolume,
    required this.spreadBps,
    required this.micropriceEdge,
    required this.nearImbalance,
    required this.queueImbalance,
    required this.aggressorImbalance,
    required this.signedVolume,
    required this.tradeAcceleration,
    required this.priceImpulseBps,
    required this.flowPersistence,
    required this.largeTradeBias,
    required this.roundStartPrice,
    required this.secondsRemaining,
  });

  /// BTC 1-minute candles, oldest first.
  final List<Candle> candles;

  /// ETH 1-minute candles used for the intermarket team.
  final List<Candle> referenceCandles;

  final double bidVolume;
  final double askVolume;
  final double spreadBps;
  final double micropriceEdge;

  /// Imbalance restricted to the levels closest to the touch.
  final double nearImbalance;

  /// Imbalance of the best bid/ask queues only.
  final double queueImbalance;

  final double aggressorImbalance;
  final double signedVolume;
  final double tradeAcceleration;
  final double priceImpulseBps;

  /// Fraction of consecutive trades hitting the same side, signed.
  final double flowPersistence;

  /// Signed share of volume traded by the largest orders.
  final double largeTradeBias;

  final double? roundStartPrice;
  final int secondsRemaining;

  double get price => candles.isEmpty ? 0 : candles.last.close;

  double get bookImbalance {
    final total = bidVolume + askVolume;
    if (total <= 0) return 0;
    return ((bidVolume - askVolume) / total).clamp(-1.0, 1.0).toDouble();
  }
}

/// Translates raw exchange data into the normalized feature vocabulary the 100
/// analysts speak, and into the numeric context the 50 mathematicians need.
class PulseFeatureFactory {
  const PulseFeatureFactory();

  MathContext buildMathContext(PulseMarketFrame frame) => MathContext(
        closes: [for (final c in frame.candles) c.close],
        highs: [for (final c in frame.candles) c.high],
        lows: [for (final c in frame.candles) c.low],
        volumes: [for (final c in frame.candles) c.volume],
        roundStartPrice: frame.roundStartPrice ?? frame.price,
        secondsRemaining: frame.secondsRemaining,
        bookImbalance: frame.bookImbalance,
        aggressorImbalance: frame.aggressorImbalance,
        signedVolume: frame.signedVolume,
        spreadBps: frame.spreadBps,
        micropriceEdge: frame.micropriceEdge,
        instability: 0,
      );

  MathContext withInstability(MathContext context, double instability) =>
      MathContext(
        closes: context.closes,
        highs: context.highs,
        lows: context.lows,
        volumes: context.volumes,
        roundStartPrice: context.roundStartPrice,
        secondsRemaining: context.secondsRemaining,
        bookImbalance: context.bookImbalance,
        aggressorImbalance: context.aggressorImbalance,
        signedVolume: context.signedVolume,
        spreadBps: context.spreadBps,
        micropriceEdge: context.micropriceEdge,
        instability: instability,
      );

  AnalystInput buildAnalystInput({
    required PulseMarketFrame frame,
    required PulseSignal signal,
    required PulseStatisticalResult statistical,
  }) {
    final candles = frame.candles;
    final closes = [for (final c in candles) c.close];
    final current = closes.isEmpty ? 0.0 : closes.last;
    final instability = signal.instabilityScore;

    final momentum = signal.momentumScore / 100;
    final trend = signal.trendScore / 100;
    final bodyPressure = signal.bodyPressure / 100;
    final momentumSign = momentum == 0 ? 0.0 : momentum.sign;
    final trendSign = trend == 0 ? 0.0 : trend.sign;

    final ret3 = _pct(closes, 3);
    final ret9 = _pct(closes, 9);
    final ret1 = _pct(closes, 1);
    final prevRet3 = _pctAt(closes, 3, 3);
    final acceleration = ret3 - prevRet3;

    final atrAbs = _atrAbsolute(candles, 14);
    final atrPct = current <= 0 ? 0.0 : atrAbs / current * 100;
    final atrBaseline = _atrAbsolute(candles, 45);
    final atrPctBaseline = current <= 0 ? 0.0 : atrBaseline / current * 100;

    final ema5 = _ema(closes, 5);
    final ema21 = _ema(closes, 21);
    final ema55 = _ema(closes, 55);
    final rsi = _rsi(closes, 14);
    final vwap = _vwap(_tailCandles(candles, 20));

    final recent = _tailCandles(candles, 20);
    final recentCloses = [for (final c in recent) c.close];
    final mean20 = _mean(recentCloses);
    final sigma20 = math.max(_std(recentCloses), 1e-9);
    final zPrice = ((current - mean20) / sigma20).clamp(-3.0, 3.0) / 3.0;
    final bandPosition = ((current - mean20) / (2 * sigma20))
        .clamp(-1.0, 1.0)
        .toDouble();

    final rangeWindow = _tailCandles(candles, 12);
    final rangeHigh = rangeWindow.isEmpty
        ? current
        : rangeWindow.map((c) => c.high).reduce(math.max);
    final rangeLow = rangeWindow.isEmpty
        ? current
        : rangeWindow.map((c) => c.low).reduce(math.min);
    final rangeSpan = math.max(rangeHigh - rangeLow, 1e-9);
    final lastRange = candles.isEmpty ? 0.0 : candles.last.high - candles.last.low;
    final avgRange = recent.isEmpty
        ? 0.0
        : recent.map((c) => c.high - c.low).reduce((a, b) => a + b) /
            recent.length;
    final rangeExpansion = avgRange <= 0
        ? 0.0
        : ((lastRange / avgRange) - 1).clamp(-1.0, 1.0).toDouble();

    final volumes = [for (final c in candles) c.volume];
    final volumeRatio = signal.volumeRatio;
    final obvSlope = _obvSlope(candles, 20);
    final volumeTrend = _normalizedSlope(_tail(volumes, 20));

    final elapsedRatio = 1 - frame.secondsRemaining.clamp(0, 300) / 300.0;
    final roundEdgeRaw = _norm(
      signal.roundDistancePct,
      math.max(signal.expectedRemainingMovePct, .05),
    );

    // --- Intermarket (ETH) --------------------------------------------------
    final ethCloses = [for (final c in frame.referenceCandles) c.close];
    final ethRet1 = _pct(ethCloses, 1);
    final ethRet5 = _pct(ethCloses, 5);
    final btcReturns = _returns(_tail(closes, 61));
    final ethReturns = _returns(_tail(ethCloses, 61));
    final pairLength = math.min(btcReturns.length, ethReturns.length);
    final btcPair = _tail(btcReturns, pairLength);
    final ethPair = _tail(ethReturns, pairLength);
    final correlation = _correlation(btcPair, ethPair);
    final beta = _beta(btcPair, ethPair);
    final residual = btcPair.isEmpty || ethPair.isEmpty
        ? 0.0
        : btcPair.last - beta * ethPair.last;
    final residualSigma = math.max(_std(btcPair), 1e-9);
    final leadLag = _laggedCorrelation(ethPair, btcPair, 1);

    final consensusSigns = <double>[
      momentumSign,
      frame.bookImbalance == 0 ? 0.0 : frame.bookImbalance.sign,
      frame.aggressorImbalance == 0 ? 0.0 : frame.aggressorImbalance.sign,
      frame.micropriceEdge == 0 ? 0.0 : frame.micropriceEdge.sign,
    ];
    final decided = consensusSigns.where((s) => s != 0).toList();
    final exchangeConsensus = decided.isEmpty
        ? 0.0
        : decided.reduce((a, b) => a + b) / decided.length;

    // --- Flow quality -------------------------------------------------------
    final flowSign =
        frame.aggressorImbalance == 0 ? 0.0 : frame.aggressorImbalance.sign;
    final realizedImpulse = frame.priceImpulseBps * flowSign;
    final expectedImpulse = frame.aggressorImbalance.abs() * 7.5;
    final absorption = flowSign * _norm(realizedImpulse - expectedImpulse, 6);

    // --- Price action -------------------------------------------------------
    final lastCandle = candles.isEmpty ? null : candles.last;
    final closeLocation = lastCandle == null || lastCandle.high <= lastCandle.low
        ? 0.0
        : (((lastCandle.close - lastCandle.low) /
                    (lastCandle.high - lastCandle.low)) *
                2 -
            1);
    final wickBias = _wickBias(_tailCandles(candles, 5));
    final swingStructure = _swingStructure(_tailCandles(candles, 12));
    final breakoutQuality = rangeSpan <= 0
        ? 0.0
        : (((current - rangeHigh) > 0
                ? (current - rangeHigh) / math.max(atrAbs, 1e-9)
                : (current - rangeLow) < 0
                    ? (current - rangeLow) / math.max(atrAbs, 1e-9)
                    : ((current - rangeLow) / rangeSpan * 2 - 1) * .35))
            .clamp(-1.0, 1.0)
            .toDouble();
    final rejectionBias = _rejectionBias(_tailCandles(candles, 6), atrAbs);

    // --- Trend quality ------------------------------------------------------
    final trendFit = _linearFit(_tail(closes, 12));
    final trendQuality = trendFit.r2 * (trendFit.slope >= 0 ? 1 : -1);
    final pullbackDepth = atrAbs <= 0
        ? 0.0
        : (trendSign *
                (1 -
                    ((trendSign >= 0
                                ? (rangeHigh - current)
                                : (current - rangeLow)) /
                            (atrAbs * 2))
                        .clamp(0.0, 1.0)))
            .toDouble();

    final volatilityRegime = atrPctBaseline <= 0
        ? 0.0
        : momentumSign * _norm(atrPct / atrPctBaseline - 1, .8);
    final bandwidth = mean20 <= 0 ? 0.0 : (4 * sigma20) / mean20 * 100;
    final baselineCloses = _tail(closes, 60);
    final baselineSigma = math.max(_std(baselineCloses), 1e-9);
    final baselineMean = math.max(_mean(baselineCloses), 1e-9);
    final baselineBandwidth = (4 * baselineSigma) / baselineMean * 100;
    final squeeze = baselineBandwidth <= 0
        ? 0.0
        : momentumSign * (1 - (bandwidth / baselineBandwidth).clamp(0.0, 2.0)).clamp(-1.0, 1.0);
    final gapRisk = avgRange <= 0
        ? 0.0
        : -momentumSign * ((lastRange / avgRange - 1) / 1.5).clamp(0.0, 1.0);

    final effortResult = volumeRatio <= 0
        ? 0.0
        : momentumSign *
            (((ret1.abs() / math.max(atrPct, 1e-6)) / math.max(volumeRatio, .2)) - 1)
                .clamp(-1.0, 1.0);

    final tightness =
        (1 - (frame.spreadBps.abs() / 3).clamp(0.0, 1.0)).toDouble();

    final features = <String, double>{
      // momentum
      'momentum': momentum,
      'acceleration': _norm(acceleration, .18),
      'shortReturn': _norm(ret3, .30),
      'velocityRatio': _norm(ret3 - ret9 / 3, .12),
      'impulse': _norm(frame.priceImpulseBps, 8),
      'momentumPersistence': _directionPersistence(_tailCandles(candles, 6)),
      // trend
      'trend': trend,
      'emaSpread': ema21 <= 0 ? 0.0 : _norm((ema5 - ema21) / ema21 * 100, .30),
      'slope': _norm(statistical.driftPerMinute * 100, .05),
      'trendQuality': trendQuality,
      'higherTrend': ema55 <= 0 ? 0.0 : _norm((ema21 - ema55) / ema55 * 100, .45),
      'pullbackDepth': pullbackDepth,
      // volatility
      'volatilityBreakout': _norm(frame.priceImpulseBps, 8),
      'atrExpansion': atrPctBaseline <= 0
          ? 0.0
          : momentumSign * _norm(atrPct - atrPctBaseline, .12),
      'rangeExpansion': momentumSign * rangeExpansion,
      'volatilityRegime': volatilityRegime,
      'squeeze': squeeze.toDouble(),
      'gapRisk': gapRisk.toDouble(),
      // mean reversion (positive means "extended upward")
      'zPrice': zPrice,
      'rsiExtreme': _norm(rsi - 50, 25),
      'vwapDistance': vwap <= 0 ? 0.0 : _norm((current - vwap) / vwap * 100, .26),
      'bandPosition': bandPosition,
      'exhaustion': _exhaustion(_tailCandles(candles, 8)),
      'reversionPull': _norm(zPrice * 3, 2.5),
      // order book
      'bookImbalance': frame.bookImbalance,
      'micropriceEdge': _norm(frame.micropriceEdge, 2.0),
      'spreadPressure': frame.bookImbalance * tightness,
      'depthSlope': (frame.nearImbalance - frame.bookImbalance)
          .clamp(-1.0, 1.0)
          .toDouble(),
      'queueDepletion': frame.queueImbalance,
      'bookStability': frame.bookImbalance.sign * tightness,
      // trade flow
      'aggressorImbalance': frame.aggressorImbalance,
      'tradeAcceleration': frame.tradeAcceleration * flowSign,
      'signedVolume': frame.signedVolume,
      'flowPersistence': frame.flowPersistence,
      'absorption': absorption,
      'largeTradeBias': frame.largeTradeBias,
      // volume
      'volumeZ': momentumSign * _norm(volumeRatio - 1, 1.5),
      'obvSlope': obvSlope,
      'volumePriceAgreement':
          momentumSign * (volumeRatio - 1).clamp(-1.0, 1.0).toDouble(),
      'volumeTrend': momentumSign * volumeTrend,
      'effortResult': effortResult.toDouble(),
      'liquidityShift': momentumSign *
          tightness *
          (volumeRatio - 1).clamp(-1.0, 1.0).toDouble(),
      // price action
      'bodyPressure': bodyPressure,
      'breakoutQuality': breakoutQuality,
      'wickBias': wickBias,
      'closeLocation': closeLocation.clamp(-1.0, 1.0).toDouble(),
      'swingStructure': swingStructure,
      'rejectionBias': rejectionBias,
      // intermarket
      'ethConfirmation': _norm(ethRet5, .40),
      'exchangeConsensus': exchangeConsensus,
      'betaResidual': _norm(residual / residualSigma, 2.0),
      'crossFlow': _norm(ret1 - ethRet1, .22),
      'correlationRegime': correlation *
          (statistical.driftPerMinute == 0
              ? 0.0
              : statistical.driftPerMinute.sign),
      'leadLag': leadLag *
          (ethPair.isEmpty || ethPair.last == 0 ? 0.0 : ethPair.last.sign),
      // regime
      'regimeTrend': trend,
      'regimePersistence': statistical.autocorrelation.clamp(-1.0, 1.0).toDouble(),
      'roundEdge': roundEdgeRaw,
      'timeDecayEdge': roundEdgeRaw * elapsedRatio,
      'sessionBias': _norm(
        statistical.driftPerMinute * 30 /
            math.max(statistical.ewmaVolatilityPerMinute * math.sqrt(30), 1e-9),
        2.0,
      ),
      'stabilityEdge':
          ((1 - instability / 100).clamp(0.0, 1.0) * signal.score.sign)
              .toDouble(),
    };

    return AnalystInput(
      features: features,
      instability: instability,
      secondsRemaining: frame.secondsRemaining,
    );
  }
}

// =============================================================================
// Local numeric helpers
// =============================================================================

double _norm(double value, double scale) {
  if (!value.isFinite || scale == 0) return 0;
  final v = value / scale;
  return v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0.0;
}

List<double> _tail(List<double> x, int n) =>
    x.length <= n ? List<double>.from(x) : x.sublist(x.length - n);

List<Candle> _tailCandles(List<Candle> x, int n) =>
    x.length <= n ? List<Candle>.from(x) : x.sublist(x.length - n);

double _mean(List<double> x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v;
  }
  return s / x.length;
}

double _std(List<double> x) {
  if (x.length < 2) return 0;
  final m = _mean(x);
  var acc = 0.0;
  for (final v in x) {
    final d = v - m;
    acc += d * d;
  }
  final variance = acc / (x.length - 1);
  return variance <= 0 ? 0 : math.sqrt(variance);
}

List<double> _returns(List<double> closes) {
  final out = <double>[];
  for (var i = 1; i < closes.length; i++) {
    if (closes[i - 1] > 0) out.add((closes[i] - closes[i - 1]) / closes[i - 1]);
  }
  return out;
}

double _pct(List<double> closes, int lookback) {
  if (closes.length <= lookback) return 0;
  final from = closes[closes.length - 1 - lookback];
  if (from <= 0) return 0;
  return (closes.last - from) / from * 100;
}

double _pctAt(List<double> closes, int lookback, int offset) {
  final endIndex = closes.length - 1 - offset;
  final startIndex = endIndex - lookback;
  if (startIndex < 0 || endIndex < 0 || closes[startIndex] <= 0) return 0;
  return (closes[endIndex] - closes[startIndex]) / closes[startIndex] * 100;
}

double _ema(List<double> values, int period) {
  if (values.isEmpty) return 0;
  final source = values.length <= period * 4
      ? values
      : values.sublist(values.length - period * 4);
  final k = 2.0 / (period + 1);
  var e = source.first;
  for (final v in source.skip(1)) {
    e = v * k + e * (1 - k);
  }
  return e;
}

double _rsi(List<double> closes, int period) {
  if (closes.length <= period) return 50;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = closes.length - period; i < closes.length; i++) {
    final d = closes[i] - closes[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  if (loss == 0) return gain == 0 ? 50 : 100;
  final rs = gain / loss;
  return 100 - (100 / (1 + rs));
}

double _vwap(List<Candle> candles) {
  if (candles.isEmpty) return 0;
  var pv = 0.0;
  var v = 0.0;
  for (final c in candles) {
    pv += ((c.high + c.low + c.close) / 3) * c.volume;
    v += c.volume;
  }
  return v <= 0 ? candles.last.close : pv / v;
}

double _atrAbsolute(List<Candle> candles, int period) {
  if (candles.length < 2) return 0;
  final start = math.max(1, candles.length - period);
  var total = 0.0;
  var n = 0;
  for (var i = start; i < candles.length; i++) {
    final c = candles[i];
    final previousClose = candles[i - 1].close;
    total += math.max(
      c.high - c.low,
      math.max((c.high - previousClose).abs(), (c.low - previousClose).abs()),
    );
    n++;
  }
  return n == 0 ? 0 : total / n;
}

class _Line {
  const _Line(this.slope, this.r2);
  final double slope;
  final double r2;
}

_Line _linearFit(List<double> y) {
  final n = y.length;
  if (n < 3) return const _Line(0, 0);
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final x = i.toDouble();
    sx += x;
    sy += y[i];
    sxy += x * y[i];
    sxx += x * x;
    syy += y[i] * y[i];
  }
  final den = n * sxx - sx * sx;
  if (den.abs() < 1e-15) return const _Line(0, 0);
  final slope = (n * sxy - sx * sy) / den;
  final varY = n * syy - sy * sy;
  final r = varY.abs() < 1e-15
      ? 0.0
      : (n * sxy - sx * sy) / math.sqrt(den * varY.abs());
  final r2 = (r * r);
  return _Line(
    slope.isFinite ? slope : 0,
    r2.isFinite ? r2.clamp(0.0, 1.0).toDouble() : 0,
  );
}

double _normalizedSlope(List<double> values) {
  if (values.length < 3) return 0;
  final fit = _linearFit(values);
  final scale = math.max(_std(values), 1e-9);
  return (fit.slope / scale).clamp(-1.0, 1.0).toDouble();
}

double _obvSlope(List<Candle> candles, int window) {
  final source = _tailCandles(candles, window + 1);
  if (source.length < 4) return 0;
  final obv = <double>[0];
  for (var i = 1; i < source.length; i++) {
    final delta = source[i].close > source[i - 1].close
        ? source[i].volume
        : source[i].close < source[i - 1].close
            ? -source[i].volume
            : 0.0;
    obv.add(obv.last + delta);
  }
  return _normalizedSlope(obv);
}

double _correlation(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  if (n < 4) return 0;
  final ma = _mean(a.sublist(a.length - n));
  final mb = _mean(b.sublist(b.length - n));
  var cov = 0.0, va = 0.0, vb = 0.0;
  for (var i = 0; i < n; i++) {
    final da = a[a.length - n + i] - ma;
    final db = b[b.length - n + i] - mb;
    cov += da * db;
    va += da * da;
    vb += db * db;
  }
  final den = math.sqrt(va * vb);
  if (den <= 1e-18) return 0;
  final r = cov / den;
  return r.isFinite ? r.clamp(-1.0, 1.0).toDouble() : 0.0;
}

double _beta(List<double> y, List<double> x) {
  final n = math.min(y.length, x.length);
  if (n < 4) return 0;
  final my = _mean(y.sublist(y.length - n));
  final mx = _mean(x.sublist(x.length - n));
  var cov = 0.0, vx = 0.0;
  for (var i = 0; i < n; i++) {
    final dy = y[y.length - n + i] - my;
    final dx = x[x.length - n + i] - mx;
    cov += dx * dy;
    vx += dx * dx;
  }
  if (vx <= 1e-18) return 0;
  final beta = cov / vx;
  return beta.isFinite ? beta.clamp(-4.0, 4.0).toDouble() : 0.0;
}

/// Correlation between [leader] shifted one step ahead of [follower].
double _laggedCorrelation(List<double> leader, List<double> follower, int lag) {
  if (leader.length <= lag + 4 || follower.length <= lag + 4) return 0;
  final a = leader.sublist(0, leader.length - lag);
  final b = follower.sublist(lag);
  return _correlation(a, b);
}

double _directionPersistence(List<Candle> candles) {
  if (candles.isEmpty) return 0;
  var score = 0.0;
  for (final c in candles) {
    if (c.close > c.open) {
      score += 1;
    } else if (c.close < c.open) {
      score -= 1;
    }
  }
  return (score / candles.length).clamp(-1.0, 1.0).toDouble();
}

double _exhaustion(List<Candle> candles) {
  if (candles.isEmpty) return 0;
  var streak = 0;
  var direction = 0;
  for (final c in candles) {
    final d = c.close > c.open ? 1 : (c.close < c.open ? -1 : 0);
    if (d == 0) continue;
    if (d == direction) {
      streak++;
    } else {
      direction = d;
      streak = 1;
    }
  }
  return (direction * (streak / 5)).clamp(-1.0, 1.0).toDouble();
}

double _wickBias(List<Candle> candles) {
  if (candles.isEmpty) return 0;
  var score = 0.0;
  var count = 0;
  for (final c in candles) {
    final range = c.high - c.low;
    if (range <= 0) continue;
    final upper = c.high - math.max(c.open, c.close);
    final lower = math.min(c.open, c.close) - c.low;
    score += (lower - upper) / range;
    count++;
  }
  return count == 0 ? 0 : (score / count).clamp(-1.0, 1.0).toDouble();
}

double _swingStructure(List<Candle> candles) {
  if (candles.length < 6) return 0;
  final half = candles.length ~/ 2;
  final firstHigh = candles.sublist(0, half).map((c) => c.high).reduce(math.max);
  final lastHigh = candles.sublist(half).map((c) => c.high).reduce(math.max);
  final firstLow = candles.sublist(0, half).map((c) => c.low).reduce(math.min);
  final lastLow = candles.sublist(half).map((c) => c.low).reduce(math.min);
  var score = 0.0;
  if (lastHigh > firstHigh) score += .5;
  if (lastHigh < firstHigh) score -= .5;
  if (lastLow > firstLow) score += .5;
  if (lastLow < firstLow) score -= .5;
  return score.clamp(-1.0, 1.0).toDouble();
}

double _rejectionBias(List<Candle> candles, double atr) {
  if (candles.isEmpty || atr <= 0) return 0;
  var score = 0.0;
  for (final c in candles) {
    final upper = c.high - math.max(c.open, c.close);
    final lower = math.min(c.open, c.close) - c.low;
    score += (lower - upper) / atr;
  }
  return (score / candles.length).clamp(-1.0, 1.0).toDouble();
}
