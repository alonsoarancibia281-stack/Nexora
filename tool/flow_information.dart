// Does the order flow know anything the diffusion anchor does not?
//
// The end-to-end A/B answered a different question — "does the flow help as
// currently wired" — and could not separate a weak signal from a diluted one.
// This asks the question directly: fit the round outcome on the anchor alone,
// then add one feature at a time and test whether its coefficient is
// distinguishable from zero.
//
// A null result here is conclusive in a way the A/B was not: if a feature
// carries no information beyond the anchor, no amount of rewiring can extract
// any. A significant result would mean the opposite — the information is there
// and the fusion is throwing it away.
//
// Usage:
//   dart run tool/flow_information.dart [--days 30]

import 'dart:io';
import 'dart:math' as math;

import 'package:nexora_markets_ai/features/pulse/domain/pulse_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

import 'backtest.dart' show loadKlines, lastClosedIndex;
import 'order_flow.dart';

/// One observation: the anchor the engine would have had, the candidate
/// features, and what the round actually did.
class Sample {
  Sample(this.anchorLogit, this.features, this.outcome);

  final double anchorLogit;
  final Map<String, double> features;
  final double outcome;
}

class LogitFit {
  const LogitFit(this.beta, this.se, this.logLikelihood, this.converged);

  final List<double> beta;
  final List<double> se;
  final double logLikelihood;
  final bool converged;
}

/// Iteratively reweighted least squares, which also hands back the standard
/// errors from the inverse information matrix.
LogitFit fitLogistic(List<List<double>> x, List<double> y) {
  final n = y.length;
  final p = x.first.length;
  final beta = List<double>.filled(p, 0);
  var cov = List<List<double>>.generate(p, (_) => List<double>.filled(p, 0));
  var converged = false;

  for (var iteration = 0; iteration < 60; iteration++) {
    final information =
        List<List<double>>.generate(p, (_) => List<double>.filled(p, 0));
    final score = List<double>.filled(p, 0);
    for (var i = 0; i < n; i++) {
      var eta = 0.0;
      for (var j = 0; j < p; j++) {
        eta += beta[j] * x[i][j];
      }
      final mu = 1 / (1 + math.exp(-eta.clamp(-30.0, 30.0)));
      final weight = math.max(mu * (1 - mu), 1e-10);
      final residual = y[i] - mu;
      for (var a = 0; a < p; a++) {
        score[a] += x[i][a] * residual;
        for (var b = 0; b < p; b++) {
          information[a][b] += x[i][a] * x[i][b] * weight;
        }
      }
    }
    final inverse = invert(information);
    if (inverse == null) break;
    cov = inverse;
    var largestStep = 0.0;
    for (var a = 0; a < p; a++) {
      var step = 0.0;
      for (var b = 0; b < p; b++) {
        step += inverse[a][b] * score[b];
      }
      beta[a] += step;
      largestStep = math.max(largestStep, step.abs());
    }
    if (largestStep < 1e-10) {
      converged = true;
      break;
    }
  }

  var logLikelihood = 0.0;
  for (var i = 0; i < n; i++) {
    var eta = 0.0;
    for (var j = 0; j < p; j++) {
      eta += beta[j] * x[i][j];
    }
    final mu = (1 / (1 + math.exp(-eta.clamp(-30.0, 30.0)))).clamp(1e-12, 1 - 1e-12);
    logLikelihood += y[i] * math.log(mu) + (1 - y[i]) * math.log(1 - mu);
  }

  return LogitFit(
    beta,
    [for (var a = 0; a < p; a++) math.sqrt(math.max(cov[a][a], 0))],
    logLikelihood,
    converged,
  );
}

List<List<double>>? invert(List<List<double>> matrix) {
  final n = matrix.length;
  final work = List<List<double>>.generate(
    n,
    (i) => <double>[
      ...matrix[i],
      for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0,
    ],
  );
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (work[r][col].abs() > work[pivot][col].abs()) pivot = r;
    }
    if (work[pivot][col].abs() < 1e-14) return null;
    final swap = work[col];
    work[col] = work[pivot];
    work[pivot] = swap;
    final value = work[col][col];
    for (var j = 0; j < 2 * n; j++) {
      work[col][j] /= value;
    }
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final factor = work[r][col];
      if (factor == 0) continue;
      for (var j = 0; j < 2 * n; j++) {
        work[r][j] -= factor * work[col][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) work[i].sublist(n)];
}

