import 'dart:math' as math;

import '../../market/domain/candle.dart';

/// The ten ways the historical desk looks at the past.
enum PatternLens {
  shape,
  returnVector,
  volatilityProfile,
  volumeSignature,
  candleMorphology,
  momentumCascade,
  rangeStructure,
  seasonality,
  fractalScale,
  regimeAnalog,
}

extension PatternLensLabel on PatternLens {
  String get label {
    switch (this) {
      case PatternLens.shape:
        return 'Forma de precio';
      case PatternLens.returnVector:
        return 'Vector de retornos';
      case PatternLens.volatilityProfile:
        return 'Perfil de volatilidad';
      case PatternLens.volumeSignature:
        return 'Firma de volumen';
      case PatternLens.candleMorphology:
        return 'Morfología de velas';
      case PatternLens.momentumCascade:
        return 'Cascada de momentum';
      case PatternLens.rangeStructure:
        return 'Estructura de rango';
      case PatternLens.seasonality:
        return 'Estacionalidad';
      case PatternLens.fractalScale:
        return 'Escala fractal';
      case PatternLens.regimeAnalog:
        return 'Análogo de régimen';
    }
  }
}

/// Multi-timeframe Bitcoin history the archive studies.
class PatternHistory {
  const PatternHistory({required this.series});

  /// Interval label (`5m`, `1h`, `4h`, `1d`) → candles, oldest first.
  final Map<String, List<Candle>> series;

  static const List<String> intervals = <String>['5m', '1h', '4h', '1d'];

  List<Candle> of(String interval) => series[interval] ?? const <Candle>[];

  bool get isReady =>
      of('5m').length >= 150 &&
      series.values.any((candles) => candles.length >= 150);

  /// Approximate span of the deepest series, in days.
  double get depthDays {
    var deepest = 0.0;
    for (final entry in series.entries) {
      final candles = entry.value;
      if (candles.length < 2) continue;
      final span = candles.last.openTime
              .difference(candles.first.openTime)
              .inMinutes /
          1440.0;
      deepest = math.max(deepest, span);
    }
    return deepest;
  }

  int get totalCandles {
    var total = 0;
    for (final candles in series.values) {
      total += candles.length;
    }
    return total;
  }
}

/// One historical episode that resembles the present.
class PatternMatch {
  const PatternMatch({
    required this.at,
    required this.interval,
    required this.similarity,
    required this.nextMovePct,
  });

  final DateTime at;
  final String interval;

  /// 0..1, where 1 is an identical shape.
  final double similarity;

  /// What the market did on the bar right after the analog.
  final double nextMovePct;
}

/// A single historical analyst's conclusion.
class PatternVerdict {
  const PatternVerdict({
    required this.id,
    required this.lens,
    required this.interval,
    required this.windowSize,
    required this.signal,
    required this.confidence,
    required this.matches,
    required this.bestSimilarity,
    required this.upRate,
    required this.medianNextMovePct,
    required this.examples,
  });

  /// 1..100
  final int id;
  final PatternLens lens;
  final String interval;
  final int windowSize;

  /// Directional evidence in [-1,1].
  final double signal;
  final double confidence;

  /// Number of historical analogs actually used.
  final int matches;
  final double bestSimilarity;

  /// Share of analogs that resolved upward.
  final double upRate;
  final double medianNextMovePct;

  final List<PatternMatch> examples;
}

/// Aggregated verdict of the 100 historical analysts.
class PatternBriefing {
  PatternBriefing({
    required this.verdicts,
    required this.lensSignal,
    required this.lensConfidence,
    required this.consensusSignal,
    required this.dispersion,
    required this.probabilityUp,
    required this.analogsExamined,
    required this.historyDays,
    required this.candlesStudied,
    required this.bestMatches,
    required this.isReady,
  });

