import 'dart:math' as math;

/// Calibrates a raw directional edge into a probability-like confidence.
/// This deliberately avoids claiming certainty: it combines independent
/// mathematical views and shrinks weak evidence toward 50%.
class PulseProbabilityCalibrator {
  const PulseProbabilityCalibrator();

  PulseProbabilityResult calibrate({
    required double score,
    required double instability,
    required double agreement,
    required double roundDistancePct,
    required double expectedRemainingMovePct,
    required int secondsRemaining,
  }) {
    final s = score.clamp(-100.0, 100.0).toDouble();
    final inst = instability.clamp(0.0, 100.0).toDouble() / 100.0;
    final agree = agreement.clamp(0.0, 1.0).toDouble();
    final sigma = math.max(expectedRemainingMovePct.abs(), 0.015);

    // 1) Logistic directional model: converts technical edge to P(up).
    final logistic = 1.0 / (1.0 + math.exp(-s / 18.0));

    // 2) Diffusion model: how difficult it is for the remaining random move
    // to overcome the current round edge. Normal-CDF approximation.
    final z = roundDistancePct / sigma;
    final diffusion = _normalCdf(z);

    // Early in the round technical structure matters more; near expiry the
    // actual distance from the round open becomes increasingly informative.
    final elapsed = 1.0 - secondsRemaining.clamp(0, 300) / 300.0;
    final diffusionWeight = (0.12 + elapsed * 0.48).clamp(0.12, 0.60);
    var pUp = logistic * (1 - diffusionWeight) + diffusion * diffusionWeight;

    // Bayesian-style shrinkage: disagreement and instability reduce effective
    // evidence, pulling probabilities back toward an uninformative 50%.
    final evidence = ((0.30 + 0.70 * agree) * (1.0 - 0.72 * inst))
        .clamp(0.08, 1.0);
    pUp = 0.5 + (pUp - 0.5) * evidence;

    // Do not report extreme pseudo-certainty for a 5-minute crypto horizon.
    pUp = pUp.clamp(0.08, 0.92).toDouble();
    final pDown = 1.0 - pUp;
    final confidence = math.max(pUp, pDown) * 100.0;
    final edge = (pUp - 0.5).abs() * 2.0;

    return PulseProbabilityResult(
      probabilityUp: pUp,
      probabilityDown: pDown,
      confidence: confidence,
      statisticalEdge: edge,
    );
  }

  double _normalCdf(double x) {
    // Abramowitz-Stegun approximation, sufficient for real-time calibration.
    final sign = x < 0 ? -1.0 : 1.0;
    final a = x.abs() / math.sqrt(2.0);
    final t = 1.0 / (1.0 + 0.3275911 * a);
    final erf = 1.0 -
        (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t -
                        0.284496736) *
                    t +
                0.254829592) *
            t *
            math.exp(-a * a));
    return 0.5 * (1.0 + sign * erf);
  }
}

class PulseProbabilityResult {
  const PulseProbabilityResult({
    required this.probabilityUp,
    required this.probabilityDown,
    required this.confidence,
    required this.statisticalEdge,
  });

  final double probabilityUp;
  final double probabilityDown;
  final double confidence;
  final double statisticalEdge;
}
