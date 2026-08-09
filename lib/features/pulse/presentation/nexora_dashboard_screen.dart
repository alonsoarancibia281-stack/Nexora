import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../../market/domain/market_asset.dart';
import '../data/pulse_ai_service.dart';
import '../data/pulse_round_history_repository.dart';
import '../domain/btc_5m_logistic_model.dart';
import '../domain/market_knowledge_framework.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_decision_gate.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_probability_calibrator.dart';
import '../domain/pulse_round_tracker.dart';
import '../domain/pulse_signal.dart';
import '../domain/pulse_statistical_engine.dart';
import 'pulse_dashboard_widgets.dart';

class NexoraDashboardScreen extends StatefulWidget {
  const NexoraDashboardScreen({super.key});

  @override
  State<NexoraDashboardScreen> createState() => _NexoraDashboardScreenState();
}

class _NexoraDashboardScreenState extends State<NexoraDashboardScreen> {
  final _service = BinanceMarketService();
  final _engine = const PulseEngine();
  final _ai = const PulseAiService();
  final _calibrator = const PulseProbabilityCalibrator();
  final _statistical = const PulseStatisticalEngine();
  final _logistic5m = const Btc5mLogisticModel();
  final _ensemble100 = const PulseEnsemble100();
  final _knowledge = const MarketKnowledgeFramework();
  final _historyRepository = PulseRoundHistoryRepository();
  final _decisionGate = PulseDecisionGate();

  Timer? _clock;
  Timer? _refreshTimer;
  Timer? _syncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime? _roundStart;
  DateTime? _roundEnd;
  DateTime? _tickerLoadedAt;
  PulseSignal? _signal;
  PulseAiConsensus? _aiPrediction;
  PulseProbabilityResult? _mathPrediction;
  PulseStatisticalResult? _statPrediction;
  Btc5mLogisticResult? _logisticPrediction;
  PulseEnsemble100Result? _ensemblePrediction;
  LockedPulseDecision? _lockedDecision;
  OrderBookSnapshot? _book;
  AggTradeSnapshot? _trades;
  MarketAsset? _ticker;
  List<Candle> _candles5m = const [];
  List<PulseRoundObservation> _roundObservations = [];
  List<PulseRoundOutcome> _outcomes = [];
  List<ProbabilitySample> _probabilityTrail = [];
  bool _loading = true;
  bool _loadInFlight = false;
  bool _roundTransitionInFlight = false;
  String? _error;
  double? _startPrice;
  double _currentPrice = 0;
  double _rawProbabilityUp = .5;
  double _ethConfirmation = 0;

  DateTime get _binanceNow => DateTime.now().toUtc().add(_binanceOffset);

  PulseCalibrationMetrics get _metrics =>
      PulseCalibrationMetrics.fromOutcomes(_outcomes);

