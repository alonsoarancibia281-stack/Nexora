// Where the prediction actually comes from, and how to make it sharper.
//
// Everything measured so far says the same thing: the diffusion anchor carries
// the merit, the councils tie it, and the tape adds a little on top. The anchor
// is Φ(d / σ√τ) — the part that can still be wrong is σ.
//
// Today σ comes from the 14-period ATR times a hand-picked 0.72. ATR is the
// true range, not the standard deviation of returns, and the ratio between the
// two moves with the regime, so the z the anchor feeds into Φ is systematically
// off. That is exactly what the fitted coefficient of 0.7754 was saying: the
// anchor is not miscalibrated because diffusion is the wrong model, it is
// miscalibrated because σ is estimated badly.
//
// This bench builds several anchors from the same rounds and asks which one is
// closest to honest. A coefficient of 1.0 means the anchor's probability can be
// taken at face value; anything below means it exaggerates.
//
// Usage:
//   dart run tool/anchor_lab.dart [--days 30] [--decide-at 60]

import 'dart:io';
import 'dart:math' as math;

import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_realized_volatility.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

import 'backtest.dart' show loadKlines, lastClosedIndex;
import 'flow_information.dart' show LogitFit, fitLogistic, normalCdf, twoSidedP;
import 'order_flow.dart';

/// One round, with every candidate anchor and every candidate feature.
class Row {
  Row({
    required this.anchors,
    required this.features,
    required this.outcome,
    required this.at,
  });

  /// Anchor name → probability the round closes up.
  final Map<String, double> anchors;
  final Map<String, double> features;
  final double outcome;
  final DateTime at;
}

double logit(double p) {
  final q = p.clamp(1e-5, 1 - 1e-5);
  return math.log(q / (1 - q));
}

double sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

Future<void> main(List<String> args) async {
  var days = 30;
  var decideAt = 60;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--days' && i + 1 < args.length) {
      days = int.tryParse(args[i + 1]) ?? days;
    }
    if (args[i] == '--decide-at' && i + 1 < args.length) {
      decideAt = int.tryParse(args[i + 1]) ?? decideAt;
    }
  }
  final remaining = 300 - decideAt;

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
  const volatility = PulseRealizedVolatility();

  // Volatility has a strong daily shape — the London and New York opens are
  // not 04:00 UTC — and a σ that ignores it is too wide half the day and too
  // narrow the other half. The shape is estimated only from the stretch that
  // precedes the validation tail, so the holdout stays clean.
  final trainUntil = range.from.add(
    Duration(
      milliseconds:
          (range.to.difference(range.from).inMilliseconds * .7).round(),
    ),
  );
  final seasonality = hourlyShape(oneMinute, trainUntil);
  stdout.writeln('\nForma horaria de la volatilidad (1,00 = día medio):');
  for (var block = 0; block < 24; block += 6) {
    final cells = [
      for (var h = block; h < block + 6; h++)
        '${h.toString().padLeft(2, '0')}h ${seasonality[h].toStringAsFixed(2)}',
    ];
    stdout.writeln('  ${cells.join('  ')}');
  }

  final rows = <Row>[];

  for (var i = 300; i < fiveMinute.length - 1; i++) {
    final round = fiveMinute[i];
    final roundStart = round.openTime.toUtc();
    if (roundStart.isBefore(range.from.add(const Duration(minutes: 5))) ||
        roundStart.isAfter(range.to)) {
      continue;
    }
    final decisionMoment = roundStart.add(Duration(seconds: decideAt));
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
        secondsRemaining: remaining,
      );
    } catch (_) {
      continue;
    }

    final tape = flow.at(decisionMoment);
    if (tape.trades == 0) continue;

    final distance = signal.roundDistancePct;
    final anchors = <String, double>{};

    double probability(double sigmaPct) {
      if (sigmaPct <= 0) return .5;
      final z = (distance / sigmaPct).clamp(-4.0, 4.0).toDouble();
      return normalCdf(z).clamp(.05, .95).toDouble();
    }

    // A) Whatever the engine is using right now. Once one of the estimators
    // below is wired in, this row becomes its twin and the pair works as a
    // check that what shipped is what was measured.
    anchors['motor (en producción)'] =
        probability(signal.expectedRemainingMovePct);

    // B) The standard deviation of one-minute log returns, EWMA, scaled by the
    // square root of the minutes still to run. No free constants.
    final ewma = volatility.ewmaPerMinutePct(candles);
    anchors['EWMA de retornos'] =
        probability(volatility.scale(ewma, remaining));

    // C) The same, told what time of day it is.
    final seasonal = seasonality[decisionMoment.hour];
    anchors['EWMA estacional'] =
        probability(volatility.scale(ewma * seasonal, remaining));

    // D) Bipower variation: the same estimate with the jumps taken out, so one
    // print does not inflate σ for the next hour.
    final bipower = volatility.bipowerPerMinutePct(candles);
    anchors['Bipotencia'] = probability(
      volatility.scale(bipower * seasonal, remaining),
    );

    // E) Plain equal-weight standard deviation over the last hour. The
    // simplest thing that could work, and the one the others have to beat.
    final plain = volatility.realizedPerMinutePct(candles);
    anchors['Desv. típica 60m'] =
        probability(volatility.scale(plain, remaining));

    final tape30 = flow.at(decisionMoment, windowSeconds: 30);
    final tape120 = flow.at(decisionMoment, windowSeconds: 120);
    final tape300 = flow.at(decisionMoment, windowSeconds: 300);

    rows.add(Row(
      at: roundStart,
      outcome: round.close > round.open ? 1.0 : 0.0,
      anchors: anchors,
      features: <String, double>{
        // The three that already earned their place.
        'flujo·desequilibrio 60s': tape.aggressorImbalance,
        'flujo·impulso 60s': tape.priceImpulseBps / 20,
        'flujo·persistencia 60s': tape.flowPersistence,
        // Same readings over other horizons: a one-minute window is an
        // arbitrary choice and nobody has checked whether it is the right one.
        'flujo·desequilibrio 30s': tape30.aggressorImbalance,
        'flujo·desequilibrio 120s': tape120.aggressorImbalance,
        'flujo·desequilibrio 300s': tape300.aggressorImbalance,
        'flujo·impulso 30s': tape30.priceImpulseBps / 20,
        'flujo·impulso 120s': tape120.priceImpulseBps / 20,
        'flujo·persistencia 120s': tape120.flowPersistence,
        // Is the pressure building or fading? The level says where the tape
        // leans, the slope says whether it is winning.
        'flujo·pendiente 30-120s':
            (tape30.aggressorImbalance - tape120.aggressorImbalance)
                .clamp(-1.0, 1.0)
                .toDouble(),
        'flujo·órdenes grandes 120s': tape120.largeTradeBias,
        // Controls: the candles were null against the old anchor. Against a
        // better one they should be even more null.
        'vela·momentum': signal.momentumScore / 100,
        'vela·tendencia': signal.trendScore / 100,
        'vela·inestabilidad': signal.instabilityScore / 100,
      },
    ));
  }

  if (rows.length < 800) {
    stdout.writeln('Muestra insuficiente: ${rows.length} rondas.');
    exit(1);
  }

  stdout.writeln('\nDecisión a los ${decideAt}s · ${rows.length} rondas');
  final best = anchorReport(rows);
  informationReport(rows, best);
}

