// Offline evaluation harness for the 5-minute prediction stack.
//
// Replays real Binance history round by round: at the one-minute mark of each
// 5-minute candle the full council runs on the data available *at that moment*,
// issues a call, and is then scored against the actual close. The population
// learns after every round, exactly as it does in the app, so the numbers are
// walk-forward rather than in-sample.
//
// Two honest limitations, stated up front:
//  * order book and aggTrade microstructure cannot be replayed from klines, so
//    those features are neutral here. The live app has strictly more input.
//  * there is no historical news feed, so the news desk abstains.
//
// Usage:
//   dart run tool/backtest.dart [--rounds 1500] [--no-archive] [--gate 0.06]

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/btc_5m_logistic_model.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_analyst_evolution.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_audit_board.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_chief_analyst.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_consensus_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_ensemble_100.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_feature_factory.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_math_council.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_news_desk.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_pattern_archive.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_probability_calibrator.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_statistical_engine.dart';

/// Market-data hosts, tried in order.
///
/// `data-api.binance.vision` is Binance's public market-data endpoint and is
/// not geo-restricted, which matters because the main API answers 451 to CI
/// runners in the United States.
const _hosts = <String>[
  'https://data-api.binance.vision',
  'https://api.binance.com',
];
const _cacheDir = '.backtest-cache';

Future<List<Candle>> loadKlines(
  String symbol,
  String interval,
  int wanted,
) async {
  final cache = File('$_cacheDir/${symbol}_${interval}_$wanted.json');
  if (cache.existsSync()) {
    final rows = jsonDecode(cache.readAsStringSync()) as List<dynamic>;
    return [for (final r in rows) Candle.fromBinance(r as List<dynamic>)];
  }

  final client = http.Client();
  final all = <List<dynamic>>[];
  int? endTime;
  var hostIndex = 0;
  try {
    while (all.length < wanted) {
      final limit = math.min(1000, wanted - all.length);
      final uri = Uri.parse('${_hosts[hostIndex]}/api/v3/klines')
          .replace(queryParameters: {
        'symbol': symbol,
        'interval': interval,
        'limit': '$limit',
        if (endTime != null) 'endTime': '$endTime',
      });
      final response =
          await client.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        // 451 means the host is geo-blocked for this runner: move to the next.
        if (hostIndex + 1 < _hosts.length) {
          stdout.writeln('\n  ${_hosts[hostIndex]} respondió '
              '${response.statusCode}; probando ${_hosts[hostIndex + 1]}');
          hostIndex++;
          continue;
        }
        throw Exception('Binance ${response.statusCode}: ${response.body}');
      }
      final rows = (jsonDecode(response.body) as List<dynamic>)
          .cast<List<dynamic>>();
      if (rows.isEmpty) break;
      all.insertAll(0, rows);
      endTime = (rows.first[0] as num).toInt() - 1;
      stdout.write('\r  $symbol $interval: ${all.length}/$wanted velas   ');
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  } finally {
    client.close();
  }
  stdout.writeln();

  Directory(_cacheDir).createSync(recursive: true);
  cache.writeAsStringSync(jsonEncode(all));
  return [for (final r in all) Candle.fromBinance(r)];
}

