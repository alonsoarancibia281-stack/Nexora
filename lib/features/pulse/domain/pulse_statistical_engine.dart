import 'dart:math' as math;

import '../../market/domain/candle.dart';

class PulseStatisticalResult {
  const PulseStatisticalResult({
    required this.probabilityUp,
    required this.confidence,
    required this.driftPerMinute,
    required this.ewmaVolatilityPerMinute,
    required this.autocorrelation,
    required this.signalQuality,
  });

  final double probabilityUp;
  final double confidence;
  final double driftPerMinute;
  final double ewmaVolatilityPerMinute;
  final double autocorrelation;
  final double signalQuality;
}

/// Statistical model for a very short BTC horizon.
///
/// It combines log-return drift, EWMA volatility, AR(1)-style serial
/// dependence, robust outlier control and order-book imbalance. The output is
/// intentionally shrunk toward 50% when evidence is weak or noisy.
class PulseStatisticalEngine {
  const PulseStatisticalEngine();

  PulseStatisticalResult analyze({
    required List<Candle> candles,
    required double bidVolume,
    required double askVolume,
    required double roundStartPrice,
    required int secondsRemaining,
  }) {
    if (candles.length < 45 || roundStartPrice <= 0) {
      return const PulseStatisticalResult(
        probabilityUp: .5,
        confidence: 50,
        driftPerMinute: 0,
        ewmaVolatilityPerMinute: 0,
        autocorrelation: 0,
        signalQuality: 0,
      );
    }

    final recent = candles.sublist(candles.length - math.min(75, candles.length));
    final closes = recent.map((c) => c.close).toList(growable: false);
    final returns = <double>[];
    for (var i = 1; i < closes.length; i++) {
      if (closes[i - 1] > 0 && closes[i] > 0) {
        returns.add(math.log(closes[i] / closes[i - 1]));
      }
    }
    if (returns.length < 30) {
      return const PulseStatisticalResult(
        probabilityUp: .5,
        confidence: 50,
        driftPerMinute: 0,
        ewmaVolatilityPerMinute: 0,
        autocorrelation: 0,
        signalQuality: 0,
      );
    }

    final clipped = _winsorizeMad(returns, 4.5);
    final drift = _expWeightedMean(clipped, .92);
    final variance = _ewmaVariance(clipped, .94);
    final sigma = math.sqrt(math.max(variance, 1e-12));
    final rho = _lag1Correlation(clipped).clamp(-.45, .45).toDouble();

    final totalDepth = bidVolume + askVolume;
    final imbalance = totalDepth <= 0
        ? 0.0
        : ((bidVolume - askVolume) / totalDepth).clamp(-1.0, 1.0).toDouble();

    final horizonMinutes = math.max(secondsRemaining.clamp(0, 300) / 60.0, .05);
    final current = closes.last;
    final logDistance = math.log(current / roundStartPrice);

    // One-step AR adjustment fades over the remaining horizon. Order-book
    // imbalance contributes only a small fraction of one-minute volatility.
    final lastReturn = clipped.last;
    final serialDrift = rho * lastReturn * math.min(horizonMinutes, 1.5);
    final bookDrift = imbalance * sigma * .18 * math.min(horizonMinutes, 1.0);
    final expectedLogMove = drift * horizonMinutes + serialDrift + bookDrift;

    // Volatility grows approximately with sqrt(time) under a diffusion model.
    final horizonSigma = sigma * math.sqrt(horizonMinutes);
    final z = horizonSigma <= 1e-9
        ? 0.0
        : (logDistance + expectedLogMove) / horizonSigma;
    var pUp = _normalCdf(z.clamp(-5.0, 5.0).toDouble());

    final directionChanges = _directionChangeRatio(clipped.takeLast(12).toList());
    final standardizedDrift = sigma <= 1e-9 ? 0.0 : (drift / sigma).abs();
    final quality = (standardizedDrift * .45 +
            rho.abs() * .20 +
            imbalance.abs() * .15 +
            (1 - directionChanges) * .20)
        .clamp(0.0, 1.0)
        .toDouble();

    // Bayesian-style shrinkage. A noisy process should not display strong
    // pseudo-certainty even if the raw diffusion probability is extreme.
    final shrink = (.18 + quality * .70).clamp(.18, .88).toDouble();
    pUp = .5 + (pUp - .5) * shrink;
    pUp = pUp.clamp(.08, .92).toDouble();

    return PulseStatisticalResult(
      probabilityUp: pUp,
      confidence: math.max(pUp, 1 - pUp) * 100,
      driftPerMinute: drift,
      ewmaVolatilityPerMinute: sigma,
      autocorrelation: rho,
      signalQuality: quality,
    );
  }

  List<double> _winsorizeMad(List<double> x, double k) {
    final sorted = [...x]..sort();
    final median = _median(sorted);
    final deviations = x.map((v) => (v - median).abs()).toList()..sort();
    final mad = _median(deviations);
    if (mad <= 1e-12) return [...x];
    final robustSigma = mad * 1.4826;
    final lo = median - k * robustSigma;
    final hi = median + k * robustSigma;
    return x.map((v) => v.clamp(lo, hi).toDouble()).toList();
  }

  double _median(List<double> sorted) {
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  double _expWeightedMean(List<double> x, double lambda) {
    var weight = 1.0;
    var weighted = 0.0;
    var total = 0.0;
    for (final v in x.reversed) {
      weighted += v * weight;
      total += weight;
      weight *= lambda;
    }
    return total == 0 ? 0 : weighted / total;
  }

  double _ewmaVariance(List<double> x, double lambda) {
    var variance = x.first * x.first;
    for (final r in x.skip(1)) {
      variance = lambda * variance + (1 - lambda) * r * r;
    }
    return variance;
  }

  double _lag1Correlation(List<double> x) {
    if (x.length < 3) return 0;
    final a = x.sublist(0, x.length - 1);
    final b = x.sublist(1);
    final ma = a.reduce((u, v) => u + v) / a.length;
    final mb = b.reduce((u, v) => u + v) / b.length;
    var cov = 0.0, va = 0.0, vb = 0.0;
    for (var i = 0; i < a.length; i++) {
      final da = a[i] - ma, db = b[i] - mb;
      cov += da * db;
      va += da * da;
      vb += db * db;
    }
    final den = math.sqrt(va * vb);
    return den <= 1e-12 ? 0 : cov / den;
  }

  double _directionChangeRatio(List<double> x) {
    if (x.length < 2) return .5;
    var changes = 0;
    for (var i = 1; i < x.length; i++) {
      if (x[i] != 0 && x[i - 1] != 0 && x[i].sign != x[i - 1].sign) changes++;
    }
    return changes / (x.length - 1);
  }

  double _normalCdf(double x) {
    final sign = x < 0 ? -1.0 : 1.0;
    final a = x.abs() / math.sqrt(2.0);
    final t = 1.0 / (1.0 + .3275911 * a);
    final erf = 1.0 -
        (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t -
                        .284496736) *
                    t +
                .254829592) *
            t *
            math.exp(-a * a));
    return .5 * (1 + sign * erf);
  }
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    return list.skip(math.max(0, list.length - count));
  }
}