/// Average absolute one-minute return per UTC hour, normalised so the mean
/// hour is 1.0. Only candles closing before [until] are used.
List<double> hourlyShape(List<Candle> candles, DateTime until) {
  final sums = List<double>.filled(24, 0);
  final counts = List<int>.filled(24, 0);
  for (var i = 1; i < candles.length; i++) {
    final at = candles[i].openTime.toUtc();
    if (!at.isBefore(until)) break;
    final previous = candles[i - 1].close;
    final current = candles[i].close;
    if (previous <= 0 || current <= 0) continue;
    final r = math.log(current / previous).abs();
    if (!r.isFinite) continue;
    sums[at.hour] += r;
    counts[at.hour]++;
  }

  final means = <double>[
    for (var h = 0; h < 24; h++) counts[h] == 0 ? 0.0 : sums[h] / counts[h],
  ];
  final observed = means.where((m) => m > 0).toList();
  if (observed.length < 20) return List<double>.filled(24, 1);
  final average = observed.reduce((a, b) => a + b) / observed.length;
  return [
    for (final m in means) m <= 0 ? 1.0 : (m / average).clamp(.55, 1.8).toDouble(),
  ];
}

/// Which σ makes the anchor honest.
String anchorReport(List<Row> rows) {
  final n = rows.length;
  final y = [for (final r in rows) r.outcome];
  final names = rows.first.anchors.keys.toList();
  final split = (n * .7).round();

  stdout.writeln('\n${'=' * 78}');
  stdout.writeln('EL ANCLA · ¿qué σ hace que Φ(d/σ√τ) sea creíble?');
  stdout.writeln('=' * 78);
  stdout.writeln('Un coeficiente de 1,00 significa que la probabilidad del');
  stdout.writeln('ancla se puede tomar al pie de la letra. Por debajo, exagera;');
  stdout.writeln('por encima, se queda corta. La log-pérdida fuera de muestra');
  stdout.writeln('es la que decide: mide probabilidad, no sólo dirección.');
  stdout.writeln('');
  stdout.writeln('  ancla                    coef     ±      acierto  log-pérd.');
  stdout.writeln('  ${'-' * 62}');

  var bestName = names.first;
  var bestLoss = double.infinity;

  for (final name in names) {
    final x = [
      for (final r in rows) <double>[1, logit(r.anchors[name]!)],
    ];
    final fit = fitLogistic(x, y);

    // Out of sample, raw: no recalibration, because that is how it would ship
    // if the estimate were right.
    var hits = 0;
    var loss = 0.0;
    for (var i = split; i < n; i++) {
      final p = rows[i].anchors[name]!.clamp(1e-9, 1 - 1e-9);
      final outcome = rows[i].outcome;
      if ((p >= .5) == (outcome == 1.0)) hits++;
      loss -= outcome * math.log(p) + (1 - outcome) * math.log(1 - p);
    }
    final tail = n - split;
    final meanLoss = loss / tail;
    if (meanLoss < bestLoss) {
      bestLoss = meanLoss;
      bestName = name;
    }

    stdout.writeln('  ${name.padRight(24)}'
        '${fit.beta[1].toStringAsFixed(4).padLeft(8)}'
        '${fit.se[1].toStringAsFixed(4).padLeft(8)}'
        '${(hits / tail * 100).toStringAsFixed(2).padLeft(9)}%'
        '${meanLoss.toStringAsFixed(5).padLeft(11)}');
  }

  stdout.writeln('');
  stdout.writeln('Mejor ancla por log-pérdida: $bestName');
  return bestName;
}

