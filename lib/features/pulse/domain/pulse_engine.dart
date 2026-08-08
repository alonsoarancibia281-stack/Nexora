import 'dart:math' as math;

import '../../market/domain/candle.dart';
import 'pulse_signal.dart';

class PulseEngine {
  const PulseEngine();

  PulseSignal analyze({
    required List<Candle> candles,
    required double bidVolume,
    required double askVolume,
    double? roundStartPrice,
    int secondsRemaining = 300,
  }) {
    if (candles.length < 30) {
      throw ArgumentError('Se requieren al menos 30 velas de 1 minuto.');
    }

    final recent = candles.sublist(candles.length - 30);
    final closes = recent.map((e) => e.close).toList();
    final volumes = recent.map((e) => e.volume).toList();
    final currentPrice = closes.last;
    final safeSeconds = secondsRemaining.clamp(0, 300);

    double pct(double from, double to) =>
        from == 0 ? 0.0 : ((to - from) / from) * 100;
    double norm(double value, double scale) =>
        scale == 0 ? 0.0 : (value / scale).clamp(-1.0, 1.0).toDouble();

    final momentum1 = pct(closes[closes.length - 2], closes.last);
    final momentum3 = pct(closes[closes.length - 4], closes.last);
    final momentum5 = pct(closes[closes.length - 6], closes.last);
    final momentumScore = (norm(momentum1, 0.16) * 0.25 +
            norm(momentum3, 0.34) * 0.45 +
            norm(momentum5, 0.58) * 0.30)
        .clamp(-1.0, 1.0)
        .toDouble();

    final ema5 = _ema(closes, 5);
    final ema13 = _ema(closes, 13);
    final ema21 = _ema(closes, 21);
    final trendPct = ema13 == 0 ? 0.0 : ((ema5 - ema13) / ema13) * 100;
    final trendLongPct = ema21 == 0 ? 0.0 : ((ema13 - ema21) / ema21) * 100;
    final slopePct = _slopePctPerCandle(closes.sublist(closes.length - 9));
    final trendScore = (norm(trendPct, 0.20) * 0.45 +
            norm(trendLongPct, 0.24) * 0.20 +
            norm(slopePct, 0.055) * 0.35)
        .clamp(-1.0, 1.0)
        .toDouble();

    final rsi = _rsi(closes, 14);
    final rsiScore = norm(rsi - 50.0, 19.0);
    final rsiExtreme = rsi >= 78 || rsi <= 22;

    final vwap = _vwap(recent.sublist(recent.length - 20));
    final vwapDistancePct = pct(vwap, currentPrice);
    final vwapScore = norm(vwapDistancePct, 0.26);

    final rangeCandles = recent.sublist(recent.length - 12);
    final rangeHigh = rangeCandles.map((e) => e.high).reduce(math.max);
    final rangeLow = rangeCandles.map((e) => e.low).reduce(math.min);
    final rangeSpan = rangeHigh - rangeLow;
    final rangePosition = rangeSpan <= 0
        ? 0.0
        : (((currentPrice - rangeLow) / rangeSpan) * 2 - 1)
            .clamp(-1.0, 1.0)
            .toDouble();

    final persistenceCandles = recent.sublist(recent.length - 7);
    var persistence = 0.0;
    for (final candle in persistenceCandles) {
      if (candle.close > candle.open) {
        persistence += 1;
      } else if (candle.close < candle.open) {
        persistence -= 1;
      }
    }
    persistence = (persistence / persistenceCandles.length)
        .clamp(-1.0, 1.0)
        .toDouble();

    final depthTotal = bidVolume + askVolume;
    final imbalance = depthTotal <= 0
        ? 0.0
        : ((bidVolume - askVolume) / depthTotal)
            .clamp(-1.0, 1.0)
            .toDouble();

    final recentVol =
        volumes.sublist(volumes.length - 4).reduce((a, b) => a + b) / 4;
    final baselineVol = volumes.sublist(5, 20).reduce((a, b) => a + b) / 15;
    final volumeRatio = baselineVol <= 0 ? 1.0 : recentVol / baselineVol;
    final volumeImpulse = (((volumeRatio - 1) / 1.35)
                .clamp(-1.0, 1.0)
                .toDouble()) *
        (momentumScore == 0 ? 0.0 : momentumScore.sign);

    var bodyPressure = 0.0;
    var wickNoise = 0.0;
    final pressureCandles = recent.sublist(recent.length - 6);
    for (final candle in pressureCandles) {
      final range = candle.high - candle.low;
      if (range > 0) {
        final body = (candle.close - candle.open).abs();
        bodyPressure += ((candle.close - candle.open) / range)
            .clamp(-1.0, 1.0)
            .toDouble();
        wickNoise += (1 - body / range).clamp(0.0, 1.0).toDouble();
      }
    }
    bodyPressure = (bodyPressure / pressureCandles.length)
        .clamp(-1.0, 1.0)
        .toDouble();
    wickNoise = (wickNoise / pressureCandles.length)
        .clamp(0.0, 1.0)
        .toDouble();

    final atrPct = _atrPct(recent, 14);
    final minutesRemaining = math.max(safeSeconds / 60.0, 0.15);
    final expectedRemainingMovePct =
        math.max(atrPct * math.sqrt(minutesRemaining) * 0.72, 0.035);

    var roundEdgeScore = 0.0;
    var roundDistancePct = 0.0;
    if (roundStartPrice != null && roundStartPrice > 0) {
      roundDistancePct = pct(roundStartPrice, currentPrice);
      roundEdgeScore = norm(roundDistancePct, expectedRemainingMovePct);
    }
    final elapsedRatio = 1.0 - (safeSeconds / 300.0);
    final roundEdgeWeight = roundStartPrice == null
        ? 0.0
        : (0.10 + elapsedRatio * 0.28).clamp(0.10, 0.38).toDouble();

    final technicalRaw = (momentumScore * 0.20 +
            trendScore * 0.18 +
            rsiScore * 0.08 +
            vwapScore * 0.12 +
            rangePosition * 0.08 +
            persistence * 0.08 +
            imbalance * 0.10 +
            volumeImpulse * 0.08 +
            bodyPressure * 0.08)
        .clamp(-1.0, 1.0)
        .toDouble();

    final raw = (technicalRaw * (1 - roundEdgeWeight) +
            roundEdgeScore * roundEdgeWeight)
        .clamp(-1.0, 1.0)
        .toDouble();
    final score = raw * 100;

    final components = <double>[
      momentumScore,
      trendScore,
      rsiScore,
      vwapScore,
      rangePosition,
      persistence,
      imbalance,
      bodyPressure,
      if (roundStartPrice != null) roundEdgeScore,
    ];
    final meaningful = components.where((v) => v.abs() >= 0.12).toList();
    final targetSign = raw == 0 ? 0.0 : raw.sign;
    final agreeing = meaningful.where((v) => v.sign == targetSign).length;
    final agreementRatio =
        meaningful.isEmpty ? 0.0 : agreeing / meaningful.length;

    final momentumVsBookConflict = momentumScore.abs() > 0.24 &&
        imbalance.abs() > 0.20 &&
        momentumScore.sign != imbalance.sign;
    final trendVsMomentumConflict = trendScore.abs() > 0.25 &&
        momentumScore.abs() > 0.25 &&
        trendScore.sign != momentumScore.sign;
    final edgeVsTrendConflict = roundStartPrice != null &&
        roundEdgeScore.abs() > 0.30 &&
        trendScore.abs() > 0.25 &&
        roundEdgeScore.sign != trendScore.sign;

    var directionFlips = 0;
    int candleDirection(Candle candle) => candle.close > candle.open
        ? 1
        : candle.close < candle.open
            ? -1
            : 0;
    final flipCandles = recent.sublist(recent.length - 8);
    var previousDirection = candleDirection(flipCandles.first);
    for (final candle in flipCandles.skip(1)) {
      final currentDirection = candleDirection(candle);
      if (previousDirection != 0 &&
          currentDirection != 0 &&
          previousDirection != currentDirection) {
        directionFlips++;
      }
      if (currentDirection != 0) previousDirection = currentDirection;
    }
    final flipRatio = directionFlips / (flipCandles.length - 1);

    final conflictCount = [
      momentumVsBookConflict,
      trendVsMomentumConflict,
      edgeVsTrendConflict,
    ].where((value) => value).length;
    final conflictRatio = conflictCount / 3.0;
    final atrInstability = ((atrPct - 0.10) / 0.55)
        .clamp(0.0, 1.0)
        .toDouble();
    final volumeShock = ((volumeRatio - 1.25) / 1.75)
        .clamp(0.0, 1.0)
        .toDouble();
    final instabilityScore = (atrInstability * 0.34 +
            flipRatio * 0.25 +
            wickNoise * 0.20 +
            conflictRatio * 0.16 +
            volumeShock * 0.05) *
        100;
    final stability = instabilityScore >= 68
        ? MarketStability.veryUnstable
        : instabilityScore >= 38
            ? MarketStability.unstable
            : MarketStability.stable;

    var confidence = 50.0 + score.abs() * 0.34 + agreementRatio * 13.0;
    if (momentumVsBookConflict) confidence -= 6;
    if (trendVsMomentumConflict) confidence -= 7;
    if (edgeVsTrendConflict) confidence -= 6;
    if (volumeRatio < 0.70) confidence -= 5;
    if (rsiExtreme) confidence -= 3;
    if (atrPct < 0.045) confidence -= 6;
    if (atrPct > 0.95) confidence -= 5;
    if (stability == MarketStability.unstable) confidence -= 7;
    if (stability == MarketStability.veryUnstable) confidence -= 14;

    if (roundStartPrice != null && safeSeconds <= 75) {
      final edgeStrength = roundDistancePct.abs() / expectedRemainingMovePct;
      if (edgeStrength >= 1.25) confidence += 5;
      if (edgeStrength < 0.25) confidence -= 7;
    }

    confidence = confidence.clamp(50.0, 91.0).toDouble();

    final lowQuality = score.abs() < 28 ||
        confidence < 64 ||
        agreementRatio < 0.56 ||
        volumeRatio < 0.48 ||
        stability == MarketStability.veryUnstable ||
        (stability == MarketStability.unstable && score.abs() < 42) ||
        (trendVsMomentumConflict && score.abs() < 48);

    final direction = lowQuality
        ? PulseDirection.noTrade
        : score > 0
            ? PulseDirection.up
            : PulseDirection.down;

    final reasons = <String>[
      momentumScore > 0.2
          ? 'Momentum de 1-5 min favorece compradores.'
          : momentumScore < -0.2
              ? 'Momentum de 1-5 min favorece vendedores.'
              : 'Momentum corto sin dirección clara.',
      trendScore > 0.18
          ? 'EMA y pendiente confirman tendencia alcista.'
          : trendScore < -0.18
              ? 'EMA y pendiente confirman tendencia bajista.'
              : 'Tendencia corta poco definida.',
      rsi > 56
          ? 'RSI confirma presión compradora.'
          : rsi < 44
              ? 'RSI confirma presión vendedora.'
              : 'RSI cerca de zona neutral.',
      vwapScore > 0.15
          ? 'Precio por encima del VWAP reciente.'
          : vwapScore < -0.15
              ? 'Precio por debajo del VWAP reciente.'
              : 'Precio muy próximo al VWAP.',
      volumeRatio > 1.20
          ? 'Volumen reciente por encima de su referencia.'
          : volumeRatio < 0.75
              ? 'Volumen reciente débil.'
              : 'Volumen reciente normal.',
      if (roundStartPrice != null)
        'Ventaja de ronda ${roundDistancePct >= 0 ? '+' : ''}${roundDistancePct.toStringAsFixed(3)}% con ${safeSeconds}s restantes.',
      if (momentumVsBookConflict || trendVsMomentumConflict || edgeVsTrendConflict)
        'Hay conflicto entre señales; confianza reducida.',
      'Mercado ${stability == MarketStability.stable ? 'estable' : stability == MarketStability.unstable ? 'inestable' : 'muy inestable'} · índice ${instabilityScore.toStringAsFixed(0)}/100.',
      if (stability == MarketStability.veryUnstable)
        'Volatilidad/ruido excesivos: Nexora fuerza NO TRADE.',
      'Confluencia ${(agreementRatio * 100).toStringAsFixed(0)}% · ATR ${atrPct.toStringAsFixed(3)}%.',
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
      instabilityScore: instabilityScore,
      stability: stability,
      reasons: reasons,
    );
  }