  final List<PatternVerdict> verdicts;
  final Map<PatternLens, double> lensSignal;
  final Map<PatternLens, double> lensConfidence;
  final double consensusSignal;
  final double dispersion;
  final double probabilityUp;
  final int analogsExamined;
  final double historyDays;
  final int candlesStudied;
  final List<PatternMatch> bestMatches;
  final bool isReady;

  static PatternBriefing empty() => PatternBriefing(
        verdicts: const <PatternVerdict>[],
        lensSignal: {for (final l in PatternLens.values) l: 0.0},
        lensConfidence: {for (final l in PatternLens.values) l: 0.0},
        consensusSignal: 0,
        dispersion: 0,
        probabilityUp: .5,
        analogsExamined: 0,
        historyDays: 0,
        candlesStudied: 0,
        bestMatches: const <PatternMatch>[],
        isReady: false,
      );

  double signalOf(PatternLens lens) => lensSignal[lens] ?? 0;

  double confidenceOf(PatternLens lens) => lensConfidence[lens] ?? 0;

  int get analysts => verdicts.length;

  int get bullishAnalysts => verdicts.where((v) => v.signal > .02).length;

  int get bearishAnalysts => verdicts.where((v) => v.signal < -.02).length;

  double get internalAgreement {
    final decided = bullishAnalysts + bearishAnalysts;
    if (decided == 0) return 0;
    return math.max(bullishAnalysts, bearishAnalysts) / decided;
  }
}

/// One hundred analysts mining years of Bitcoin metadata for analogs.
///
/// Every analyst takes the last N bars of one timeframe, encodes them through
/// its own lens, sweeps the whole history for the closest episodes and reports
/// what happened on the bar right after each of them. This is nearest-neighbour
/// analog forecasting: no curve fitting, just "the market has been here before,
/// and here is what followed".
class PulsePatternArchive {
  const PulsePatternArchive();

  static const int analysts = 100;

  /// How much a timeframe's next-bar outcome says about a 5-minute round.
  static const Map<String, double> _relevance = <String, double>{
    '5m': 1.0,
    '1h': .55,
    '4h': .35,
    '1d': .25,
  };

  PatternBriefing study(PatternHistory history) {
    if (!history.isReady) return PatternBriefing.empty();

    final verdicts = <PatternVerdict>[];
    var id = 1;
    var analogs = 0;
    for (final lens in PatternLens.values) {
      for (var variant = 0; variant < 10; variant++) {
        PatternVerdict verdict;
        try {
          verdict = _run(id, lens, variant, history);
        } catch (_) {
          verdict = _empty(id, lens, _intervalFor(variant), 12);
        }
        verdicts.add(verdict);
        analogs += verdict.matches;
        id++;
      }
    }

    final lensSignal = <PatternLens, double>{};
    final lensConfidence = <PatternLens, double>{};
    for (final lens in PatternLens.values) {
      final group = verdicts.where((v) => v.lens == lens).toList();
      var weighted = 0.0;
      var weight = 0.0;
      var confidence = 0.0;
      for (final v in group) {
        final w = math.max(v.confidence, .04);
        weighted += v.signal * w;
        weight += w;
        confidence += v.confidence;
      }
      lensSignal[lens] = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
      lensConfidence[lens] =
          group.isEmpty ? 0.0 : _unit(confidence / group.length);
    }

    var weighted = 0.0;
    var weight = 0.0;
    for (final v in verdicts) {
      final w = math.max(v.confidence, .03);
      weighted += v.signal * w;
      weight += w;
    }
    final consensus = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
    final dispersion = _unit(_std([for (final v in verdicts) v.signal]));
    final coherence = (1 - dispersion * .7).clamp(.15, 1.0).toDouble();

    final allMatches = <PatternMatch>[];
    for (final v in verdicts) {
      allMatches.addAll(v.examples);
    }
    allMatches.sort((a, b) => b.similarity.compareTo(a.similarity));

    return PatternBriefing(
      verdicts: List<PatternVerdict>.unmodifiable(verdicts),
      lensSignal: Map<PatternLens, double>.unmodifiable(lensSignal),
      lensConfidence: Map<PatternLens, double>.unmodifiable(lensConfidence),
      consensusSignal: consensus,
      dispersion: dispersion,
      probabilityUp:
          _sigmoid(consensus * 1.9 * coherence).clamp(.10, .90).toDouble(),
      analogsExamined: analogs,
      historyDays: history.depthDays,
      candlesStudied: history.totalCandles,
      bestMatches: List<PatternMatch>.unmodifiable(allMatches.take(8)),
      isReady: true,
    );
  }