/// What is left once the best anchor has spoken.
void informationReport(List<Row> rows, String anchorName) {
  final n = rows.length;
  final y = [for (final r in rows) r.outcome];
  final names = rows.first.features.keys.toList();
  final anchor = [for (final r in rows) logit(r.anchors[anchorName]!)];

  final standardised = <String, List<double>>{};
  for (final name in names) {
    final raw = [for (final r in rows) r.features[name] ?? 0];
    final mean = raw.reduce((a, b) => a + b) / n;
    var variance = 0.0;
    for (final v in raw) {
      variance += (v - mean) * (v - mean);
    }
    final sd = math.sqrt(math.max(variance / (n - 1), 1e-18));
    standardised[name] = [for (final v in raw) (v - mean) / sd];
  }

  final baseline = fitLogistic(
    [for (var i = 0; i < n; i++) <double>[1, anchor[i]]],
    y,
  );

  final threshold = .05 / names.length;
  stdout.writeln('\n${'=' * 78}');
  stdout.writeln('QUÉ QUEDA · información más allá de «$anchorName»');
  stdout.writeln('=' * 78);
  stdout.writeln('Umbral de Bonferroni con ${names.length} features: '
      'p < ${threshold.toStringAsFixed(4)}');
  stdout.writeln('');
  stdout.writeln('  feature                        coef      z        p');
  stdout.writeln('  ${'-' * 58}');

  final winners = <String>[];
  for (final name in names) {
    final column = standardised[name]!;
    final fit = fitLogistic(
      [for (var i = 0; i < n; i++) <double>[1, anchor[i], column[i]]],
      y,
    );
    final coefficient = fit.beta[2];
    final se = fit.se[2];
    final z = se <= 0 ? 0.0 : coefficient / se;
    final p = twoSidedP(z);
    if (p < threshold) winners.add(name);
    stdout.writeln('  ${name.padRight(30)}'
        '${coefficient.toStringAsFixed(4).padLeft(8)}'
        '${z.toStringAsFixed(2).padLeft(8)}'
        '${p.toStringAsFixed(4).padLeft(9)}'
        '${p < threshold ? '  ← señal' : ''}');
  }

  if (winners.isEmpty) {
    stdout.writeln('\nNada sobrevive al umbral: el ancla ya lo absorbe todo.');
    return;
  }

  // Passing the threshold one at a time is not the same as deserving a seat
  // together. The tape readings over 30, 60 and 120 seconds are three views of
  // one thing, and thrown into the same fit they trade signs and inflate each
  // other's errors. So two models get built and checked out of sample: the
  // three readings of the one-minute window, which is what ships today, and
  // everything that survived, which is what a naive reading of the table would
  // suggest.
  const parsimonious = <String>[
    'flujo·desequilibrio 60s',
    'flujo·impulso 60s',
    'flujo·persistencia 60s',
  ];
  productionReport(rows, anchorName, parsimonious, baseline, 'ventana de 60s');
  productionReport(rows, anchorName, winners, baseline, 'todo lo significativo');
}

