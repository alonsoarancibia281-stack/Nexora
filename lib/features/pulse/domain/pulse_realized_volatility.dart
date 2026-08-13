import 'dart:math' as math;

import '../../market/domain/candle.dart';

/// How much the price can still move before the candle closes.
///
/// This is the σ in the diffusion anchor, Φ(d / σ√τ), and it is the whole
/// reason the anchor's fitted coefficient came out at 0.7754 instead of 1: the
/// estimate in use was the 14-period ATR times a hand-picked 0.72. ATR measures
/// the true range, not the standard deviation of returns, and the ratio between
/// the two is not a constant — it widens in trends and narrows in chop — so the
/// z fed into Φ drifts with the regime and the probability comes out
/// overconfident.
///
/// What follows are the textbook estimators instead, with no free constants:
/// an exponentially weighted standard deviation of one-minute log returns, and
/// its jump-robust cousin.
class PulseRealizedVolatility {
  const PulseRealizedVolatility({this.lambda = .94});

  /// Decay of the exponential weighting. 0.94 is the RiskMetrics value and
  /// gives an effective memory of roughly sixteen minutes, which is the right
  /// order for a five-minute forecast.
  final double lambda;

  /// Smallest σ per minute, in percent, that will be reported. Without it a
  /// dead stretch of tape divides by nearly zero and the anchor pins at 5%.
  static const double floorPct = .008;

  /// Exponentially weighted standard deviation of one-minute log returns, in
  /// percent.
  double ewmaPerMinutePct(List<Candle> candles) {
    final returns = _logReturns(candles);
    if (returns.length < 8) return floorPct;

    // Seed with the plain variance of the oldest third so the recursion does
    // not spend its first observations catching up.
    final seed = returns.take(math.max(returns.length ~/ 3, 4)).toList();
    var variance = _variance(seed);
    for (final r in returns.skip(seed.length)) {
      variance = lambda * variance + (1 - lambda) * r * r;
    }
    return math.max(math.sqrt(math.max(variance, 0)) * 100, floorPct);
  }

  /// Plain standard deviation of the last [window] one-minute log returns, in
  /// percent. Equal weight, no decay — the honest baseline the weighted and
  /// jump-robust estimators have to beat.
  double realizedPerMinutePct(List<Candle> candles, {int window = 60}) {
    final returns = _logReturns(candles);
    if (returns.length < 8) return floorPct;
    final tail = returns.length <= window
        ? returns
        : returns.sublist(returns.length - window);
    return math.max(math.sqrt(_variance(tail)) * 100, floorPct);
  }

  /// Bipower variation: the same volatility with the jumps taken out.
  ///
  /// A single violent print inflates a squared-return estimate for as long as
  /// the window remembers it. Multiplying neighbouring absolute returns instead
  /// of squaring each one leaves the continuous part of the move behind, which
  /// is the part that says anything about the next four minutes.
  double bipowerPerMinutePct(List<Candle> candles) {
    final returns = _logReturns(candles);
    if (returns.length < 12) return ewmaPerMinutePct(candles);

    // Only the recent window matters; sixty minutes is long enough to be
    // stable and short enough to still be about now.
    final window = returns.length <= 60
        ? returns
        : returns.sublist(returns.length - 60);
    var sum = 0.0;
    for (var i = 1; i < window.length; i++) {
      sum += window[i].abs() * window[i - 1].abs();
    }
    final bipower = (math.pi / 2) * sum / (window.length - 1);
    return math.max(math.sqrt(math.max(bipower, 0)) * 100, floorPct);
  }

  /// Stretches a per-minute σ over the part of the round still to run.
  ///
  /// Square root of time: the variance of a diffusion adds up, the standard
  /// deviation does not.
  double scale(double sigmaPerMinutePct, int secondsRemaining) {
    final minutes = math.max(secondsRemaining, 1) / 60.0;
    return math.max(sigmaPerMinutePct * math.sqrt(minutes), floorPct);
  }

  List<double> _logReturns(List<Candle> candles) {
    final out = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final previous = candles[i - 1].close;
      final current = candles[i].close;
      if (previous <= 0 || current <= 0) continue;
      final r = math.log(current / previous);
      if (r.isFinite) out.add(r);
    }
    return out;
  }

  double _variance(List<double> values) {
    if (values.length < 2) return 0;
    var mean = 0.0;
    for (final v in values) {
      mean += v;
    }
    mean /= values.length;
    var acc = 0.0;
    for (final v in values) {
      final d = v - mean;
      acc += d * d;
    }
    return acc / (values.length - 1);
  }
}