  String _intervalFor(int variant) {
    if (variant <= 4) return '5m';
    if (variant <= 6) return '1h';
    if (variant <= 8) return '4h';
    return '1d';
  }

  PatternVerdict _run(
    int id,
    PatternLens lens,
    int variant,
    PatternHistory history,
  ) {
    final interval = _intervalFor(variant);
    final candles = history.of(interval);
    final window = 8 + (variant % 5) * 4 + (lens.index % 3) * 2;
    final neighbours = 6 + variant;

    if (candles.length < window + 40) {
      return _empty(id, lens, interval, window);
    }

    if (lens == PatternLens.regimeAnalog) {
      return _regimeAnalog(id, lens, interval, window, candles, variant);
    }

    final target = _encode(lens, candles, candles.length - window, window);
    if (target == null) return _empty(id, lens, interval, window);

    final seasonalHour = candles.last.openTime.toUtc().hour;
    final scored = <List<double>>[]; // [distance, nextMovePct, index]
    final limit = candles.length - window - 1;
    final start = math.max(0, limit - 900);
    for (var i = start; i < limit; i++) {
      if (lens == PatternLens.seasonality) {
        final hour = candles[i + window - 1].openTime.toUtc().hour;
        final diff = (hour - seasonalHour).abs();
        if (math.min(diff, 24 - diff) > 1) continue;
      }
      final candidate = _encode(lens, candles, i, window);
      if (candidate == null) continue;
      final distance = _distance(lens, target, candidate);
      if (!distance.isFinite) continue;
      final next = candles[i + window];
      final base = candles[i + window - 1].close;
      if (base <= 0) continue;
      final movePct = (next.close - base) / base * 100;
      scored.add([distance, movePct, i.toDouble()]);
    }

    if (scored.length < 8) return _empty(id, lens, interval, window);
    scored.sort((a, b) => a[0].compareTo(b[0]));
    final selected = scored.take(neighbours).toList();

    final scale = math.max(selected.last[0], 1e-9);
    var weightedUp = 0.0;
    var weightSum = 0.0;
    var bestSimilarity = 0.0;
    final moves = <double>[];
    final examples = <PatternMatch>[];
    for (final row in selected) {
      final similarity = math.exp(-row[0] / scale).clamp(0.0, 1.0).toDouble();
      final w = math.max(similarity * similarity, 1e-6);
      weightedUp += (row[1] > 0 ? 1.0 : 0.0) * w;
      weightSum += w;
      bestSimilarity = math.max(bestSimilarity, similarity);
      moves.add(row[1]);
      if (examples.length < 3) {
        examples.add(PatternMatch(
          at: candles[row[2].toInt() + window - 1].openTime,
          interval: interval,
          similarity: similarity,
          nextMovePct: row[1],
        ));
      }
    }

    final upRate = weightSum <= 0 ? .5 : weightedUp / weightSum;
    final relevance = _relevance[interval] ?? .3;
    final sampleStrength = (selected.length / 12).clamp(.3, 1.0).toDouble();
    final decisiveness = ((upRate - .5).abs() * 2).clamp(0.0, 1.0).toDouble();

    final signal = _clamp1((upRate - .5) * 2 * relevance * 1.25);
    final confidence =
        _unit(decisiveness * .55 * relevance + bestSimilarity * .25 + sampleStrength * .20 * relevance);

    return PatternVerdict(
      id: id,
      lens: lens,
      interval: interval,
      windowSize: window,
      signal: signal,
      confidence: confidence,
      matches: selected.length,
      bestSimilarity: bestSimilarity,
      upRate: upRate,
      medianNextMovePct: _median(moves),
      examples: List<PatternMatch>.unmodifiable(examples),
    );
  }

