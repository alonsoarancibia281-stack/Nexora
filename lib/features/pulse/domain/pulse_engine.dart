import 'dart:math' as math;
import '../../market/domain/candle.dart';
import 'pulse_signal.dart';

class PulseEngine {
  const PulseEngine();

  PulseSignal analyze({
    required List<Candle> candles,
    required double bidVolume,
    required double askVolume,
  }) {
    if (candles.length < 20) {
      throw ArgumentError('Se requieren al menos 20 velas de 1 minuto.');
    }

    final recent = candles.sublist(candles.length - 20);
    final closes = recent.map((e) => e.close).toList();
    final volumes = recent.map((e) => e.volume).toList();

    double pct(double from, double to) => from == 0 ? 0 : ((to - from) / from) * 100;
    double norm(double value, double scale) => (value / scale).clamp(-1.0, 1.0);

    final momentum1 = pct(closes[closes.length - 2], closes.last);
    final momentum3 = pct(closes[closes.length - 4], closes.last);
    final momentum5 = pct(closes[closes.length - 6], closes.last);
    final momentumScore = (
      norm(momentum1, 0.18) * 0.35 +
      norm(momentum3, 0.35) * 0.40 +
      norm(momentum5, 0.55) * 0.25
    ).clamp(-1.0, 1.0);

    final ema5 = _ema(closes, 5);
    final ema13 = _ema(closes, 13);
    final trendPct = ema13 == 0 ? 0 : ((ema5 - ema13) / ema13) * 100;
    final trendScore = norm(trendPct, 0.22);

    final depthTotal = bidVolume + askVolume;
    final imbalance = depthTotal <= 0 ? 0.0 : ((bidVolume - askVolume) / depthTotal).clamp(-1.0, 1.0);

    final recentVol = volumes.sublist(volumes.length - 3).reduce((a, b) => a + b) / 3;
    final baselineVol = volumes.sublist(2, 12).reduce((a, b) => a + b) / 10;
    final volumeRatio = baselineVol <= 0 ? 1.0 : recentVol / baselineVol;
    final volumeImpulse = ((volumeRatio - 1) / 1.5).clamp(-1.0, 1.0) * (momentumScore == 0 ? 0 : momentumScore.sign);

    var bodyPressure = 0.0;
    for (final candle in recent.sublist(recent.length - 5)) {
      final range = candle.high - candle.low;
      if (range > 0) bodyPressure += ((candle.close - candle.open) / range).clamp(-1.0, 1.0);
    }
    bodyPressure = (bodyPressure / 5).clamp(-1.0, 1.0);

    final raw = (
      momentumScore * 0.30 +
      trendScore * 0.20 +
      imbalance * 0.25 +
      volumeImpulse * 0.15 +
      bodyPressure * 0.10
    ).clamp(-1.0, 1.0);

    final score = raw * 100;
    var confidence = 50 + score.abs() * 0.42;
    final momentumVsBookConflict = momentumScore.abs() > 0.25 && imbalance.abs() > 0.20 && momentumScore.sign != imbalance.sign;
    if (momentumVsBookConflict) confidence -= 8;
    if (volumeRatio < 0.70) confidence -= 6;
    confidence = confidence.clamp(50.0, 90.0);

    final lowQuality = score.abs() < 35 || confidence < 62 || volumeRatio < 0.55;
    final direction = lowQuality
        ? PulseDirection.noTrade
        : score > 0
            ? PulseDirection.up
            : PulseDirection.down;

    final reasons = <String>[
      momentumScore > 0.2
          ? 'Momentum reciente comprador.'
          : momentumScore < -0.2
              ? 'Momentum reciente vendedor.'
              : 'Momentum corto sin dirección clara.',
      trendScore > 0.15
          ? 'EMA 5 por encima de EMA 13.'
          : trendScore < -0.15
              ? 'EMA 5 por debajo de EMA 13.'
              : 'EMA 5 y EMA 13 muy próximas.',
      imbalance > 0.15
          ? 'Mayor profundidad compradora en el libro.'
          : imbalance < -0.15
              ? 'Mayor profundidad vendedora en el libro.'
              : 'Libro de órdenes relativamente equilibrado.',
      volumeRatio > 1.25
          ? 'Volumen reciente por encima de su referencia.'
          : volumeRatio < 0.75
              ? 'Volumen reciente débil.'
              : 'Volumen reciente cercano a su referencia.',
      if (momentumVsBookConflict) 'Existe conflicto entre momentum y libro de órdenes.',
    ];

    return PulseSignal(
      direction: direction,
      score: score,
      confidence: confidence,
      momentumScore: momentumScore * 100,
      trendScore: trendScore * 100,
      orderBookImbalance: imbalance * 100,
      volumeRatio: volumeRatio,
      bodyPressure: bodyPressure * 100,
      reasons: reasons,
    );
  }

  double _ema(List<double> values, int period) {
    final k = 2 / (period + 1);
    var ema = values.first;
    for (final value in values.skip(1)) {
      ema = value * k + ema * (1 - k);
    }
    return ema;
  }
}