/// Index of the last candle whose openTime is strictly before [moment].
int lastIndexBefore(List<Candle> candles, DateTime moment) {
  var lo = 0;
  var hi = candles.length - 1;
  var answer = -1;
  final target = moment.millisecondsSinceEpoch;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (candles[mid].openTime.millisecondsSinceEpoch < target) {
      answer = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return answer;
}

class RoundResult {
  const RoundResult({
    required this.roundStart,
    required this.probabilityUp,
    required this.predictedUp,
    required this.actualUp,
    required this.movePct,
    required this.auditQuality,
    required this.stability,
    required this.dissent,
    required this.vetoed,
  });

  final DateTime roundStart;
  final double probabilityUp;
  final bool predictedUp;
  final bool actualUp;
  final double movePct;
  final double auditQuality;
  final double stability;
  final double dissent;
  final bool vetoed;

  bool get hit => predictedUp == actualUp;
  double get edge => (probabilityUp - .5).abs();
}

Future<void> main(List<String> args) async {
  var rounds = 1500;
  var useArchive = true;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--rounds' && i + 1 < args.length) {
      rounds = int.tryParse(args[i + 1]) ?? rounds;
    }
    if (args[i] == '--no-archive') useArchive = false;
  }

  stdout.writeln('Descargando historia de Binance…');
  // One 5-minute round needs ~120 one-minute candles of context.
  final oneMinute = await loadKlines('BTCUSDT', '1m', rounds * 5 + 200);
  final fiveMinute = await loadKlines('BTCUSDT', '5m', rounds + 300);
  final ethOneMinute = await loadKlines('ETHUSDT', '1m', rounds * 5 + 200);
  final hourly = useArchive ? await loadKlines('BTCUSDT', '1h', 1000) : <Candle>[];
  final fourHour = useArchive ? await loadKlines('BTCUSDT', '4h', 1000) : <Candle>[];
  final daily = useArchive ? await loadKlines('BTCUSDT', '1d', 1000) : <Candle>[];

  const engine = PulseEngine();
  const statisticalEngine = PulseStatisticalEngine();
  const calibrator = PulseProbabilityCalibrator();
  const logisticModel = Btc5mLogisticModel();
  const ensemble = PulseEnsemble100();
  const council = PulseMathCouncil();
  const archive = PulsePatternArchive();
  const fusion = PulseConsensusEngine();
  const board = PulseAuditBoard();
  const chief = PulseChiefAnalyst();
  const evolutionEngine = PulseEvolutionEngine();
  const features = PulseFeatureFactory();

  var evolution = PulseEvolutionState.bootstrap();
  final results = <RoundResult>[];
  final started = DateTime.now();

  // Skip the first candles so every round has full context behind it.
  final firstRound = math.max(300, fiveMinute.length - rounds);
  var patterns = PatternBriefing.empty();

  for (var i = firstRound; i < fiveMinute.length - 1; i++) {
    final round = fiveMinute[i];
    final roundStart = round.openTime.toUtc();
    final decisionMoment = roundStart.add(const Duration(minutes: 1));

    final minuteIndex = lastIndexBefore(oneMinute, decisionMoment);
    if (minuteIndex < 130) continue;
    final ethIndex = lastIndexBefore(ethOneMinute, decisionMoment);
    if (ethIndex < 90) continue;

    final candles = oneMinute.sublist(minuteIndex - 119, minuteIndex + 1);
    final ethCandles = ethOneMinute.sublist(ethIndex - 89, ethIndex + 1);
    final entry = round.open;
    const secondsRemaining = 240;

    // The historical archive is restudied hourly: analog structure does not
    // change materially from one five-minute bar to the next, and restudying
    // every round would dominate the run time without changing the verdicts.
    if (useArchive && (i - firstRound) % 12 == 0) {
      patterns = archive.study(PatternHistory(series: <String, List<Candle>>{
        '5m': fiveMinute.sublist(math.max(0, i - 900), i),
        '1h': _sliceBefore(hourly, roundStart, 900),
        '4h': _sliceBefore(fourHour, roundStart, 900),
        '1d': _sliceBefore(daily, roundStart, 900),
      }));
    }

    final frame = PulseMarketFrame(
      candles: candles,
      referenceCandles: ethCandles,
      // Microstructure cannot be reconstructed from klines: kept neutral.
      bidVolume: 0,
      askVolume: 0,
      spreadBps: 1,
      micropriceEdge: 0,
      nearImbalance: 0,
      queueImbalance: 0,
      aggressorImbalance: 0,
      signedVolume: 0,
      tradeAcceleration: 0,
      priceImpulseBps: 0,
      flowPersistence: 0,
      largeTradeBias: 0,
      roundStartPrice: entry,
      secondsRemaining: secondsRemaining,
    );

    final PulseSignal signal;
    try {
      signal = engine.analyze(
        candles: candles,
        bidVolume: 0,
        askVolume: 0,
        roundStartPrice: entry,
        secondsRemaining: secondsRemaining,
      );
    } catch (_) {
      continue;
    }

    final briefing = council.deliberate(
      features.withInstability(
        features.buildMathContext(frame),
        signal.instabilityScore,
      ),
    );

    final statistical = statisticalEngine.analyze(
      candles: candles,
      bidVolume: 0,
      askVolume: 0,
      roundStartPrice: entry,
      secondsRemaining: secondsRemaining,
    );

    final analystInput = features.buildAnalystInput(
      frame: frame,
      signal: signal,
      statistical: statistical,
    );

    final ensembleResult = ensemble.analyze(
      analystInput,
      briefing: briefing,
      news: NewsBriefing.empty(),
      patterns: patterns,
      evolution: evolution,
    );

    final calibrated = calibrator.calibrate(
      score: signal.score,
      instability: signal.instabilityScore,
      agreement: signal.agreementRatio,
      roundDistancePct: signal.roundDistancePct,
      expectedRemainingMovePct: signal.expectedRemainingMovePct,
      secondsRemaining: secondsRemaining,
    );

    final logistic = logisticModel.analyze(
      fiveMinute.sublist(math.max(0, i - 40), i),
    );

    final consensus = fusion.fuse(
      signal: signal,
      ensemble: ensembleResult,
      briefing: briefing,
      news: NewsBriefing.empty(),
      patterns: patterns,
      evolution: evolution,
      statistical: statistical,
      calibrated: calibrated,
      logistic: logistic,
    );

    final audit = board.audit(
      consensus: consensus,
      signal: signal,
      evolution: evolution,
      secondsRemaining: secondsRemaining,
      historyReady: patterns.isReady,
    );

    final verdict = chief.decide(
      samples: const <ChiefSample>[],
      consensus: consensus,
      audit: audit,
      signal: signal,
      entryPrice: entry,
      decidedAt: decisionMoment,
      secondsRemaining: secondsRemaining,
    );

    final actualUp = round.close > round.open;
    results.add(RoundResult(
      roundStart: roundStart,
      probabilityUp: verdict.probabilityUp,
      predictedUp: verdict.isUp,
      actualUp: actualUp,
      movePct: (round.close - round.open) / round.open * 100,
      auditQuality: audit.qualityScore,
      stability: verdict.stability,
      dissent: verdict.dissent,
      vetoed: audit.verdict == AuditVerdict.vetoed,
    ));

    // Predict first, then learn: this keeps every measurement out of sample.
    evolution = evolutionEngine.learn(
      evolution,
      wentUp: actualUp,
      votes: ensembleResult.votes,
      consensusProbabilityUp: verdict.probabilityUp,
    );

    if (results.length % 100 == 0) {
      final hits = results.where((r) => r.hit).length;
      stdout.write('\r  ${results.length} rondas · acierto '
          '${(hits / results.length * 100).toStringAsFixed(2)}%   ');
    }
  }
  stdout.writeln();

  report(results, DateTime.now().difference(started));
}