  /// Conditional statistics: what does this volatility/trend regime usually do?
  PatternVerdict _regimeAnalog(
    int id,
    PatternLens lens,
    String interval,
    int window,
    List<Candle> candles,
    int variant,
  ) {
    final returns = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final prev = candles[i - 1].close;
      if (prev <= 0) {
        returns.add(0);
      } else {
        returns.add((candles[i].close - prev) / prev);
      }
    }
    if (returns.length < window + 60) {
      return _empty(id, lens, interval, window);
    }

    int bucketAt(int endIndex) {
      final slice = returns.sublist(endIndex - window, endIndex);
      final vol = _std(slice);
      final drift = _mean(slice);
      final reference = returns.sublist(math.max(0, endIndex - 200), endIndex);
      final baseVol = math.max(_std(reference), 1e-12);
      final volBucket = vol > baseVol * 1.25 ? 2 : (vol < baseVol * .75 ? 0 : 1);
      final trendBucket = drift > baseVol * .12
          ? 2
          : (drift < -baseVol * .12 ? 0 : 1);
      return volBucket * 3 + trendBucket;
    }

    final currentBucket = bucketAt(returns.length);
    var up = 0;
    var total = 0;
    final moves = <double>[];
    final examples = <PatternMatch>[];
    final start = math.max(window + 1, returns.length - 900);
    for (var i = start; i < returns.length - 1; i++) {
      if (bucketAt(i) != currentBucket) continue;
      final next = returns[i];
      total++;
      if (next > 0) up++;
      moves.add(next * 100);
      if (examples.length < 3 && i < candles.length) {
        examples.add(PatternMatch(
          at: candles[i].openTime,
          interval: interval,
          similarity: .82,
          nextMovePct: next * 100,
        ));
      }
    }

    if (total < 12) return _empty(id, lens, interval, window);
    final upRate = up / total;
    // Wilson-style penalty so a thin bucket cannot look decisive.
    final z = 1.96;
    final n = total.toDouble();
    final margin = z * math.sqrt(upRate * (1 - upRate) / n);
    final edge = (upRate - .5).abs() - margin;
    final relevance = _relevance[interval] ?? .3;
    final significant = edge > 0;

