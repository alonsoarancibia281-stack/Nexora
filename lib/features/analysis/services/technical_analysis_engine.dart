import 'dart:math' as math;
import '../../market/domain/candle.dart';
import '../domain/technical_analysis.dart';

class TechnicalAnalysisEngine {
  TechnicalAnalysis analyze(List<Candle> candles) {
    if (candles.length < 210) {
      throw ArgumentError('Se requieren al menos 210 velas para un análisis completo.');
    }

    final closes = candles.map((c) => c.close).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final last = candles.last;

    final ema9 = _ema(closes, 9).last;
    final ema21 = _ema(closes, 21).last;
    final ema50 = _ema(closes, 50).last;
    final ema200 = _ema(closes, 200).last;
    final rsi = _rsi(closes, 14);
    final macdSeries = _macd(closes);
    final macd = macdSeries.$1;
    final macdSignal = macdSeries.$2;
    final boll = _bollinger(closes, 20, 2);
    final atr = _atr(candles, 14);
    final adx = _adx(candles, 14);
    final stochastic = _stochastic(candles, 14, 3);

    final recentHighs = highs.sublist(highs.length - 50);
    final recentLows = lows.sublist(lows.length - 50);
    final support = recentLows.reduce(math.max);
    final resistance = recentHighs.reduce(math.min);
    final volatilityPercent = last.close == 0 ? 0 : (atr / last.close) * 100;

    var score = 0.0;
    score += ema9 > ema21 ? 10 : -10;
    score += ema21 > ema50 ? 10 : -10;
    score += ema50 > ema200 ? 15 : -15;
    score += macd > macdSignal ? 15 : -15;
    score += rsi >= 55 && rsi <= 70 ? 10 : rsi <= 45 && rsi >= 30 ? -10 : 0;
    score += stochastic.$1 > stochastic.$2 ? 8 : -8;
    score += last.close > boll.$2 ? 8 : -8;
    score += adx >= 25 ? (ema21 > ema50 ? 12 : -12) : 0;
    score = score.clamp(-100, 100);

    final trend = score >= 70
        ? 'Impulso alcista fuerte'
        : score >= 35
            ? 'Condiciones alcistas moderadas'
            : score <= -70
                ? 'Impulso bajista fuerte'
                : score <= -35
                    ? 'Presión bajista'
                    : 'Mercado lateral o sin confirmación';

    final risk = volatilityPercent >= 5
        ? 'Elevado'
        : volatilityPercent >= 2.5
            ? 'Moderado'
            : 'Controlado';

    final confidence = ((score.abs() * 0.65) + (adx.clamp(0, 50) * 0.7)).clamp(0, 100).toDouble();

    return TechnicalAnalysis(
      rsi: rsi,
      macd: macd,
      macdSignal: macdSignal,
      ema9: ema9,
      ema21: ema21,
      ema50: ema50,
      ema200: ema200,
      bollingerUpper: boll.$1,
      bollingerMiddle: boll.$2,
      bollingerLower: boll.$3,
      atr: atr,
      adx: adx,
      stochasticK: stochastic.$1,
      stochasticD: stochastic.$2,
      support: support,
      resistance: resistance,
      volatilityPercent: volatilityPercent,
      score: score.round(),
      trend: trend,
      risk: risk,
      confidence: confidence,
    );
  }

  List<double> _ema(List<double> values, int period) {
    final multiplier = 2 / (period + 1);
    final out = <double>[];
    var previous = values.take(period).reduce((a, b) => a + b) / period;
    for (var i = 0; i < values.length; i++) {
      if (i < period - 1) {
        out.add(values[i]);
      } else if (i == period - 1) {
        out.add(previous);
      } else {
        previous = (values[i] - previous) * multiplier + previous;
        out.add(previous);
      }
    }
    return out;
  }

  double _rsi(List<double> closes, int period) {
    var gains = 0.0;
    var losses = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      if (change >= 0) {
        gains += change;
      } else {
        losses += -change;
      }
    }
    if (losses == 0) return 100;
    final rs = (gains / period) / (losses / period);
    return 100 - (100 / (1 + rs));
  }

  (double, double) _macd(List<double> closes) {
    final fast = _ema(closes, 12);
    final slow = _ema(closes, 26);
    final line = List<double>.generate(closes.length, (i) => fast[i] - slow[i]);
    final signal = _ema(line, 9);
    return (line.last, signal.last);
  }

  (double, double, double) _bollinger(List<double> closes, int period, double deviations) {
    final data = closes.sublist(closes.length - period);
    final mean = data.reduce((a, b) => a + b) / period;
    final variance = data.map((v) => math.pow(v - mean, 2).toDouble()).reduce((a, b) => a + b) / period;
    final std = math.sqrt(variance);
    return (mean + deviations * std, mean, mean - deviations * std);
  }

  double _atr(List<Candle> candles, int period) {
    final trs = <double>[];
    for (var i = candles.length - period; i < candles.length; i++) {
      final c = candles[i];
      final prevClose = candles[i - 1].close;
      trs.add(math.max(c.high - c.low, math.max((c.high - prevClose).abs(), (c.low - prevClose).abs())));
    }
    return trs.reduce((a, b) => a + b) / trs.length;
  }

  double _adx(List<Candle> candles, int period) {
    var plusDm = 0.0;
    var minusDm = 0.0;
    var tr = 0.0;
    for (var i = candles.length - period; i < candles.length; i++) {
      final current = candles[i];
      final previous = candles[i - 1];
      final up = current.high - previous.high;
      final down = previous.low - current.low;
      if (up > down && up > 0) plusDm += up;
      if (down > up && down > 0) minusDm += down;
      tr += math.max(current.high - current.low, math.max((current.high - previous.close).abs(), (current.low - previous.close).abs()));
    }
    if (tr == 0) return 0;
    final plusDi = 100 * plusDm / tr;
    final minusDi = 100 * minusDm / tr;
    final denom = plusDi + minusDi;
    if (denom == 0) return 0;
    return 100 * (plusDi - minusDi).abs() / denom;
  }

  (double, double) _stochastic(List<Candle> candles, int period, int smooth) {
    final ks = <double>[];
    for (var offset = smooth - 1; offset >= 0; offset--) {
      final end = candles.length - offset;
      final start = end - period;
      final slice = candles.sublist(start, end);
      final highest = slice.map((c) => c.high).reduce(math.max);
      final lowest = slice.map((c) => c.low).reduce(math.min);
      final close = slice.last.close;
      final k = highest == lowest ? 50.0 : ((close - lowest) / (highest - lowest)) * 100;
      ks.add(k);
    }
    final d = ks.reduce((a, b) => a + b) / ks.length;
    return (ks.last, d);
  }
}
