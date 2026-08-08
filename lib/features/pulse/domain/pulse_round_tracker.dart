import 'dart:math' as math;

import 'pulse_signal.dart';

/// One immutable observation made during a 5-minute BTC round.
class PulseRoundObservation {
  const PulseRoundObservation({
    required this.roundStart,
    required this.observedAt,
    required this.secondsRemaining,
    required this.startPrice,
    required this.observedPrice,
    required this.predictedDirection,
    required this.probabilityUp,
    required this.instability,
  });

  final DateTime roundStart;
  final DateTime observedAt;
  final int secondsRemaining;
  final double startPrice;
  final double observedPrice;
  final PulseDirection predictedDirection;
  final double probabilityUp;
  final double instability;
}

class PulseRoundOutcome {
  const PulseRoundOutcome({
    required this.roundStart,
    required this.startPrice,
    required this.endPrice,
    required this.observations,
  });

  final DateTime roundStart;
  final double startPrice;
  final double endPrice;
  final List<PulseRoundObservation> observations;

  bool get finishedUp => endPrice > startPrice;
}

/// Computes honest out-of-sample quality metrics from closed rounds.
/// Accuracy alone is insufficient, so Brier score and calibration error are
/// tracked as well.
class PulseCalibrationMetrics {
  const PulseCalibrationMetrics({
    required this.samples,
    required this.accuracy,
    required this.brierScore,
    required this.expectedCalibrationError,
  });

  final int samples;
  final double accuracy;
  final double brierScore;
  final double expectedCalibrationError;

  bool get hasUsefulSample => samples >= 100;

  static PulseCalibrationMetrics fromOutcomes(
    List<PulseRoundOutcome> outcomes, {
    int targetSecondsRemaining = 240,
  }) {
    final pairs = <({double p, double y, bool correct})>[];
    for (final outcome in outcomes) {
      if (outcome.observations.isEmpty) continue;
      final obs = outcome.observations.reduce((a, b) =>
          (a.secondsRemaining - targetSecondsRemaining).abs() <=
                  (b.secondsRemaining - targetSecondsRemaining).abs()
              ? a
              : b);
      final y = outcome.finishedUp ? 1.0 : 0.0;
      final p = obs.probabilityUp.clamp(0.0, 1.0).toDouble();
      final predictedUp = p >= 0.5;
      pairs.add((p: p, y: y, correct: predictedUp == outcome.finishedUp));
    }
    if (pairs.isEmpty) {
      return const PulseCalibrationMetrics(
        samples: 0,
        accuracy: 0,
        brierScore: 0,
        expectedCalibrationError: 0,
      );
    }

    final n = pairs.length;
    final accuracy = pairs.where((x) => x.correct).length / n;
    final brier = pairs.fold<double>(0, (s, x) => s + math.pow(x.p - x.y, 2)) / n;

    const bins = 10;
    var ece = 0.0;
    for (var i = 0; i < bins; i++) {
      final lo = i / bins;
      final hi = (i + 1) / bins;
      final bucket = pairs.where((x) =>
          x.p >= lo && (i == bins - 1 ? x.p <= hi : x.p < hi)).toList();
      if (bucket.isEmpty) continue;
      final meanP = bucket.fold<double>(0, (s, x) => s + x.p) / bucket.length;
      final rate = bucket.fold<double>(0, (s, x) => s + x.y) / bucket.length;
      ece += (bucket.length / n) * (meanP - rate).abs();
    }

    return PulseCalibrationMetrics(
      samples: n,
      accuracy: accuracy,
      brierScore: brier,
      expectedCalibrationError: ece,
    );
  }
}