/// The model as it would ship, checked on rounds the fit never saw.
void productionReport(
  List<Row> rows,
  String anchorName,
  List<String> winners,
  LogitFit baseline,
  String label,
) {
  final n = rows.length;
  final split = (n * .7).round();

  List<List<double>> design(Iterable<Row> subset, {required bool withFlow}) => [
        for (final r in subset)
          <double>[
            1,
            logit(r.anchors[anchorName]!),
            if (withFlow)
              for (final name in winners) r.features[name] ?? 0,
          ],
      ];

  final train = rows.sublist(0, split);
  final test = rows.sublist(split);
  final yTrain = [for (final r in train) r.outcome];

  final anchorOnly = fitLogistic(design(train, withFlow: false), yTrain);
  final full = fitLogistic(design(train, withFlow: true), yTrain);

  stdout.writeln('\n${'=' * 78}');
  stdout.writeln('MODELO DE PRODUCCIÓN · «$anchorName» + $label');
  stdout.writeln('=' * 78);
  stdout.writeln('Ajuste sobre $split rondas, validación sobre ${test.length}.');
  stdout.writeln('');
  stdout.writeln('  término                             coef        z');
  stdout.writeln('  ${'-' * 52}');
  final terms = <String>['constante', 'logit(ancla)', ...winners];
  for (var j = 0; j < terms.length; j++) {
    final z = full.se[j] <= 0 ? 0.0 : full.beta[j] / full.se[j];
    stdout.writeln('  ${terms[j].padRight(32)}'
        '${full.beta[j].toStringAsFixed(4).padLeft(10)}'
        '${z.toStringAsFixed(2).padLeft(9)}');
  }

  double predict(LogitFit fit, List<double> row) {
    var eta = 0.0;
    for (var j = 0; j < row.length; j++) {
      eta += fit.beta[j] * row[j];
    }
    return sigmoid(eta);
  }

  void score(String label, List<double> probabilities) {
    var hits = 0;
    var loss = 0.0;
    var brier = 0.0;
    for (var i = 0; i < test.length; i++) {
      final p = probabilities[i].clamp(1e-9, 1 - 1e-9);
      final outcome = test[i].outcome;
      if ((p >= .5) == (outcome == 1.0)) hits++;
      loss -= outcome * math.log(p) + (1 - outcome) * math.log(1 - p);
      brier += (p - outcome) * (p - outcome);
    }
    stdout.writeln('  ${label.padRight(24)}'
        '${(hits / test.length * 100).toStringAsFixed(2).padLeft(8)}%'
        '${(loss / test.length).toStringAsFixed(5).padLeft(11)}'
        '${(brier / test.length).toStringAsFixed(5).padLeft(10)}');
  }

  stdout.writeln('');
  stdout.writeln('Fuera de muestra:');
  stdout.writeln('  ${'modelo'.padRight(24)}${'acierto'.padLeft(9)}'
      '${'log-pérdida'.padLeft(11)}${'Brier'.padLeft(10)}');
  stdout.writeln('  ${'-' * 54}');
  score('ancla tal cual', [
    for (final r in test) r.anchors[anchorName]!,
  ]);
  score('ancla recalibrada', [
    for (final row in design(test, withFlow: false)) predict(anchorOnly, row),
  ]);
  score('ancla + flujo', [
    for (final row in design(test, withFlow: true)) predict(full, row),
  ]);

  // What the safety gate would deliver with this model: the number the app
  // actually shows.
  stdout.writeln('');
  stdout.writeln('Puerta de seguridad sobre el modelo completo:');
  stdout.writeln('  ${'margen'.padRight(10)}${'cobertura'.padLeft(11)}'
      '${'acierto'.padLeft(10)}');
  stdout.writeln('  ${'-' * 31}');
  final probabilities = [
    for (final row in design(test, withFlow: true)) predict(full, row),
  ];
  for (final margin in <double>[0, .02, .04, .06, .08, .10, .12, .15]) {
    var taken = 0;
    var hits = 0;
    for (var i = 0; i < test.length; i++) {
      final p = probabilities[i];
      if ((p - .5).abs() < margin) continue;
      taken++;
      if ((p >= .5) == (test[i].outcome == 1.0)) hits++;
    }
    if (taken == 0) continue;
    stdout.writeln('  ${'${(margin * 100).toStringAsFixed(0)}%'.padLeft(6).padRight(10)}'
        '${(taken / test.length * 100).toStringAsFixed(1).padLeft(10)}%'
        '${(hits / taken * 100).toStringAsFixed(2).padLeft(9)}%');
  }
  stdout.writeln('=' * 78);
  stdout.writeln('Base para comparar: log-verosimilitud del ancla actual '
      '${baseline.logLikelihood.toStringAsFixed(2)}');
}