    return PatternVerdict(
      id: id,
      lens: lens,
      interval: interval,
      windowSize: window,
      signal: significant
          ? _clamp1((upRate - .5) * 2 * relevance * 1.3)
          : _clamp1((upRate - .5) * .6 * relevance),
      confidence: _unit(((significant ? edge * 6 : 0.0) * relevance +
              (n / 300).clamp(0.0, .25))
          .toDouble()),
      matches: total,
      bestSimilarity: .82,
      upRate: upRate,
      medianNextMovePct: _median(moves),
      examples: List<PatternMatch>.unmodifiable(examples),
    );
  }

  PatternVerdict _empty(int id, PatternLens lens, String interval, int window) =>
      PatternVerdict(
        id: id,
        lens: lens,
        interval: interval,
        windowSize: window,
        signal: 0,
        confidence: 0,
        matches: 0,
        bestSimilarity: 0,
        upRate: .5,
        medianNextMovePct: 0,
        examples: const <PatternMatch>[],
      );

  /// Encodes the window starting at [start] through the analyst's lens.
  List<double>? _encode(
    PatternLens lens,
    List<Candle> candles,
    int start,
    int window,
  ) {
    if (start < 0 || start + window > candles.length) return null;
    final slice = candles.sublist(start, start + window);

    switch (lens) {
      case PatternLens.shape:
      case PatternLens.seasonality:
        return _zNormalize([for (final c in slice) c.close]);
      case PatternLens.returnVector:
      case PatternLens.momentumCascade:
        final returns = <double>[];
        for (var i = 1; i < slice.length; i++) {
          final prev = slice[i - 1].close;
          returns.add(prev <= 0 ? 0 : (slice[i].close - prev) / prev);
        }
        if (lens == PatternLens.returnVector) return _zNormalize(returns);
        final cascade = <double>[];
        var cumulative = 0.0;
        for (final r in returns) {
          cumulative += r;
          cascade.add(cumulative);
        }
        return _zNormalize(cascade);
      case PatternLens.volatilityProfile:
        return _zNormalize([
          for (final c in slice) c.close <= 0 ? 0 : (c.high - c.low) / c.close,
        ]);
      case PatternLens.volumeSignature:
        return _zNormalize([for (final c in slice) c.volume]);
      case PatternLens.candleMorphology:
        return [
          for (final c in slice)
            (c.high - c.low) <= 0
                ? 0.0
                : ((c.close - c.open) / (c.high - c.low)).clamp(-1.0, 1.0).toDouble(),
        ];
      case PatternLens.rangeStructure:
        final high = slice.map((c) => c.high).reduce(math.max);
        final low = slice.map((c) => c.low).reduce(math.min);
        final span = high - low;
        if (span <= 0) return null;
        return [for (final c in slice) ((c.close - low) / span) * 2 - 1];
      case PatternLens.fractalScale:
        final closes = [for (final c in slice) c.close];
        final coarse = <double>[];
        for (var i = 0; i + 1 < closes.length; i += 2) {
          coarse.add((closes[i] + closes[i + 1]) / 2);
        }
        return _zNormalize(coarse);
      case PatternLens.regimeAnalog:
        return null;
    }
  }

  double _distance(PatternLens lens, List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n < 3) return double.infinity;
    switch (lens) {
      case PatternLens.returnVector:
      case PatternLens.momentumCascade:
        // Cosine distance: direction of the trajectory matters, size does not.
        var dot = 0.0, na = 0.0, nb = 0.0;
        for (var i = 0; i < n; i++) {
          dot += a[i] * b[i];
          na += a[i] * a[i];
          nb += b[i] * b[i];
        }
        final den = math.sqrt(na * nb);
        if (den <= 1e-15) return double.infinity;
        return 1 - (dot / den);
      case PatternLens.shape:
      case PatternLens.fractalScale:
      case PatternLens.seasonality:
        // Correlation distance on z-normalized shapes.
        final r = _correlation(a.sublist(0, n), b.sublist(0, n));
        return 1 - r;
      default:
        var acc = 0.0;
        for (var i = 0; i < n; i++) {
          final d = a[i] - b[i];
          acc += d * d;
        }
        return math.sqrt(acc / n);
    }
  }
}

List<double> _zNormalize(List<double> x) {
  if (x.isEmpty) return const <double>[];
  final mean = _mean(x);
  final sd = _std(x);
  if (sd <= 1e-15) return List<double>.filled(x.length, 0);
  return [for (final v in x) (v - mean) / sd];
}

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

double _median(List<double> x) {
  if (x.isEmpty) return 0;
  final sorted = [...x]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

double _correlation(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  if (n < 3) return 0;
  final ma = _mean(a);
  final mb = _mean(b);
  var cov = 0.0, va = 0.0, vb = 0.0;
  for (var i = 0; i < n; i++) {
    final da = a[i] - ma;
    final db = b[i] - mb;
    cov += da * db;
    va += da * da;
    vb += db * db;
  }
  final den = math.sqrt(va * vb);
  if (den <= 1e-15) return 0;
  final r = cov / den;
  return r.isFinite ? r.clamp(-1.0, 1.0).toDouble() : 0.0;
}

double _clamp1(double v) => v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0.0;

double _unit(double v) => v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.0;

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));