  bool get _historicalAuditPassed {
    final metrics = _metrics;
    return metrics.samples < 30 ||
        (metrics.accuracy > .5 && metrics.brierScore < .25);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final outcomes = await _historyRepository.load();
    if (mounted) setState(() => _outcomes = outcomes);
    await _syncBinanceClock();
    await _startCurrentRound();

    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final end = _roundEnd;
      if (end != null && !_binanceNow.isBefore(end)) {
        unawaited(_startCurrentRound());
      } else {
        setState(() {});
      }
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_load(silent: true)),
    );
    _syncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_syncBinanceClock()),
    );
  }

  Future<void> _syncBinanceClock() async {
    try {
      final before = DateTime.now().toUtc();
      final serverTime = await _service.loadServerTime();
      final after = DateTime.now().toUtc();
      final midpoint = before.add(
        Duration(microseconds: after.difference(before).inMicroseconds ~/ 2),
      );
      final measuredOffset = serverTime.difference(midpoint);
      final deltaMs = (measuredOffset - _binanceOffset).inMilliseconds.abs();
      _binanceOffset = deltaMs > 1500 || _binanceOffset == Duration.zero
          ? measuredOffset
          : Duration(
              microseconds: ((_binanceOffset.inMicroseconds * .65) +
                      (measuredOffset.inMicroseconds * .35))
                  .round(),
            );
      if (mounted) setState(() {});
    } catch (_) {
      // Keep the last valid exchange clock offset.
    }
  }

  Future<void> _startCurrentRound() async {
    if (_roundTransitionInFlight) return;
    _roundTransitionInFlight = true;
    try {
      await _syncBinanceClock();
      final now = _binanceNow;
      final minuteBucket = (now.minute ~/ 5) * 5;
      final nextStart = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        minuteBucket,
      );
      final previousStart = _roundStart;
      if (previousStart != null && previousStart != nextStart) {
        await _finalizeRound(previousStart);
      }
      if (previousStart == nextStart) return;

      _roundStart = nextStart;
      _roundEnd = nextStart.add(const Duration(minutes: 5));
      _startPrice = null;
      _aiPrediction = null;
      _mathPrediction = null;
      _statPrediction = null;
      _logisticPrediction = null;
      _ensemblePrediction = null;
      _lockedDecision = null;
      _roundObservations = [];
      _probabilityTrail = [];
      _decisionGate.reset();
      if (mounted) setState(() {});
      await _load();
    } finally {
      _roundTransitionInFlight = false;
    }
  }

  Future<void> _finalizeRound(DateTime roundStart) async {
    final startPrice = _startPrice;
    if (startPrice == null || startPrice <= 0) return;
    var endPrice = _currentPrice;
    try {
      final candles = await _service.loadCandles('BTCUSDT', '5m', limit: 5);
      for (final candle in candles) {
        if (candle.openTime.toUtc().millisecondsSinceEpoch ==
            roundStart.millisecondsSinceEpoch) {
          endPrice = candle.close;
          break;
        }
      }
    } catch (_) {
      // The last observed real price remains a valid conservative fallback.
    }
    if (endPrice <= 0) return;
    final outcome = PulseRoundOutcome(
      roundStart: roundStart,
      startPrice: startPrice,
      endPrice: endPrice,
      observations: List.unmodifiable(_roundObservations),
    );
    final outcomes = await _historyRepository.add(outcome);
    if (mounted) setState(() => _outcomes = outcomes);
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tickerIsStale = _tickerLoadedAt == null ||
          DateTime.now().difference(_tickerLoadedAt!) >
              const Duration(seconds: 30);
      final results = await Future.wait<Object?>([
        _service.loadCandles('BTCUSDT', '1m', limit: 90),
        _service.loadCandles('BTCUSDT', '5m', limit: 60),
        _service.loadCandles('ETHUSDT', '1m', limit: 30),
        _service.loadOrderBookSnapshot('BTCUSDT', limit: 100),
        _service.loadAggTradeSnapshot('BTCUSDT', limit: 500),
        tickerIsStale
            ? _service.loadTicker24h('BTCUSDT')
            : Future<MarketAsset?>.value(_ticker),
      ]);
      final candles1m = results[0] as List<Candle>;
      final candles5m = results[1] as List<Candle>;
      final ethCandles = results[2] as List<Candle>;
      final book = results[3] as OrderBookSnapshot;
      final trades = results[4] as AggTradeSnapshot;
      final ticker = results[5] as MarketAsset?;
      final currentPrice = candles1m.last.close;

      double? startPrice = _startPrice;
      final start = _roundStart;
      if (start != null) {
        for (final candle in candles1m.reversed) {
          if (candle.openTime.toUtc().millisecondsSinceEpoch ==
              start.millisecondsSinceEpoch) {
            startPrice = candle.open;
            break;
          }
        }
      }
      final secondsRemaining = _remainingSeconds;
      final signal = _engine.analyze(
        candles: candles1m,
        bidVolume: book.bidVolume,
        askVolume: book.askVolume,
        roundStartPrice: startPrice,
        secondsRemaining: secondsRemaining,
      );

      PulseProbabilityResult? mathPrediction;
      PulseStatisticalResult? statPrediction;
      PulseEnsemble100Result? ensemblePrediction;
      var ethConfirmation = 0.0;
      if (startPrice != null) {
        mathPrediction = _calibrator.calibrate(
          score: signal.score,
          instability: signal.instabilityScore,
          agreement: signal.agreementRatio,
          roundDistancePct: signal.roundDistancePct,
          expectedRemainingMovePct: signal.expectedRemainingMovePct,
          secondsRemaining: secondsRemaining,
        );
        statPrediction = _statistical.analyze(
          candles: candles1m,
          bidVolume: book.bidVolume,
          askVolume: book.askVolume,
          roundStartPrice: startPrice,
          secondsRemaining: secondsRemaining,
        );
        final analystInput = _buildAnalystInput(
          candles: candles1m,
          ethCandles: ethCandles,
          signal: signal,
          stat: statPrediction,
          startPrice: startPrice,
          secondsRemaining: secondsRemaining,
          book: book,
          trades: trades,
        );
        ethConfirmation = analystInput.get('ethConfirmation');
        ensemblePrediction = _ensemble100.analyze(analystInput);
      }

      final completed5m = start == null
          ? <Candle>[]
          : candles5m
              .where((candle) => candle.openTime.toUtc().isBefore(start))
              .toList(growable: false);
      final logisticPrediction = _logistic5m.analyze(completed5m);

      var aiPrediction = _aiPrediction;
      if (startPrice != null && aiPrediction == null && _ai.isConfigured) {
        aiPrediction = await _ai.evaluate(
          symbol: 'BTCUSDT',
          startPrice: startPrice,
          currentPrice: currentPrice,
          secondsRemaining: secondsRemaining,
          quantitative: signal,
        );
      }
      final rawProbability = _fuseProbability(
        signal: signal,
        calibrated: mathPrediction,
        statistical: statPrediction,
        logistic: logisticPrediction,
        ensemble: ensemblePrediction,
        ai: aiPrediction,
      );
      final votes = _directionalVotes(
        rawProbability,
        mathPrediction,
        statPrediction,
        logisticPrediction,
        ensemblePrediction,
        aiPrediction,
      );
      final decision = ensemblePrediction == null || statPrediction == null
          ? null
          : _decisionGate.consider(
              candidate: PulseDecisionCandidate(
                probabilityUp: rawProbability,
                analystAgreement: ensemblePrediction.agreement,
                statisticalQuality: statPrediction.signalQuality,
                instability: signal.instabilityScore,
                directionalVotes: votes,
              ),
              elapsedSeconds: 300 - secondsRemaining,
              observedAt: _binanceNow,
              historicalAuditPassed: _historicalAuditPassed,
            );

      final trail = [..._probabilityTrail];
      if (trail.isEmpty ||
          _binanceNow.difference(trail.last.at) >= const Duration(seconds: 2)) {
        trail.add(
          ProbabilitySample(at: _binanceNow, probabilityUp: rawProbability),
        );
        if (trail.length > 100) trail.removeAt(0);
      }
      final observations = [..._roundObservations];
      if (decision != null &&
          startPrice != null &&
          (observations.isEmpty ||
              _binanceNow.difference(observations.last.observedAt) >=
                  const Duration(seconds: 2))) {
        observations.add(
          PulseRoundObservation(
            roundStart: start!,
            observedAt: _binanceNow,
            secondsRemaining: secondsRemaining,
            startPrice: startPrice,
            observedPrice: currentPrice,
            predictedDirection: decision.direction,
            probabilityUp: decision.probabilityUp,
            instability: signal.instabilityScore,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _candles5m = candles5m;
        _book = book;
        _trades = trades;
        _ticker = ticker;
        if (tickerIsStale && ticker != null) _tickerLoadedAt = DateTime.now();
        _currentPrice = currentPrice;
        _startPrice = startPrice;
        _signal = signal;
        _mathPrediction = mathPrediction;
        _statPrediction = statPrediction;
        _logisticPrediction = logisticPrediction;
        _ensemblePrediction = ensemblePrediction;
        _aiPrediction = aiPrediction;
        _lockedDecision = decision;
        _rawProbabilityUp = rawProbability;
        _ethConfirmation = ethConfirmation;
        _probabilityTrail = trail;
        _roundObservations = observations;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No se pudieron actualizar los datos reales. Se conservó la última lectura válida.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  AnalystInput _buildAnalystInput({
    required List<Candle> candles,
    required List<Candle> ethCandles,
    required PulseSignal signal,
    required PulseStatisticalResult stat,
    required double startPrice,
    required int secondsRemaining,
    required OrderBookSnapshot book,
    required AggTradeSnapshot trades,
  }) {
    double norm(double value, double scale) =>
        scale == 0 ? 0 : (value / scale).clamp(-1.0, 1.0).toDouble();
    final closes =
        candles.map((candle) => candle.close).toList(growable: false);
    final current = closes.last;
    final shortReturn = closes.length < 4
        ? 0.0
        : (current - closes[closes.length - 4]) /
            closes[closes.length - 4] *
            100;
    final previousReturn = closes.length < 7
        ? 0.0
        : (closes[closes.length - 4] - closes[closes.length - 7]) /
            closes[closes.length - 7] *
            100;
    final recent = candles.sublist(math.max(0, candles.length - 20));
    final mean = recent.map((candle) => candle.close).reduce((a, b) => a + b) /
        recent.length;
    final variance = recent
            .map((candle) => math.pow(candle.close - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        recent.length;
    final sigma = math.sqrt(variance);
    final zPrice =
        sigma <= 0 ? 0.0 : ((current - mean) / sigma).clamp(-3.0, 3.0) / 3.0;
    final depthTotal = book.bidVolume + book.askVolume;
    final bookImbalance =
        depthTotal <= 0 ? 0.0 : (book.bidVolume - book.askVolume) / depthTotal;
    final roundEdge = (current - startPrice) / startPrice * 100;
    final recentRanges = recent
        .map((candle) => candle.high - candle.low)
        .toList(growable: false);
    final averageRange =
        recentRanges.reduce((a, b) => a + b) / recentRanges.length;
    final lastRange = candles.last.high - candles.last.low;
    final rangeExpansion = averageRange <= 0
        ? 0.0
        : ((lastRange / averageRange) - 1).clamp(-1.0, 1.0).toDouble();
    final ethCloses =
        ethCandles.map((candle) => candle.close).toList(growable: false);
    final ethReturn = ethCloses.length < 4
        ? 0.0
        : (ethCloses.last - ethCloses[ethCloses.length - 4]) /
            ethCloses[ethCloses.length - 4] *
            100;

    return AnalystInput(
      instability: signal.instabilityScore,
      secondsRemaining: secondsRemaining,
      features: {
        'momentum': signal.momentumScore / 100,
        'acceleration': norm(shortReturn - previousReturn, .18),
        'shortReturn': norm(shortReturn, .30),
        'trend': signal.trendScore / 100,
        'emaSpread': signal.trendScore / 100,
        'slope': norm(stat.driftPerMinute * 100, .05),
        'volatilityBreakout': norm(trades.priceImpulseBps, 8),
        'atrExpansion': rangeExpansion,
        'rangeExpansion': rangeExpansion,
        'zPrice': zPrice,
        'rsiExtreme': 0,
        'vwapDistance': norm(roundEdge, .35),
        'bookImbalance': bookImbalance.clamp(-1.0, 1.0).toDouble(),
        'micropriceEdge': norm(book.micropriceEdge, 2),
        'spreadPressure': -norm(book.spreadBps, 3),
        'aggressorImbalance': trades.aggressorImbalance,
        'tradeAcceleration':
            trades.tradeAcceleration * trades.aggressorImbalance.sign,
        'signedVolume': trades.signedVolume,
        'volumeZ': norm(signal.volumeRatio - 1, 1.5),
        'obvSlope': trades.signedVolume,
        'volumePriceAgreement': trades.signedVolume * signal.momentumScore.sign,
        'bodyPressure': signal.bodyPressure / 100,
        'breakoutQuality': norm(trades.priceImpulseBps, 10),
        'wickBias': signal.bodyPressure / 100,
        'ethConfirmation': norm(ethReturn, .25),
        'exchangeConsensus': 0,
        'betaResidual': norm(shortReturn - ethReturn, .25),
        'regimeTrend': signal.trendScore / 100,
        'regimePersistence': stat.autocorrelation.clamp(-1.0, 1.0).toDouble(),
        'roundEdge': norm(
          roundEdge,
          math.max(signal.expectedRemainingMovePct, .05),
        ),
        'rawVolatility': stat.ewmaVolatilityPerMinute,
      },
    );
  }

  double _fuseProbability({
    required PulseSignal signal,
    required PulseProbabilityResult? calibrated,
    required PulseStatisticalResult? statistical,
    required Btc5mLogisticResult logistic,
    required PulseEnsemble100Result? ensemble,
    required PulseAiConsensus? ai,
  }) {
    if (calibrated == null && statistical == null && ensemble == null) {
      return .5;
    }
    final statQuality = statistical?.signalQuality ?? 0;
    final ensembleWeight =
        ensemble == null ? 0.0 : .42 + ensemble.agreement * .18;
    final statisticalWeight =
        statistical == null ? 0.0 : .32 + statQuality * .12;
    final calibratedWeight = calibrated == null ? 0.0 : .18;
    final logisticEvidence = logistic.isReady
        ? ((logistic.probabilityUp - .5).abs() * 2).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final logisticWeight =
        logistic.isReady ? .05 + logisticEvidence * .03 : 0.0;
    var aiWeight = 0.0;
    var aiProbability = .5;
    if (ai != null && ai.direction != PulseDirection.noTrade) {
      aiWeight = (.05 * (1 - signal.instabilityScore / 120))
          .clamp(.01, .05)
          .toDouble();
      aiProbability = ai.direction == PulseDirection.up
          ? ai.confidence / 100
          : 1 - ai.confidence / 100;
    }
    final total = ensembleWeight +
        statisticalWeight +
        calibratedWeight +
        logisticWeight +
        aiWeight;
    if (total <= 0) return .5;
    var probability = ((ensemble?.probabilityUp ?? .5) * ensembleWeight +
            (statistical?.probabilityUp ?? .5) * statisticalWeight +
            (calibrated?.probabilityUp ?? .5) * calibratedWeight +
            logistic.probabilityUp * logisticWeight +
            aiProbability * aiWeight) /
        total;
    final stabilityShrink =
        (1 - signal.instabilityScore / 165).clamp(.40, 1.0).toDouble();
    probability = .5 + (probability - .5) * stabilityShrink;
    final metrics = _metrics;
    final observedAdvantage = metrics.samples < 30
        ? .5
        : (.5 + (metrics.accuracy - .5) * 5).clamp(0.0, 1.0).toDouble();
    final knowledgeMultiplier = _knowledge.confidenceMultiplier(
      instability: signal.instabilityScore / 100,
      analystAgreement: ensemble?.agreement ?? 0,
      statisticalEdge: calibrated?.statisticalEdge ?? 0,
      baselineAdvantage: observedAdvantage,
      robustness: statistical?.signalQuality ?? 0,
    );
    probability = .5 + (probability - .5) * math.sqrt(knowledgeMultiplier);
    return probability.clamp(.08, .92).toDouble();
  }

  int _directionalVotes(
    double fused,
    PulseProbabilityResult? calibrated,
    PulseStatisticalResult? statistical,
    Btc5mLogisticResult logistic,
    PulseEnsemble100Result? ensemble,
    PulseAiConsensus? ai,
  ) {
    final components = <double>[
      if (calibrated != null) calibrated.probabilityUp,
      if (statistical != null) statistical.probabilityUp,
      if (ensemble != null) ensemble.probabilityUp,
      if (logistic.isReady) logistic.probabilityUp,
      if (ai != null && ai.direction != PulseDirection.noTrade)
        ai.direction == PulseDirection.up
            ? ai.confidence / 100
            : 1 - ai.confidence / 100,
    ];
    final fusedUp = fused >= .5;
    return components
        .where(
          (value) => (value - .5).abs() >= .015 && (value >= .5) == fusedUp,
        )
        .length;
  }

  Duration get _remaining {
    final end = _roundEnd;
    if (end == null) return Duration.zero;
    final duration = end.difference(_binanceNow);
    return duration.isNegative ? Duration.zero : duration;
  }

  int get _remainingSeconds {
    final milliseconds = _remaining.inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  String get _countdown {
    final seconds = _remainingSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  int get _roundNumber =>
      ((_roundStart?.millisecondsSinceEpoch ?? 0) ~/ 300000) % 100000;

  double get _calibrationProgress =>
      ((300 - _remainingSeconds) / _decisionGate.minimumCalibrationSeconds)
          .clamp(0.0, 1.0)
          .toDouble();

  BreakoutView get _breakout {
    final start = _roundStart;
    final completed = start == null
        ? <Candle>[]
        : _candles5m
            .where((candle) => candle.openTime.toUtc().isBefore(start))
            .toList(growable: false);
    final box = completed.length > 20
        ? completed.sublist(completed.length - 20)
        : completed;
    if (box.isEmpty) {
      return const BreakoutView(
        status: 'RECOPILANDO ESTRUCTURA',
        direction: PulseDirection.noTrade,
        boxHigh: 0,
        boxLow: 0,
        confirmations: ['✕ Historial 5m insuficiente'],
      );
    }
    final high = box.map((candle) => candle.high).reduce(math.max);
    final low = box.map((candle) => candle.low).reduce(math.min);
    final direction = _currentPrice > high
        ? PulseDirection.up
        : _currentPrice < low
            ? PulseDirection.down
            : PulseDirection.noTrade;
    final up = direction == PulseDirection.up;
    final down = direction == PulseDirection.down;
    final volumeConfirmed = (_signal?.volumeRatio ?? 0) >= 1.1;
    final flowConfirmed = up
        ? (_trades?.signedVolume ?? 0) > .05
        : down
            ? (_trades?.signedVolume ?? 0) < -.05
            : false;
    final micropriceConfirmed = up
        ? (_book?.micropriceEdge ?? 0) > 0
        : down
            ? (_book?.micropriceEdge ?? 0) < 0
            : false;
    final confirmations = <String>[
      '${direction == PulseDirection.noTrade ? '✕' : '✓'} Precio fuera de la caja',
      '${volumeConfirmed ? '✓' : '✕'} Volumen acompañando',
      '${flowConfirmed ? '✓' : '✕'} Flujo agresor alineado',
      '${micropriceConfirmed ? '✓' : '✕'} Microprecio alineado',
    ];
    final confirmed = direction != PulseDirection.noTrade &&
        [volumeConfirmed, flowConfirmed, micropriceConfirmed]
                .where((value) => value)
                .length >=
            2;
    return BreakoutView(
      status: confirmed
          ? 'RUPTURA ${up ? 'ALCISTA' : 'BAJISTA'} CONFIRMADA'
          : direction == PulseDirection.noTrade
              ? 'DENTRO DE LA CAJA'
              : 'RUPTURA SIN CONFIRMACIÓN',
      direction: confirmed ? direction : PulseDirection.noTrade,
      boxHigh: high,
      boxLow: low,
      confirmations: confirmations,
    );
  }

  List<KnowledgeEntry> get _knowledgeEntries {
    final breakout = _breakout;
    final metrics = _metrics;
    final stable = (_signal?.instabilityScore ?? 100) <= 72;
    final spreadOk = (_book?.spreadBps ?? 99) <= 2;
    final technical = (_signal?.agreementRatio ?? 0) >= .55;
    final ethAligned = _ethConfirmation.abs() >= .08;
    return [
      KnowledgeEntry(
        source: 'Graham',
        focus: 'margen de seguridad',
        status: _lockedDecision == null ? 'ESPERAR' : 'OK',
        positive: _lockedDecision != null,
      ),
      KnowledgeEntry(
        source: 'Greenblatt',
        focus: 'ranking multifactor',
        status:
            '${((_ensemblePrediction?.agreement ?? 0) * 100).toStringAsFixed(0)}%',
        positive: (_ensemblePrediction?.agreement ?? 0) >= .58,
      ),
      KnowledgeEntry(
        source: 'Malkiel / Taleb',
        focus: 'azar y robustez',
        status: metrics.samples < 30
            ? 'MUESTRA CORTA'
            : (_historicalAuditPassed ? 'SUPERA BASE' : 'VETO'),
        positive: _historicalAuditPassed,
      ),
      KnowledgeEntry(
        source: 'Livermore / Darvas',
        focus: 'confirmación',
        status: breakout.direction == PulseDirection.noTrade
            ? 'SIN RUPTURA'
            : 'CONFIRMADA',
        positive: breakout.direction != PulseDirection.noTrade,
      ),
      KnowledgeEntry(
        source: 'Murphy',
        focus: 'confluencia técnica',
        status: technical ? 'ALINEADA' : 'MIXTA',
        positive: technical,
      ),
      KnowledgeEntry(
        source: 'Shiller',
        focus: 'exuberancia',
        status: stable ? 'CONTROLADA' : 'ALTA',
        positive: stable,
      ),
      KnowledgeEntry(
        source: 'Bogle',
        focus: 'costos y spread',
        status: spreadOk ? 'ACEPTABLE' : 'ELEVADO',
        positive: spreadOk,
      ),
      KnowledgeEntry(
        source: 'Lynch',
        focus: 'contexto BTC/ETH',
        status: ethAligned ? 'ACTIVO' : 'NEUTRO',
        positive: ethAligned,
      ),
      KnowledgeEntry(
        source: 'Kahneman',
        focus: 'control de sesgos',
        status: stable ? 'BAJO' : 'MEDIO',
        positive: stable,
      ),
      KnowledgeEntry(
        source: 'Douglas / Elder',
        focus: 'disciplina',
        status: _lockedDecision == null ? 'SIN FORZAR' : 'BLOQUEADA',
        positive: true,
      ),
    ];
  }

  List<AuditEntry> get _biasEntries {
    final instability = _signal?.instabilityScore ?? 100;
    final agreement = _ensemblePrediction?.agreement ?? 0;
    final confidence = math.max(_rawProbabilityUp, 1 - _rawProbabilityUp) * 100;
    final anchorRisk = _signal == null || _signal!.expectedRemainingMovePct <= 0
        ? 2
        : (_signal!.roundDistancePct.abs() /
                    _signal!.expectedRemainingMovePct) >
                1.5
            ? 1
            : 0;
    return [
      AuditEntry(
        label: 'Recencia / ruido',
        status: instability > 72
            ? 'ALTO'
            : instability > 45
                ? 'MEDIO'
                : 'BAJO',
        level: instability > 72
            ? 2
            : instability > 45
                ? 1
                : 0,
      ),
      AuditEntry(
        label: 'Exceso de confianza',
        status: confidence > 70 && agreement < .6 ? 'MEDIO' : 'BAJO',
        level: confidence > 70 && agreement < .6 ? 1 : 0,
      ),
      AuditEntry(
        label: 'Anclaje al precio inicial',
        status: anchorRisk == 0
            ? 'BAJO'
            : anchorRisk == 1
                ? 'MEDIO'
                : 'ALTO',
        level: anchorRisk,
      ),
      AuditEntry(
        label: 'Confirmación selectiva',
        status: _directionalVotes(
                  _rawProbabilityUp,
                  _mathPrediction,
                  _statPrediction,
                  _logisticPrediction ??
                      const Btc5mLogisticResult(
                        probabilityUp: .5,
                        logit: 0,
                        isReady: false,
                      ),
                  _ensemblePrediction,
                  _aiPrediction,
                ) >=
                2
            ? 'BAJO'
            : 'MEDIO',
        level: _directionalVotes(
                  _rawProbabilityUp,
                  _mathPrediction,
                  _statPrediction,
                  _logisticPrediction ??
                      const Btc5mLogisticResult(
                        probabilityUp: .5,
                        logit: 0,
                        isReady: false,
                      ),
                  _ensemblePrediction,
                  _aiPrediction,
                ) >=
                2
            ? 0
            : 1,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF050A0F),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              const horizontalPadding = 10.0;
              final available = constraints.maxWidth - horizontalPadding * 2;
              final columns = available >= 1180
                  ? 3
                  : available >= 700
                      ? 2
                      : 1;
              final columnWidth = (available - gap * (columns - 1)) / columns;
              double widthFor(int desiredSpan) {
                final span = math.min(desiredSpan, columns);
                return columnWidth * span + gap * (span - 1);
              }

              final breakout = _breakout;
              return RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(horizontalPadding),
                  children: [
                    NexoraDashboardHeader(
                      price: _currentPrice,
                      change24h: _ticker?.changePercent24h ?? 0,
                      countdown: _countdown,
                      roundNumber: _roundNumber,
                      loading: _loading || _loadInFlight,
                      onBack: Navigator.of(context).canPop()
                          ? () => Navigator.of(context).pop()
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: nexoraRed.withValues(alpha: .09),
                          border: Border.all(
                            color: nexoraRed.withValues(alpha: .4),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: nexoraRed,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: gap),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: widthFor(1),
                          child: PredictionPanel(
                            decision: _lockedDecision,
                            calibrationProgress: _calibrationProgress,
                            agreement: _ensemblePrediction?.agreement ?? 0,
                            auditPassed: _historicalAuditPassed,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: AnalystDistributionPanel(
                            ensemble: _ensemblePrediction,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: KnowledgePanel(entries: _knowledgeEntries),
                        ),
                        SizedBox(
                          width: widthFor(columns >= 2 ? 2 : 1),
                          child: MarketChartPanel(
                            candles: _candles5m,
                            currentPrice: _currentPrice,
                            boxHigh: breakout.boxHigh,
                            boxLow: breakout.boxLow,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: MicrostructurePanel(
                            book: _book,
                            trades: _trades,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: QualityPanel(
                            metrics: _metrics,
                            statisticalQuality:
                                _statPrediction?.signalQuality ?? 0,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: AuditPanel(
                            title: 'Detector de sesgos · Kahneman',
                            entries: _biasEntries,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: BreakoutPanel(breakout: breakout),
                        ),
                        SizedBox(
                          width: widthFor(columns >= 2 ? 2 : 1),
                          child: ProbabilityEvolutionPanel(
                            samples: _probabilityTrail,
                          ),
                        ),
                        SizedBox(
                          width: widthFor(1),
                          child: AggregatePerformancePanel(metrics: _metrics),
                        ),
                        SizedBox(
                          width: widthFor(columns >= 2 ? 2 : 1),
                          child: RoundHistoryPanel(outcomes: _outcomes),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Nexora es un sistema experimental de análisis probabilístico. No garantiza resultados, no custodia fondos y no ejecuta operaciones.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: nexoraMuted, fontSize: 10),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
        ),
      );

  @override
  void dispose() {
    _clock?.cancel();
    _refreshTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