double normalCdf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  final a = x.abs() / math.sqrt(2.0);
  final t = 1.0 / (1.0 + .3275911 * a);
  final erf = 1.0 -
      (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - .284496736) *
                  t +
              .254829592) *
          t *
          math.exp(-a * a));
  return .5 * (1 + sign * erf);
}

double twoSidedP(double z) => 2 * (1 - normalCdf(z.abs()));

Future<void> main(List<String> args) async {
  var days = 30;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.tryParse(args[i + 1]) ?? days;
    }
  }

  final rounds = days * 288 + 400;
  stdout.writeln('Descargando historia…');
  final oneMinute = await loadKlines('BTCUSDT', '1m', rounds * 5 + 200);
  final fiveMinute = await loadKlines('BTCUSDT', '5m', rounds + 300);

  stdout.writeln('\nReconstruyendo el flujo de órdenes…');
  final flow = await const OrderFlowLoader().load('BTCUSDT', days);
  final range = flowRange(flow);
  if (range == null) {
    stdout.writeln('Sin datos de flujo.');
    exit(1);
  }
  stdout.writeln('  cobertura ${range.from.toIso8601String()} → '
      '${range.to.toIso8601String()}');

  const engine = PulseEngine();
  final samples = <Sample>[];

  for (var i = 300; i < fiveMinute.length - 1; i++) {
    final round = fiveMinute[i];
    final roundStart = round.openTime.toUtc();
    if (roundStart.isBefore(range.from.add(const Duration(minutes: 5))) ||
        roundStart.isAfter(range.to)) {
      continue;
    }
    final decisionMoment = roundStart.add(const Duration(seconds: 60));
    final minuteIndex =
        lastClosedIndex(oneMinute, decisionMoment, const Duration(minutes: 1));
    if (minuteIndex < 130) continue;
    final candles = oneMinute.sublist(minuteIndex - 119, minuteIndex + 1);

    final PulseSignal signal;
    try {
      signal = engine.analyze(
        candles: candles,
        bidVolume: 0,
        askVolume: 0,
        roundStartPrice: round.open,
        secondsRemaining: 240,
      );
    } catch (_) {
      continue;
    }

    final tape = flow.at(decisionMoment);
    if (tape.trades == 0) continue;

    // The anchor exactly as the engine builds it.
    final z = signal.expectedRemainingMovePct <= 0
        ? 0.0
        : (signal.roundDistancePct / signal.expectedRemainingMovePct)
            .clamp(-4.0, 4.0)
            .toDouble();
    final anchor = normalCdf(z).clamp(.05, .95);
    final anchorLogit = math.log(anchor / (1 - anchor));

    samples.add(Sample(anchorLogit, <String, double>{
      // Order flow, reconstructed from the tape.
      'flujo·desequilibrio agresor': tape.aggressorImbalance,
      'flujo·aceleración': tape.tradeAcceleration,
      'flujo·impulso de precio': tape.priceImpulseBps / 20,
      'flujo·persistencia': tape.flowPersistence,
      'flujo·órdenes grandes': tape.largeTradeBias,
      // Candle-derived controls: if these are null too, the anchor simply
      // absorbs everything and the null result says less than it seems.
      'vela·momentum': signal.momentumScore / 100,
      'vela·tendencia': signal.trendScore / 100,
      'vela·presión de cuerpo': signal.bodyPressure / 100,
      'vela·volumen': (signal.volumeRatio - 1).clamp(-1.0, 1.0).toDouble(),
      'vela·inestabilidad': signal.instabilityScore / 100,
    }, round.close > round.open ? 1.0 : 0.0));
  }

  if (samples.length < 500) {
    stdout.writeln('Muestra insuficiente: ${samples.length} rondas.');
    exit(1);
  }

  report(samples);
}