  double _ema(List<double> values, int period) {
    final k = 2.0 / (period + 1);
    var ema = values.first;
    for (final value in values.skip(1)) {
      ema = value * k + ema * (1 - k);
    }
    return ema;
  }

  double _rsi(List<double> closes, int period) {
    if (closes.length <= period) return 50.0;
    var gains = 0.0;
    var losses = 0.0;
    final start = closes.length - period;
    for (var i = start; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses -= change;
      }
    }
    if (losses == 0) return gains == 0 ? 50.0 : 100.0;
    final rs = gains / losses;
    return 100.0 - (100.0 / (1.0 + rs));
  }

  double _vwap(List<Candle> candles) {
    var pv = 0.0;
    var totalVolume = 0.0;
    for (final candle in candles) {
      final typical = (candle.high + candle.low + candle.close) / 3;
      pv += typical * candle.volume;
      totalVolume += candle.volume;
    }
    if (totalVolume <= 0) return candles.last.close;
    return pv / totalVolume;
  }

  double _atrPct(List<Candle> candles, int period) {
    if (candles.length < 2) return 0.0;
    final start = math.max(1, candles.length - period);
    var totalTr = 0.0;
    var count = 0;
    for (var i = start; i < candles.length; i++) {
      final candle = candles[i];
      final prevClose = candles[i - 1].close;
      final tr = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - prevClose).abs(),
          (candle.low - prevClose).abs(),
        ),
      );
      totalTr += tr;
      count++;
    }
    if (count == 0 || candles.last.close == 0) return 0.0;
    return (totalTr / count) / candles.last.close * 100;
  }

  double _slopePctPerCandle(List<double> values) {
    if (values.length < 2 || values.last == 0) return 0.0;
    final n = values.length.toDouble();
    var sumX = 0.0;
    var sumY = 0.0;
    var sumXY = 0.0;
    var sumXX = 0.0;
    for (var i = 0; i < values.length; i++) {
      final x = i.toDouble();
      final y = values[i];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }
    final denominator = n * sumXX - sumX * sumX;
    if (denominator == 0) return 0.0;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    return slope / values.last * 100;
  }
}