List<Candle> _sliceBefore(List<Candle> candles, DateTime moment, int max) {
  if (candles.isEmpty) return const <Candle>[];
  final index = lastIndexBefore(candles, moment);
  if (index < 0) return const <Candle>[];
  final start = math.max(0, index + 1 - max);
  return candles.sublist(start, index + 1);
}

void report(List<RoundResult> results, Duration elapsed) {
  if (results.isEmpty) {
    stdout.writeln('Sin rondas evaluadas.');
    return;
  }

  final n = results.length;
  final hits = results.where((r) => r.hit).length;
  final accuracy = hits / n;
  final actualUp = results.where((r) => r.actualUp).length;
  final baseRate = math.max(actualUp, n - actualUp) / n;
  final brier = results.fold<double>(
        0,
        (s, r) => s + math.pow(r.probabilityUp - (r.actualUp ? 1 : 0), 2),
      ) /
      n;

  // Two-sided binomial test against a fair coin, normal approximation.
  final z = (hits - n / 2) / math.sqrt(n / 4);

  stdout.writeln('\n${'=' * 62}');
  stdout.writeln('BACKTEST · predicción a 1 minuto sobre el cierre de 5 min');
  stdout.writeln('=' * 62);
  stdout.writeln('Rondas evaluadas .......... $n');
  stdout.writeln('Periodo ................... '
      '${results.first.roundStart.toIso8601String()} → '
      '${results.last.roundStart.toIso8601String()}');
  stdout.writeln('Tiempo de cómputo ......... ${elapsed.inSeconds}s');
  stdout.writeln('');
  stdout.writeln('Acierto ................... '
      '${(accuracy * 100).toStringAsFixed(2)}%');
  stdout.writeln('Tasa base (clase mayor) ... '
      '${(baseRate * 100).toStringAsFixed(2)}%');
  stdout.writeln('Brier ..................... ${brier.toStringAsFixed(5)} '
      '(0.25 = moneda)');
  stdout.writeln('z contra moneda ........... ${z.toStringAsFixed(2)} '
      '${z.abs() > 1.96 ? '(significativo)' : '(NO significativo)'}');

  stdout.writeln('\nAcierto por umbral de convicción (puerta de seguridad):');
  stdout.writeln('  umbral   rondas   cobertura   acierto   z');
  for (final gate in <double>[0, .02, .04, .06, .08, .10, .12, .15, .20]) {
    final subset = results.where((r) => r.edge >= gate).toList();
    if (subset.length < 20) continue;
    final subsetHits = subset.where((r) => r.hit).length;
    final subsetAccuracy = subsetHits / subset.length;
    final subsetZ =
        (subsetHits - subset.length / 2) / math.sqrt(subset.length / 4);
    stdout.writeln('  ${(gate * 100).toStringAsFixed(0).padLeft(4)}%   '
        '${subset.length.toString().padLeft(6)}   '
        '${(subset.length / n * 100).toStringAsFixed(1).padLeft(8)}%   '
        '${(subsetAccuracy * 100).toStringAsFixed(2).padLeft(6)}%   '
        '${subsetZ.toStringAsFixed(2).padLeft(5)}');
  }

  stdout.writeln('\nAcierto por calidad de auditoría:');
  for (final gate in <double>[0, .5, .6, .7, .8]) {
    final subset = results.where((r) => r.auditQuality >= gate).toList();
    if (subset.length < 20) continue;
    final subsetHits = subset.where((r) => r.hit).length;
    stdout.writeln('  calidad ≥ ${(gate * 100).toStringAsFixed(0).padLeft(3)}%   '
        '${subset.length.toString().padLeft(6)} rondas   '
        '${(subsetHits / subset.length * 100).toStringAsFixed(2)}%');
  }

  stdout.writeln('\nCalibración (probabilidad declarada vs. realidad):');
  for (var bucket = 0; bucket < 10; bucket++) {
    final lo = bucket / 10;
    final hi = (bucket + 1) / 10;
    final subset = results
        .where((r) => r.probabilityUp >= lo && r.probabilityUp < hi)
        .toList();
    if (subset.isEmpty) continue;
    final realized = subset.where((r) => r.actualUp).length / subset.length;
    stdout.writeln('  ${(lo * 100).toStringAsFixed(0).padLeft(3)}–'
        '${(hi * 100).toStringAsFixed(0).padLeft(3)}%  '
        '${subset.length.toString().padLeft(6)} rondas  →  '
        'subió el ${(realized * 100).toStringAsFixed(1)}%');
  }

  final vetoed = results.where((r) => r.vetoed).toList();
  if (vetoed.length >= 20) {
    final vetoedHits = vetoed.where((r) => r.hit).length;
    stdout.writeln('\nRondas vetadas por auditoría: ${vetoed.length} · '
        'acierto ${(vetoedHits / vetoed.length * 100).toStringAsFixed(2)}%');
  }
  stdout.writeln('=' * 62);
}