void report(List<Sample> samples) {
  final n = samples.length;
  final y = [for (final s in samples) s.outcome];
  final names = samples.first.features.keys.toList();

  // Standardise so the coefficients are comparable across features.
  final standardised = <String, List<double>>{};
  for (final name in names) {
    final raw = [for (final s in samples) s.features[name] ?? 0];
    final mean = raw.reduce((a, b) => a + b) / n;
    var variance = 0.0;
    for (final v in raw) {
      variance += (v - mean) * (v - mean);
    }
    final sd = math.sqrt(math.max(variance / (n - 1), 1e-18));
    standardised[name] = [for (final v in raw) (v - mean) / sd];
  }

  final baselineX = [
    for (final s in samples) <double>[1, s.anchorLogit],
  ];
  final baseline = fitLogistic(baselineX, y);

  stdout.writeln('\n${'=' * 74}');
  stdout.writeln('PRUEBA DE INFORMACIÓN · ¿aporta algo más allá del ancla?');
  stdout.writeln('=' * 74);
  stdout.writeln('Rondas .................... $n');
  stdout.writeln('Modelo base ............... y ~ 1 + logit(ancla)');
  stdout.writeln('  coeficiente del ancla ... '
      '${baseline.beta[1].toStringAsFixed(4)} '
      '± ${baseline.se[1].toStringAsFixed(4)}  '
      '(z=${(baseline.beta[1] / baseline.se[1]).toStringAsFixed(2)})');
  stdout.writeln('  log-verosimilitud ....... '
      '${baseline.logLikelihood.toStringAsFixed(2)}');
  stdout.writeln('');
  stdout.writeln('Un coeficiente del ancla cercano a 1 significa que está bien');
  stdout.writeln('calibrada; por debajo, que exagera lo que sabe.');
  stdout.writeln('');
  stdout.writeln('Cada feature entra junto al ancla. La columna que decide es p:');
  stdout.writeln('por debajo de 0,05/10 features ≈ 0,005 (Bonferroni) hay señal.');
  stdout.writeln('');
  stdout.writeln('  feature                        coef      z        p       ΔlogL');
  stdout.writeln('  ${'-' * 66}');

  final results = <List<dynamic>>[];
  for (final name in names) {
    final column = standardised[name]!;
    final x = [
      for (var i = 0; i < n; i++) <double>[1, samples[i].anchorLogit, column[i]],
    ];
    final fit = fitLogistic(x, y);
    final coefficient = fit.beta[2];
    final se = fit.se[2];
    final z = se <= 0 ? 0.0 : coefficient / se;
    final p = twoSidedP(z);
    final deltaLogL = fit.logLikelihood - baseline.logLikelihood;
    results.add([name, coefficient, z, p, deltaLogL]);
    stdout.writeln('  ${name.padRight(30)}'
        '${coefficient.toStringAsFixed(4).padLeft(8)}'
        '${z.toStringAsFixed(2).padLeft(8)}'
        '${p.toStringAsFixed(4).padLeft(9)}'
        '${deltaLogL.toStringAsFixed(2).padLeft(10)}'
        '${p < .005 ? '  ← señal' : ''}');
  }

  // Joint test: all five flow features at once.
  final flowNames = names.where((name) => name.startsWith('flujo·')).toList();
  final jointX = [
    for (var i = 0; i < n; i++)
      <double>[
        1,
        samples[i].anchorLogit,
        for (final name in flowNames) standardised[name]![i],
      ],
  ];
  final joint = fitLogistic(jointX, y);
  final jointStatistic = 2 * (joint.logLikelihood - baseline.logLikelihood);
  stdout.writeln('');
  stdout.writeln('Prueba conjunta de las ${flowNames.length} features de flujo:');
  stdout.writeln('  razón de verosimilitud χ² = '
      '${jointStatistic.toStringAsFixed(2)} con ${flowNames.length} g.l.');
  stdout.writeln('  crítico al 5% ≈ '
      '${flowNames.length == 5 ? '11.07' : '—'}  → '
      '${jointStatistic > 11.07 ? 'HAY información conjunta' : 'sin información conjunta'}');

  final best = results.where((r) => (r[0] as String).startsWith('flujo·')).toList()
    ..sort((a, b) => (b[2] as double).abs().compareTo((a[2] as double).abs()));
  if (best.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('La feature de flujo más fuerte es ${best.first[0]} '
        '(z=${(best.first[2] as double).toStringAsFixed(2)}).');
  }
  stdout.writeln('=' * 74);
}
