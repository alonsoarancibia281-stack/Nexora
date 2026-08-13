import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../data/crypto_news_service.dart';
import '../data/pulse_ai_service.dart';
import '../data/pulse_evolution_store.dart';
import '../data/pulse_overlay.dart';
import '../domain/btc_5m_logistic_model.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_analyst_evolution.dart';
import '../domain/pulse_audit_board.dart';
import '../domain/pulse_chief_analyst.dart';
import '../domain/pulse_consensus_engine.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_feature_factory.dart';
import '../domain/pulse_flow_edge.dart';
import '../domain/pulse_math_council.dart';
import '../domain/pulse_news_desk.dart';
import '../domain/pulse_pattern_archive.dart';
import '../domain/pulse_probability_calibrator.dart';
import '../domain/pulse_round_plan.dart';
import '../domain/pulse_signal.dart';
import '../domain/pulse_statistical_engine.dart';
import '../domain/pulse_trade_guard.dart';
import 'widgets/liquid_neural_network.dart';
import 'widgets/liquid_widgets.dart';

/// Outcome of one settled round, kept for the on-screen history strip.
class _RoundOutcome {
  const _RoundOutcome({
    required this.roundStart,
    required this.predictedUp,
    required this.actualUp,
    required this.movePct,
    required this.probability,
  });

  final DateTime roundStart;
  final bool predictedUp;
  final bool actualUp;
  final double movePct;
  final double probability;

  bool get hit => predictedUp == actualUp;
}

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen> {
  // Data sources
  final _market = BinanceMarketService();
  final _newsService = CryptoNewsService();
  final _store = const PulseEvolutionStore();
  final _ai = const PulseAiService();
  final _overlay = const PulseOverlay();

  // Engines
  final _engine = const PulseEngine();
  final _calibrator = const PulseProbabilityCalibrator();
  final _statistical = const PulseStatisticalEngine();
  final _logistic5m = const Btc5mLogisticModel();
  final _ensemble = const PulseEnsemble100();
  final _council = const PulseMathCouncil();
  final _newsDesk = const PulseNewsDesk();
  final _archive = const PulsePatternArchive();
  final _fusion = const PulseConsensusEngine();
  final _auditBoard = const PulseAuditBoard();

  /// When the chief locks the call. Anticipation and accuracy trade off along
  /// a fixed curve, so this is a choice the user gets to make.
  PulseChiefAnalyst _chief = const PulseChiefAnalyst();
  final _evolutionEngine = const PulseEvolutionEngine();
  final _features = const PulseFeatureFactory();

  // Timers and streams
  Timer? _clock;
  Timer? _reviewTimer;
  Timer? _newsTimer;
  Timer? _historyTimer;
  Timer? _syncTimer;
  StreamSubscription<BinanceKlineTick>? _klineSubscription;

  // Exchange clock
  Duration _binanceOffset = Duration.zero;
  bool _liveFeed = false;

  // Round state
  DateTime? _roundStart;
  DateTime? _roundEnd;
  double? _entryPrice;
  double? _livePrice;
  final List<double> _roundPath = <double>[];

  /// The round is over and the screen is holding the result until the user
  /// asks for the next one. Without this the exchange stream would wipe the
  /// outcome the instant the candle closed.
  bool _holdingResult = false;

  /// Round the exchange already opened while the result was on hold.
  ({DateTime start, DateTime end, double open})? _pendingRound;

  // Councils
  PulseEvolutionState _evolution = PulseEvolutionState.bootstrap();
  PulseSignal? _signal;
  PulseConsensus? _consensus;
  AuditReport? _audit;
  double _flowActivation = 0;
  double _crossActivation = 0;
  MathBriefing _briefing = MathBriefing.neutral();
  NewsBriefing _news = NewsBriefing.empty();
  PatternBriefing _patterns = PatternBriefing.empty();
  int _historyCandles = 0;

  // Chief analyst
  final List<ChiefSample> _deliberation = <ChiefSample>[];
  ChiefVerdict? _verdict;
  PulseRoundPlan? _plan;
  PulseRoundTracking? _tracking;

  // Learning
  List<AnalystVote> _lastVotes = const <AnalystVote>[];

  /// Votes captured at the instant the chief locked the call. These — not the
  /// late-round opinions, which have already seen most of the move — are what
  /// the round outcome must be attributed to.
  List<AnalystVote> _decisionVotes = const <AnalystVote>[];
  List<AnalystVote>? _microVotes;
  double? _microPrice;
  double? _microProbability;
  DateTime? _microAt;
  final List<_RoundOutcome> _outcomes = <_RoundOutcome>[];

  // UI
  int _tab = 0;
  bool _loading = true;
  String? _error;
  bool _newsLoading = true;

  // Floating readout over other apps
  bool _overlayOn = false;

  /// Protection over a position the user opened by hand on the exchange.
  TradeGuard _guard = TradeGuard.off;

  /// The user asked for the overlay and was sent to system settings. Android
  /// cannot report back, so the next review cycle checks whether the permission
  /// arrived and starts the panel without a second tap.
  bool _overlayPending = false;

  DateTime get _binanceNow => DateTime.now().toUtc().add(_binanceOffset);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _evolution = await _store.load();
    // The panel outlives the app process, so it may already be up.
    _overlayOn = await _overlay.isRunning();
    if (mounted) setState(() {});

    await _syncClock();
    _alignRoundFromClock();
    _subscribeKline();

    unawaited(_refreshNews());
    unawaited(_refreshHistory());
    await _reviewMarket();

    _clock = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final end = _roundEnd;
      if (end != null &&
          !_binanceNow.isBefore(end) &&
          !_liveFeed &&
          !_holdingResult) {
        _rollRoundFromClock();
      } else {
        _reviewGuard();
        setState(() {});
      }
    });
    _reviewTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _reviewMarket(),
    );
    _newsTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshNews(),
    );
    _historyTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _refreshHistory(),
    );
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncClock(),
    );
  }

  // ===========================================================================
  // Exchange clock and round lifecycle
  // ===========================================================================

  Future<void> _syncClock() async {
    try {
      final before = DateTime.now().toUtc();
      final serverTime = await _market.loadServerTime();
      final after = DateTime.now().toUtc();
      final midpoint = before.add(
        Duration(microseconds: after.difference(before).inMicroseconds ~/ 2),
      );
      _applyOffset(serverTime.difference(midpoint));
    } catch (_) {
      // Keep the last valid synchronization.
    }
  }

  void _applyOffset(Duration measured) {
    final deltaMs = (measured - _binanceOffset).inMilliseconds.abs();
    if (deltaMs > 1500 || _binanceOffset == Duration.zero) {
      _binanceOffset = measured;
    } else {
      _binanceOffset = Duration(
        microseconds: ((_binanceOffset.inMicroseconds * .65) +
                (measured.inMicroseconds * .35))
            .round(),
      );
    }
  }

  /// Live 5-minute kline stream: exact exchange clock, exact round boundaries
  /// and the exact opening price of the running candle.
  void _subscribeKline() {
    _klineSubscription?.cancel();
    _klineSubscription =
        _market.liveKline('BTCUSDT', '5m').listen((tick) {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      _applyOffset(tick.eventTime.difference(now));
      _liveFeed = true;

      final currentStart = _roundStart;
      final isNewRound = currentStart == null ||
          tick.openTime.millisecondsSinceEpoch !=
              currentStart.millisecondsSinceEpoch;

      // While the result is held, the exchange keeps streaming the next
      // candle. Park it instead of letting it overwrite what the user is
      // still looking at.
      if (_holdingResult) {
        if (isNewRound) {
          _pendingRound =
              (start: tick.openTime, end: tick.roundEnd, open: tick.open);
        }
        setState(() {});
        return;
      }

      if (isNewRound) {
        _openRound(tick.openTime, tick.roundEnd, tick.open);
      }

      _entryPrice = tick.open;
      _livePrice = tick.close;
      _appendPath(tick.close);
      _roundEnd = tick.roundEnd;

      if (tick.isClosed) {
        _settleRound(tick.open, tick.close);
      } else {
        setState(() {});
      }
    }, onError: (_) {
      _liveFeed = false;
    }, cancelOnError: false);
  }

  void _alignRoundFromClock() {
    final now = _binanceNow;
    final bucket = (now.minute ~/ 5) * 5;
    final start =
        DateTime.utc(now.year, now.month, now.day, now.hour, bucket);
    _openRound(start, start.add(const Duration(minutes: 5)), null);
  }

  void _rollRoundFromClock() {
    final entry = _entryPrice;
    final close = _livePrice;
    if (entry != null && close != null) {
      _settleRound(entry, close);
    } else {
      _alignRoundFromClock();
      setState(() {});
    }
  }

  void _openRound(DateTime start, DateTime end, double? entry) {
    _roundStart = start;
    _roundEnd = end;
    _entryPrice = entry;
    _roundPath.clear();
    _deliberation.clear();
    _verdict = null;
    _plan = null;
    _tracking = null;
    _microVotes = null;
    _microPrice = null;
    _microAt = null;
    _decisionVotes = const <AnalystVote>[];
    // A new candle is a new thesis; whatever was being protected belonged to
    // the previous one.
    _guard = TradeGuard.off;
    if (entry != null) _appendPath(entry);
    // A new round means a new chart to process: refresh the analog archive so
    // the historical desk studies the window that just closed.
    unawaited(_refreshHistory());
    unawaited(_reviewMarket());
  }

  void _appendPath(double price) {
    if (!price.isFinite || price <= 0) return;
    if (_roundPath.isNotEmpty && (_roundPath.last - price).abs() < 1e-9) return;
    _roundPath.add(price);
    if (_roundPath.length > 400) _roundPath.removeAt(0);
  }

  /// Closes the round, scores the call and feeds the result back to everyone.
  Future<void> _settleRound(double entry, double close) async {
    final start = _roundStart;
    if (start == null || entry <= 0) return;
    final wentUp = close > entry;
    final verdict = _verdict;
    final consensus = _consensus;

    final scoredVotes =
        _decisionVotes.isNotEmpty ? _decisionVotes : _lastVotes;
    if (scoredVotes.isNotEmpty && consensus != null) {
      _evolution = _evolutionEngine.learn(
        _evolution,
        wentUp: wentUp,
        votes: scoredVotes,
        consensusProbabilityUp:
            verdict?.probabilityUp ?? consensus.probabilityUp,
      );
      unawaited(_store.save(_evolution));
    }

    if (verdict != null && consensus != null && _signal != null) {
      _outcomes.insert(
        0,
        _RoundOutcome(
          roundStart: start,
          predictedUp: verdict.isUp,
          actualUp: wentUp,
          movePct: (close - entry) / entry * 100,
          probability: verdict.confidence,
        ),
      );
      if (_outcomes.length > 24) _outcomes.removeLast();
      _tracking = PulseRoundTracking.evaluate(
        plan: _plan ??
            PulseRoundPlan.build(
              roundStart: start,
              roundEnd: _roundEnd ?? start.add(const Duration(minutes: 5)),
              entryPrice: entry,
              secondsRemaining: 0,
              consensus: consensus,
              signal: _signal!,
            ),
        currentPrice: close,
        secondsRemaining: 0,
        liveProbabilityUp: verdict.probabilityUp,
        closed: true,
      );
    }

    // An armed position has nothing left to ride: the candle it was betting on
    // is closed.
    if (_guard.isArmed) {
      _guard = _guard.evaluate(
        price: close,
        probabilityUp: verdict?.probabilityUp ?? .5,
        secondsRemaining: 0,
      );
    }

    // The round is scored; hold it on screen. Nothing advances until the user
    // asks for the next one.
    _holdingResult = true;
    _pendingRound = null;
    if (mounted) setState(() {});
    unawaited(_pushOverlay());
  }

  /// Leaves the closed round behind and starts the one the exchange is already
  /// running.
  void _advanceRound() {
    final pending = _pendingRound;
    _holdingResult = false;
    _pendingRound = null;
    if (pending != null) {
      _openRound(pending.start, pending.end, pending.open);
      _livePrice = pending.open;
    } else {
      _alignRoundFromClock();
    }
    setState(() {});
  }

  // ===========================================================================
  // Councils
  // ===========================================================================

  Future<void> _refreshNews() async {
    try {
      final items = await _newsService.loadBitcoinNews();
      final briefing = _newsDesk.analyze(items, now: _binanceNow);
      if (!mounted) return;
      setState(() {
        _news = briefing;
        _newsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  Future<void> _refreshHistory() async {
    try {
      final results = await Future.wait<List<Candle>>([
        _market.loadCandles('BTCUSDT', '5m', limit: 1000),
        _market.loadCandles('BTCUSDT', '1h', limit: 1000),
        _market.loadCandles('BTCUSDT', '4h', limit: 1000),
        _market.loadCandles('BTCUSDT', '1d', limit: 1000),
      ]);
      final history = PatternHistory(series: <String, List<Candle>>{
        '5m': results[0],
        '1h': results[1],
        '4h': results[2],
        '1d': results[3],
      });
      final briefing = _archive.study(history);
      if (!mounted) return;
      setState(() {
        _historyCandles = history.totalCandles;
        _patterns = briefing;
      });
    } catch (_) {
      // The archive keeps its previous study.
    }
  }

  Future<void> _reviewMarket() async {
    // The round on screen is already scored; there is nothing left to analyse
    // until the user moves on.
    if (_holdingResult) {
      await _pushOverlay();
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _market.loadCandles('BTCUSDT', '1m', limit: 120),
        _market.loadCandles('BTCUSDT', '5m', limit: 40),
        _market.loadCandles('ETHUSDT', '1m', limit: 90),
        _market.loadDepthMetrics('BTCUSDT', limit: 100),
        _market.loadAggTradeMetrics('BTCUSDT', limit: 500),
      ]);
      final candles = results[0] as List<Candle>;
      final fiveMinute = results[1] as List<Candle>;
      final ethCandles = results[2] as List<Candle>;
      final depth = results[3] as ({
        double bidVolume,
        double askVolume,
        double bestBid,
        double bestAsk,
        double spreadBps,
        double micropriceEdge,
        double nearImbalance,
        double queueImbalance,
      });
      final trades = results[4] as ({
        double aggressorImbalance,
        double signedVolume,
        double tradeAcceleration,
        double priceImpulseBps,
        double flowPersistence,
        double largeTradeBias,
        int trades,
      });

      final start = _roundStart;
      var entry = _entryPrice;
      if (entry == null && start != null) {
        for (final c in candles.reversed) {
          if (c.openTime.toUtc().millisecondsSinceEpoch ==
              start.millisecondsSinceEpoch) {
            entry = c.open;
            break;
          }
        }
      }

      final seconds = _remainingSeconds;
      final price = _livePrice ?? candles.last.close;
      _appendPath(price);

      final frame = PulseMarketFrame(
        candles: candles,
        referenceCandles: ethCandles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
        spreadBps: depth.spreadBps,
        micropriceEdge: depth.micropriceEdge,
        nearImbalance: depth.nearImbalance,
        queueImbalance: depth.queueImbalance,
        aggressorImbalance: trades.aggressorImbalance,
        signedVolume: trades.signedVolume,
        tradeAcceleration: trades.tradeAcceleration,
        priceImpulseBps: trades.priceImpulseBps,
        flowPersistence: trades.flowPersistence,
        largeTradeBias: trades.largeTradeBias,
        roundStartPrice: entry,
        secondsRemaining: seconds,
      );

      final signal = _engine.analyze(
        candles: candles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
        roundStartPrice: entry,
        secondsRemaining: seconds,
      );

      final mathContext = _features.withInstability(
        _features.buildMathContext(frame),
        signal.instabilityScore,
      );
      final briefing = _council.deliberate(mathContext);

      final statistical = entry == null
          ? null
          : _statistical.analyze(
              candles: candles,
              bidVolume: depth.bidVolume,
              askVolume: depth.askVolume,
              roundStartPrice: entry,
              secondsRemaining: seconds,
            );

      final analystInput = _features.buildAnalystInput(
        frame: frame,
        signal: signal,
        statistical: statistical ??
            const PulseStatisticalResult(
              probabilityUp: .5,
              confidence: 50,
              driftPerMinute: 0,
              ewmaVolatilityPerMinute: 0,
              autocorrelation: 0,
              signalQuality: 0,
            ),
      );

      final ensemble = _ensemble.analyze(
        analystInput,
        briefing: briefing,
        news: _news,
        patterns: _patterns,
        evolution: _evolution,
      );

      final calibrated = entry == null
          ? null
          : _calibrator.calibrate(
              score: signal.score,
              instability: signal.instabilityScore,
              agreement: signal.agreementRatio,
              roundDistancePct: signal.roundDistancePct,
              expectedRemainingMovePct: signal.expectedRemainingMovePct,
              secondsRemaining: seconds,
            );

      final completed5m = start == null
          ? const <Candle>[]
          : fiveMinute
              .where((c) => c.openTime.toUtc().isBefore(start))
              .toList(growable: false);
      final logistic = _logistic5m.analyze(completed5m);

      PulseAiConsensus? ai;
      if (entry != null) {
        ai = await _ai.evaluate(
          symbol: 'BTCUSDT',
          startPrice: entry,
          currentPrice: price,
          secondsRemaining: seconds,
          quantitative: signal,
        );
      }

      final consensus = _fusion.fuse(
        signal: signal,
        ensemble: ensemble,
        briefing: briefing,
        news: _news,
        patterns: _patterns,
        evolution: _evolution,
        // The tape is read twice: once by the trade-flow desk among the 100,
        // and once here with the weights measured against real outcomes.
        flow: PulseFlowEdge(
          aggressorImbalance: trades.aggressorImbalance,
          priceImpulseBps: trades.priceImpulseBps,
          flowPersistence: trades.flowPersistence,
          trades: trades.trades,
        ),
        statistical: statistical,
        calibrated: calibrated,
        logistic: logistic,
        ai: ai,
      );

      // Final test: 100 auditors interrogate the packet before the chief sees it.
      final audit = _auditBoard.audit(
        consensus: consensus,
        signal: signal,
        evolution: _evolution,
        secondsRemaining: seconds,
        newsAgeMinutes: _news.freshestMinutes,
        historyReady: _patterns.isReady,
      );

      _learnContinuously(price, ensemble.votes, audit.probabilityUp);

      // Chart processed at the open: the thesis is fixed on the first pass.
      if (_plan == null && entry != null && start != null) {
        _plan = PulseRoundPlan.build(
          roundStart: start,
          roundEnd: _roundEnd ?? start.add(const Duration(minutes: 5)),
          entryPrice: entry,
          secondsRemaining: seconds,
          consensus: consensus,
          signal: signal,
        );
      }

      // The chief analyst listens for the first minute, then locks the call.
      if (entry != null) {
        _deliberation.add(ChiefSample(
          takenAt: _binanceNow,
          secondsRemaining: seconds,
          probabilityUp: audit.probabilityUp,
          price: price,
          instability: signal.instabilityScore,
          ensembleProbability: ensemble.probabilityUp,
          mathProbability: briefing.probabilityUp,
          patternProbability: _patterns.probabilityUp,
          newsProbability: _news.probabilityUp,
        ));
        if (_deliberation.length > 40) _deliberation.removeAt(0);

        if (_verdict == null &&
            seconds <= _chief.lockAtSecondsRemaining) {
          _decisionVotes = ensemble.votes;
          _verdict = _chief.decide(
            samples: _deliberation,
            consensus: consensus,
            audit: audit,
            signal: signal,
            entryPrice: entry,
            decidedAt: _binanceNow,
            secondsRemaining: seconds,
          );
        }
      }

      final plan = _plan;
      final tracking = plan == null
          ? null
          : PulseRoundTracking.evaluate(
              plan: plan,
              currentPrice: price,
              secondsRemaining: seconds,
              liveProbabilityUp:
                  _verdict?.probabilityUp ?? audit.probabilityUp,
            );

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _briefing = briefing;
        _consensus = consensus;
        _audit = audit;
        _flowActivation = trades.aggressorImbalance;
        _crossActivation = analystInput.get('ethConfirmation');
        _lastVotes = ensemble.votes;
        _entryPrice = entry;
        _livePrice = price;
        _tracking = tracking;
        _loading = false;
        _error = null;
      });

      _reviewGuard();
      unawaited(_pushOverlay());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar la lectura del mercado.';
      });
    }
  }

  /// Continuous learning: every ~30 seconds the population is scored against
  /// the move that actually happened since the previous review.
  ///
  /// This is deliberately weak. The analysts are forecasting a 5-minute close,
  /// so a 30-second wiggle is only a proxy for their skill; at full strength
  /// the ten reviews inside a round would outweigh the one outcome that
  /// actually matters and the population would drift toward predicting the
  /// wrong horizon. Moves inside the noise floor are ignored outright.
  void _learnContinuously(
    double price,
    List<AnalystVote> votes,
    double consensusProbability,
  ) {
    final previousAt = _microAt;
    final previousPrice = _microPrice;
    final previousVotes = _microVotes;
    final previousProbability = _microProbability;
    final now = _binanceNow;

    // Noise floor: a third of the volatility the market itself expects over
    // thirty seconds. Below that the sign of the move carries no information.
    final expected = _signal?.expectedRemainingMovePct ?? .05;
    final floorPct = math.max(expected * .18, .004);

    if (previousAt != null &&
        previousPrice != null &&
        previousVotes != null &&
        previousProbability != null &&
        previousPrice > 0 &&
        now.difference(previousAt).inSeconds >= 30) {
      final movePct = (price - previousPrice) / previousPrice * 100;
      if (movePct.abs() >= floorPct) {
        _evolution = _evolutionEngine.learn(
          _evolution,
          wentUp: movePct > 0,
          votes: previousVotes,
          consensusProbabilityUp: previousProbability,
          intensity: .10,
          closedRound: false,
        );
      }
    }

    if (previousAt == null || now.difference(previousAt).inSeconds >= 30) {
      _microAt = now;
      _microPrice = price;
      _microVotes = votes;
      _microProbability = consensusProbability;
    }
  }

  // ===========================================================================
  // Floating readout over other apps
  // ===========================================================================

  /// The call as an order: what the user would do on the exchange.
  TradeAction get _action {
    final verdict = _verdict;
    if (verdict == null) return TradeAction.wait;
    return TradeGuard.actionFor(
      direction: verdict.isUp ? PulseDirection.up : PulseDirection.down,
      hasReading: verdict.hasReading,
    );
  }

  /// Re-reads the armed position against the market. Called on every review
  /// and on every clock tick, so the alarm does not wait for the next cycle.
  void _reviewGuard() {
    if (_guard.state == GuardState.off) return;
    final price = _livePrice;
    if (price == null) return;
    final next = _guard.evaluate(
      price: price,
      probabilityUp: _verdict?.probabilityUp ??
          _consensus?.probabilityUp ??
          .5,
      secondsRemaining: _remainingSeconds,
    );
    final tripped = next.isTriggered && !_guard.isTriggered;
    _guard = next;
    // The alarm cannot wait for the next three-second review: the user is
    // looking at the exchange, not at this screen.
    if (tripped) unawaited(_pushOverlay());
  }

  void _toggleGuard() {
    if (_guard.state != GuardState.off) {
      // Both clearing a watch and acknowledging an alarm land here: either way
      // the position is no longer Nexora's business.
      setState(() => _guard = TradeGuard.off);
      unawaited(_pushOverlay());
      return;
    }
    final plan = _plan;
    final price = _livePrice;
    if (plan == null || price == null) return;
    setState(() => _guard = TradeGuard.arm(plan: plan, price: price));
    unawaited(_pushOverlay());
  }

  /// What the panel should say right now.
  PulseOverlayReading _overlayReading() {
    final verdict = _verdict;
    final consensus = _consensus;
    final entry = _entryPrice;
    final price = _livePrice;
    final end = _roundEnd;

    if (_holdingResult) {
      final wentUp = entry != null && price != null && price > entry;
      return PulseOverlayReading(
        headline: wentUp ? 'SUBIÓ' : 'BAJÓ',
        detail: 'ronda cerrada · abre Nexora para la siguiente',
        probability: 0,
        up: wentUp,
        hasReading: false,
        roundEndsAt: DateTime.now(),
      );
    }

    final action = _action;
    final headline = verdict == null
        ? 'ANALIZANDO'
        : !verdict.hasReading
            ? 'ESPERAR'
            : (action == TradeAction.buy ? 'COMPRAR' : 'VENDER');
    final detail = price == null
        ? 'esperando precio'
        : entry == null
            ? 'BTC ${price.toStringAsFixed(2)}'
            : 'BTC ${price.toStringAsFixed(2)} · apertura '
                '${entry.toStringAsFixed(2)}';

    return PulseOverlayReading(
      headline: headline,
      detail: detail,
      probability:
          verdict?.confidence ?? ((consensus?.winningProbability ?? .5) * 100),
      up: verdict?.isUp ?? ((consensus?.probabilityUp ?? .5) >= .5),
      hasReading: verdict?.hasReading ?? false,
      // The panel counts down on its own, so it needs the deadline on the
      // device clock rather than the exchange's.
      roundEndsAt: (end ?? _binanceNow).subtract(_binanceOffset),
      guard: switch (_guard.state) {
        GuardState.off => OverlayGuard.off,
        GuardState.armed => OverlayGuard.armed,
        GuardState.triggered => OverlayGuard.triggered,
      },
      guardDetail: _guardDetail(),
      actionLabel: _guardButtonLabel(),
    );
  }

  String _guardDetail() => switch (_guard.state) {
        GuardState.off => '',
        GuardState.armed => 'protegida desde '
            '${_guard.entryPrice.toStringAsFixed(2)} · sale en '
            '${_guard.invalidationPrice.toStringAsFixed(2)}',
        GuardState.triggered => '${_guard.reasonLabel} · '
            '−${_guard.adversePct.toStringAsFixed(3)}%',
      };

  String _guardButtonLabel() {
    if (_holdingResult) return '';
    return switch (_guard.state) {
      GuardState.off => _plan == null ? '' : 'PROTEGER OPERACIÓN',
      GuardState.armed => 'QUITAR PROTECCIÓN',
      GuardState.triggered => 'HECHO, YA CERRÉ',
    };
  }

  Future<void> _pushOverlay() async {
    if (!_overlay.isSupported) return;

    if (_overlayPending && !_overlayOn) {
      // Back from the settings screen: start without asking for a second tap.
      if (await _overlay.hasPermission()) {
        final started = await _overlay.start(_overlayReading());
        if (!mounted) return;
        setState(() {
          _overlayOn = started;
          _overlayPending = !started;
        });
        return;
      }
    }

    if (!_overlayOn) return;
    final tapped = await _overlay.update(_overlayReading());
    if (tapped == 'toggle' && mounted) {
      _toggleGuard();
    }
  }

  Future<void> _toggleOverlay() async {
    if (_overlayOn) {
      await _overlay.stop();
      if (!mounted) return;
      setState(() {
        _overlayOn = false;
        _overlayPending = false;
      });
      return;
    }

    var granted = await _overlay.hasPermission();
    if (!granted) {
      // Opens the system screen; Android never grants this from inside the app.
      granted = await _overlay.requestPermission();
      if (!granted) {
        if (!mounted) return;
        setState(() => _overlayPending = true);
        return;
      }
    }

    final started = await _overlay.start(_overlayReading());
    if (!mounted) return;
    setState(() {
      _overlayOn = started;
      _overlayPending = !started;
    });
  }

  // ===========================================================================
  // Derived values
  // ===========================================================================

  Duration get _remaining {
    final end = _roundEnd;
    if (end == null) return Duration.zero;
    final value = end.difference(_binanceNow);
    return value.isNegative ? Duration.zero : value;
  }

  int get _remainingSeconds {
    final ms = _remaining.inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil().clamp(0, 300);
  }

  String get _countdown {
    final total = _remainingSeconds;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }

  double get _roundProgress =>
      ((300 - _remainingSeconds) / 300).clamp(0.0, 1.0).toDouble();

  /// Seconds left in the chief analyst's one-minute decision window.
  int get _decisionSecondsLeft {
    final elapsed = 300 - _remainingSeconds;
    final left = _chief.decisionWindowSeconds - elapsed;
    return left.clamp(0, _chief.decisionWindowSeconds);
  }

  bool get _deciding => _verdict == null;

  int get _totalAgents =>
      100 +
      PulseMathCouncil.mathematicians +
      PulseNewsDesk.analysts +
      PulsePatternArchive.analysts +
      PulseAuditBoard.auditors +
      1;

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    final consensus = _consensus;
    final up = verdict?.isUp ?? ((consensus?.probabilityUp ?? .5) >= .5);

    return Scaffold(
      backgroundColor: LiquidPalette.paper,
      body: LiquidBackground(
        intensity: _deciding ? .75 : 1,
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: LiquidTabs(
                  tabs: const [
                    'Predicción',
                    'Red neuronal',
                    'Consejos',
                    'Noticias',
                    'Evolución',
                  ],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: LiquidPalette.primary,
                  backgroundColor: LiquidPalette.surface,
                  onRefresh: () async {
                    await _syncClock();
                    await Future.wait([
                      _reviewMarket(),
                      _refreshNews(),
                      _refreshHistory(),
                    ]);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: switch (_tab) {
                      1 => _networkTab(),
                      2 => _councilsTab(),
                      3 => _newsTab(),
                      4 => _evolutionTab(),
                      _ => _predictionTab(up),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Predicciones BTC', style: LiquidType.display),
                  const SizedBox(height: 4),
                  Text(
                    'Rondas de 5 minutos · $_totalAgents agentes en consejo',
                    style: LiquidType.caption,
                  ),
                ],
              ),
            ),
            LiquidChip(
              label: _liveFeed ? 'BINANCE EN VIVO' : 'SINCRONIZANDO',
              icon: _liveFeed ? Icons.bolt : Icons.sync,
              color: _liveFeed ? LiquidPalette.rise : LiquidPalette.inkFaint,
              dense: true,
            ),
          ],
        ),
      );

  // --- Tab 1: prediction ----------------------------------------------------

  List<Widget> _predictionTab(bool up) {
    final consensus = _consensus;
    final verdict = _verdict;
    final plan = _plan;
    final tracking = _tracking;
    final signal = _signal;

    return [
      _countdownCard(),
      const SizedBox(height: 14),
      _verdictCard(up, verdict, consensus),
      const SizedBox(height: 14),
      if (!_holdingResult) ...[
        _guardCard(),
        const SizedBox(height: 14),
      ],
      if (_overlay.isSupported) ...[
        _overlayCard(),
        const SizedBox(height: 14),
      ],
      if (plan != null) ...[
        _strategyCard(plan, tracking),
        const SizedBox(height: 14),
      ],
      _liveChartCard(up, plan, tracking),
      const SizedBox(height: 14),
      if (signal != null) _marketStateCard(signal),
      if (_audit != null) ...[
        const SizedBox(height: 14),
        _auditCard(_audit!),
      ],
      if (_error != null) ...[
        const SizedBox(height: 14),
        LiquidAlert(
          message: _error!,
          tone: LiquidPalette.fall,
          icon: Icons.warning_amber_rounded,
        ),
      ],
      if (_outcomes.isNotEmpty) ...[
        const SizedBox(height: 14),
        _historyCard(),
      ],
      const SizedBox(height: 16),
      const LiquidAlert(
        message:
            'Modelo experimental de uso educativo. No ejecuta operaciones ni garantiza resultados.',
        tone: LiquidPalette.inkFaint,
      ),
    ];
  }

  Widget _countdownCard() {
    if (_holdingResult) return _roundClosedCard();
    final decisionPhase = _deciding && _remainingSeconds > 0;
    return LiquidCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TIEMPO DE RONDA', style: LiquidType.micro),
              LiquidChip(
                label: decisionPhase
                    ? 'DECIDE EN ${_decisionSecondsLeft}s'
                    : 'VEREDICTO FIJADO',
                color: decisionPhase
                    ? LiquidPalette.primary
                    : LiquidPalette.rise,
                dense: true,
                icon: decisionPhase ? Icons.hourglass_bottom : Icons.lock,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _countdown,
            style: const TextStyle(
              fontSize: 54,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              height: 1,
              color: LiquidPalette.ink,
            ),
          ),
          const SizedBox(height: 12),
          LiquidWaveBar(value: _roundProgress),
          const SizedBox(height: 12),
          _decisionModeSelector(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _entryPrice == null
                    ? 'Apertura pendiente'
                    : 'Apertura ${_entryPrice!.toStringAsFixed(2)}',
                style: LiquidType.caption,
              ),
              Text(
                _livePrice == null
                    ? '—'
                    : 'Ahora ${_livePrice!.toStringAsFixed(2)}',
                style: LiquidType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: LiquidPalette.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Protection over a position the user opened by hand on the exchange.
  Widget _guardCard() {
    final plan = _plan;
    final triggered = _guard.isTriggered;
    final armed = _guard.isArmed;
    final action = _action;
    final tone = triggered
        ? LiquidPalette.fall
        : armed
            ? LiquidPalette.rise
            : LiquidPalette.primary;

    return LiquidCard(
      accent: triggered || armed ? tone : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('LA OPERACIÓN', style: LiquidType.micro),
              LiquidChip(
                label: triggered
                    ? 'CIERRA AHORA'
                    : armed
                        ? 'PROTEGIDA'
                        : action == TradeAction.wait
                            ? 'SIN SEÑAL'
                            : _guard.actionLabel,
                color: tone,
                icon: triggered
                    ? Icons.report_gmailerrorred
                    : armed
                        ? Icons.shield_outlined
                        : Icons.trending_flat,
                dense: true,
                filled: triggered,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (triggered) ...[
            Text(
              'CIERRA AHORA',
              style: LiquidType.title.copyWith(color: LiquidPalette.fall),
            ),
            const SizedBox(height: 4),
            Text(
              '${_guard.reasonLabel}. En contra '
              '${_guard.adversePct.toStringAsFixed(3)}% desde '
              '${_guard.entryPrice.toStringAsFixed(2)}.',
              style: LiquidType.caption,
            ),
          ] else if (armed) ...[
            Text(
              _guard.action == TradeAction.buy
                  ? 'Compra vigilada'
                  : 'Venta vigilada',
              style: LiquidType.subtitle,
            ),
            const SizedBox(height: 4),
            Text(
              'Entrada ${_guard.entryPrice.toStringAsFixed(2)} · aviso si el '
              'precio ${_guard.action == TradeAction.buy ? 'cae por debajo de' : 'sube por encima de'} '
              '${_guard.invalidationPrice.toStringAsFixed(2)}, o si el consejo '
              'se da la vuelta. Ahora mismo en contra '
              '${_guard.adversePct.toStringAsFixed(3)}%.',
              style: LiquidType.caption,
            ),
          ] else ...[
            Text(
              plan == null
                  ? 'En cuanto el jefe fije la llamada, aquí aparece la acción '
                      'y podrás vigilarla.'
                  : action == TradeAction.wait
                      ? 'Esta ronda no supera el umbral de seguridad: el '
                          'consejo recomienda no entrar.'
                      : 'Si abres esta ${action == TradeAction.buy ? 'compra' : 'venta'} '
                          'en Binance, Nexora vigila el nivel que la invalida y '
                          'te avisa en el acto —también sobre la app de Binance— '
                          'para que la cierres antes de que duela.',
              style: LiquidType.caption,
            ),
          ],
          const SizedBox(height: 12),
          LiquidButton(
            label: triggered
                ? 'HECHO, YA CERRÉ'
                : armed
                    ? 'QUITAR PROTECCIÓN'
                    : 'PROTEGER OPERACIÓN',
            icon: triggered
                ? Icons.check
                : armed
                    ? Icons.shield_moon_outlined
                    : Icons.shield_outlined,
            color: tone,
            outlined: armed,
            onPressed: (plan == null || action == TradeAction.wait) && !armed &&
                    !triggered
                ? null
                : _toggleGuard,
          ),
          const SizedBox(height: 8),
          Text(
            'Nexora no ejecuta ni cancela órdenes: no tiene claves de tu cuenta '
            'de Binance. Vigila el mercado y te dice cuándo salir; abrir y '
            'cerrar lo haces tú.',
            style: LiquidType.caption.copyWith(
              fontSize: 10.5,
              color: LiquidPalette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  /// Control for the floating readout that sits on top of the trading app.
  Widget _overlayCard() => LiquidCard(
        accent: _overlayOn ? LiquidPalette.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SUPERPOSICIÓN', style: LiquidType.micro),
                LiquidChip(
                  label: _overlayOn
                      ? 'ACTIVA'
                      : _overlayPending
                          ? 'FALTA PERMISO'
                          : 'APAGADA',
                  color: _overlayOn
                      ? LiquidPalette.rise
                      : _overlayPending
                          ? LiquidPalette.primary
                          : LiquidPalette.inkFaint,
                  icon: _overlayOn
                      ? Icons.picture_in_picture_alt
                      : Icons.layers_outlined,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Deja el veredicto y la cuenta atrás flotando sobre Binance '
              'mientras miras el gráfico allí. Se arrastra a donde quieras y, '
              'al tocarlo, vuelves a Nexora.',
              style: LiquidType.caption,
            ),
            const SizedBox(height: 6),
            Text(
              'No lee la pantalla de Binance: el análisis sale del mismo mercado '
              'que Nexora ya recibe en vivo.',
              style: LiquidType.caption.copyWith(
                fontSize: 10.5,
                color: LiquidPalette.inkFaint,
              ),
            ),
            const SizedBox(height: 12),
            LiquidButton(
              label: _overlayOn
                  ? 'QUITAR DE LA PANTALLA'
                  : 'SUPERPONER SOBRE BINANCE',
              icon: _overlayOn ? Icons.close : Icons.open_in_new,
              outlined: _overlayOn,
              onPressed: _toggleOverlay,
            ),
            if (_overlayPending) ...[
              const SizedBox(height: 10),
              const LiquidAlert(
                message:
                    'Android pide el permiso «mostrar sobre otras apps» desde '
                    'sus ajustes. Concédeselo a Nexora y la superposición '
                    'arranca sola al volver.',
                tone: LiquidPalette.primary,
                icon: Icons.settings_outlined,
              ),
            ],
          ],
        ),
      );

  /// What the round did, held on screen until the user asks for the next one.
  Widget _roundClosedCard() {
    // Only the outcome of the round on screen; an older one would report a
    // hit that belongs to a different candle.
    final latest = _outcomes.isEmpty ? null : _outcomes.first;
    final settled = latest != null &&
            _roundStart != null &&
            latest.roundStart.millisecondsSinceEpoch ==
                _roundStart!.millisecondsSinceEpoch
        ? latest
        : null;
    final entry = _entryPrice;
    final close = _livePrice;
    final wentUp = entry != null && close != null && close > entry;
    final hit = settled?.hit;
    final waiting = _pendingRound == null;

    return LiquidCard(
      accent: hit == null
          ? LiquidPalette.inkFaint
          : (hit ? LiquidPalette.rise : LiquidPalette.fall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('RONDA CERRADA', style: LiquidType.micro),
              LiquidChip(
                label: hit == null
                    ? 'SIN LLAMADA'
                    : (hit ? 'ACERTÓ' : 'FALLÓ'),
                color: hit == null
                    ? LiquidPalette.inkFaint
                    : (hit ? LiquidPalette.rise : LiquidPalette.fall),
                icon: hit == null
                    ? Icons.remove
                    : (hit ? Icons.check_circle_outline : Icons.cancel_outlined),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                wentUp ? Icons.trending_up : Icons.trending_down,
                size: 34,
                color: LiquidPalette.directional(wentUp),
              ),
              const SizedBox(width: 10),
              Text(
                wentUp ? 'SUBIÓ' : 'BAJÓ',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1,
                  color: LiquidPalette.directional(wentUp),
                ),
              ),
              const Spacer(),
              if (settled != null)
                Text(
                  '${settled.movePct >= 0 ? '+' : ''}'
                  '${settled.movePct.toStringAsFixed(3)}%',
                  style: LiquidType.subtitle.copyWith(
                    color: LiquidPalette.directional(settled.movePct >= 0),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry == null
                    ? 'Apertura —'
                    : 'Apertura ${entry.toStringAsFixed(2)}',
                style: LiquidType.caption,
              ),
              Text(
                close == null
                    ? 'Cierre —'
                    : 'Cierre ${close.toStringAsFixed(2)}',
                style: LiquidType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: LiquidPalette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LiquidButton(
            label: waiting ? 'ESPERANDO LA SIGUIENTE VELA' : 'SIGUIENTE RONDA',
            icon: waiting ? Icons.hourglass_empty : Icons.arrow_forward,
            onPressed: waiting ? null : _advanceRound,
          ),
          const SizedBox(height: 8),
          Text(
            waiting
                ? 'El consejo ya aprendió de esta ronda. En cuanto Binance abra '
                    'la siguiente vela, el botón se activa.'
                : 'Binance ya abrió la siguiente vela. El consejo empieza de '
                    'cero en cuanto pulses.',
            style: LiquidType.caption.copyWith(fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  /// Anticipation versus accuracy. The percentages are what the realised
  /// fraction of the candle delivers on its own at each moment, so they are the
  /// floor the engine works from, not a promise.
  Widget _decisionModeSelector() {
    const options = <int>[60, 180, 240];
    const labels = <String>['1 min', '3 min', '4 min'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MOMENTO DE LA DECISIÓN', style: LiquidType.micro),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: _verdict != null
                      ? null
                      : () => setState(() =>
                          _chief = PulseChiefAnalyst(
                              decisionWindowSeconds: options[i])),
                  child: LiquidChip(
                    label:
                        '${labels[i]} · ${(PulseChiefAnalyst(decisionWindowSeconds: options[i]).mechanicalCeiling * 100).toStringAsFixed(0)}%',
                    dense: true,
                    filled: _chief.decisionWindowSeconds == options[i],
                    color: _chief.decisionWindowSeconds == options[i]
                        ? LiquidPalette.primary
                        : LiquidPalette.inkFaint,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Cuanto más tarde decide, más parte de la vela ya ocurrió y más '
          'acierta — pero menos anticipa. El porcentaje es el piso mecánico de '
          'cada momento, no una promesa del motor.',
          style: LiquidType.caption.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _verdictCard(
    bool up,
    ChiefVerdict? verdict,
    PulseConsensus? consensus,
  ) {
    final deciding = verdict == null;
    final abstains = verdict != null && !verdict.hasReading;
    final probability = verdict?.confidence ??
        ((consensus?.winningProbability ?? .5) * 100);
    final title = verdict == null
        ? 'ANALIZANDO'
        : !verdict.hasReading
            ? 'SIN\nLECTURA'
            : (verdict.isUp ? 'SUBE' : 'BAJA');
    final subtitle = deciding
        ? 'El analista jefe decide en ${_decisionSecondsLeft}s'
        : !verdict.hasReading
            ? 'la ronda no supera el umbral de seguridad'
            : '${probability.toStringAsFixed(1)}% de probabilidad';

    return LiquidCard(
      accent: deciding || abstains
          ? LiquidPalette.primary
          : LiquidPalette.directional(verdict.isUp),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        children: [
          const Text('VEREDICTO DEL ANALISTA JEFE', style: LiquidType.micro),
          const SizedBox(height: 14),
          if (_loading && consensus == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                color: LiquidPalette.primary,
                strokeWidth: 2.4,
              ),
            )
          else
            LiquidOrb(
              probability: deciding
                  ? (consensus?.winningProbability ?? .5)
                  : probability / 100,
              up: up,
              idle: deciding || abstains,
              title: title,
              subtitle: subtitle,
            ),
          const SizedBox(height: 16),
          if (verdict != null) ...[
            Text(
              verdict.headline,
              textAlign: TextAlign.center,
              style: LiquidType.subtitle,
            ),
            if (!verdict.hasReading) ...[
              const SizedBox(height: 10),
              const LiquidAlert(
                message:
                    'La evidencia de esta ronda queda dentro de la banda de '
                    'ruido, así que el motor no lanza predicción. Medido sobre '
                    '1999 rondas reales, exigir este margen sube el acierto del '
                    '63% al 70% sobre las rondas en las que sí habla.',
                icon: Icons.do_not_disturb_on_outlined,
              ),
            ],
            if (!verdict.fullDeliberation) ...[
              const SizedBox(height: 10),
              const LiquidAlert(
                message:
                    'La ronda ya estaba en curso al abrir la app: el analista '
                    'jefe no tuvo su minuto completo de deliberación y la '
                    'convicción se recortó. La próxima ronda arranca desde cero.',
                icon: Icons.timelapse,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                LiquidChip(
                  label:
                      '${verdict.councilsInFavour}/${verdict.councilVotes.length} consejos',
                  dense: true,
                  color: LiquidPalette.directional(verdict.isUp),
                ),
                LiquidChip(
                  label:
                      'Estabilidad ${(verdict.stability * 100).toStringAsFixed(0)}%',
                  dense: true,
                  color: LiquidPalette.info,
                ),
                LiquidChip(
                  label: verdict.fullDeliberation
                      ? '${verdict.samplesUsed} lecturas en 60 s'
                      : 'ventana incompleta · ${verdict.samplesUsed} lecturas',
                  dense: true,
                  color: verdict.fullDeliberation
                      ? LiquidPalette.inkFaint
                      : LiquidPalette.primary,
                  icon: verdict.fullDeliberation ? null : Icons.timelapse,
                ),
                LiquidChip(
                  label: '${verdict.totalAnalysts} analistas',
                  dense: true,
                  color: LiquidPalette.primary,
                ),
                LiquidChip(
                  label: 'Auditoría ${verdict.auditVerdict.label}',
                  dense: true,
                  color: switch (verdict.auditVerdict) {
                    AuditVerdict.approved => LiquidPalette.rise,
                    AuditVerdict.caution => LiquidPalette.primary,
                    AuditVerdict.vetoed => LiquidPalette.fall,
                  },
                ),
              ],
            ),
          ] else
            Text(
              'Los ${_totalAgents} agentes están entregando su lectura. '
              'El analista jefe fija una única decisión dentro del primer minuto '
              'y no la cambia hasta el cierre.',
              textAlign: TextAlign.center,
              style: LiquidType.caption,
            ),
        ],
      ),
    );
  }

  Widget _strategyCard(PulseRoundPlan plan, PulseRoundTracking? tracking) {
    final status = tracking?.status ?? RoundPlanStatus.building;
    final tone = switch (status) {
      RoundPlanStatus.onTrack || RoundPlanStatus.settledWin => LiquidPalette.rise,
      RoundPlanStatus.atRisk => LiquidPalette.primary,
      RoundPlanStatus.invalidated ||
      RoundPlanStatus.settledLoss =>
        LiquidPalette.fall,
      RoundPlanStatus.building => LiquidPalette.inkFaint,
    };

    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiquidSectionTitle(
            title: 'Estrategia de la ronda',
            subtitle:
                'Tesis fijada al abrir los 5 minutos, procesando el gráfico en ese instante.',
            trailing: LiquidChip(label: status.label, color: tone, dense: true),
          ),
          Text(plan.strategy, style: LiquidType.body),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LiquidStat(
                  label: 'Apertura',
                  value: plan.entryPrice.toStringAsFixed(2),
                ),
              ),
              Expanded(
                child: LiquidStat(
                  label: 'Objetivo',
                  value: plan.targetPrice.toStringAsFixed(2),
                  color: LiquidPalette.directional(plan.isUp),
                ),
              ),
              Expanded(
                child: LiquidStat(
                  label: 'Invalidación',
                  value: plan.invalidationPrice.toStringAsFixed(2),
                  color: LiquidPalette.fall,
                ),
              ),
            ],
          ),
          if (tracking != null) ...[
            const SizedBox(height: 14),
            LiquidMeter(
              label: 'Avance hacia el objetivo',
              value: tracking.progressToTarget,
              bipolar: false,
              color: tone,
              trailing: '${(tracking.progressToTarget * 100).toStringAsFixed(0)}%',
            ),
            LiquidMeter(
              label: 'Movimiento desde la apertura',
              value: (tracking.movePct / math.max(plan.expectedMovePct, .01))
                  .clamp(-1.0, 1.0)
                  .toDouble(),
              trailing:
                  '${tracking.movePct >= 0 ? '+' : ''}${tracking.movePct.toStringAsFixed(3)}%',
            ),
            const SizedBox(height: 10),
            LiquidAlert(
              message: tracking.commentary,
              tone: tone,
              icon: switch (status) {
                RoundPlanStatus.onTrack ||
                RoundPlanStatus.settledWin =>
                  Icons.trending_up,
                RoundPlanStatus.atRisk => Icons.priority_high,
                RoundPlanStatus.invalidated ||
                RoundPlanStatus.settledLoss =>
                  Icons.close,
                RoundPlanStatus.building => Icons.hourglass_empty,
              },
            ),
          ],
          if (plan.drivers.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('POR QUÉ', style: LiquidType.micro),
            const SizedBox(height: 8),
            for (final driver in plan.drivers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: const BoxDecoration(
                        color: LiquidPalette.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Text(driver, style: LiquidType.caption)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _liveChartCard(
    bool up,
    PulseRoundPlan? plan,
    PulseRoundTracking? tracking,
  ) =>
      LiquidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiquidSectionTitle(
              title: 'Gráfico de la ronda en vivo',
              subtitle:
                  'Precio contra la apertura de los 5 minutos, actualizado con cada tick de Binance.',
              trailing: tracking == null
                  ? null
                  : LiquidChip(
                      label:
                          '${tracking.movePct >= 0 ? '+' : ''}${tracking.movePct.toStringAsFixed(3)}%',
                      color: LiquidPalette.directional(tracking.movePct >= 0),
                      dense: true,
                    ),
            ),
            LiquidRoundChart(
              path: _roundPath,
              entryPrice: plan?.entryPrice ?? _entryPrice ?? 0,
              up: up,
            ),
          ],
        ),
      );

  Widget _marketStateCard(PulseSignal signal) {
    final consensus = _consensus;
    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiquidSectionTitle(
            title: 'Estado del mercado',
            subtitle: 'Lectura cuantitativa que reciben todos los consejos.',
            trailing: LiquidChip(
              label: signal.stabilityLabel,
              dense: true,
              color: switch (signal.stability) {
                MarketStability.stable => LiquidPalette.rise,
                MarketStability.unstable => LiquidPalette.primary,
                MarketStability.veryUnstable => LiquidPalette.fall,
              },
            ),
          ),
          LiquidMeter(label: 'Momentum', value: signal.momentumScore / 100),
          LiquidMeter(label: 'Tendencia', value: signal.trendScore / 100),
          LiquidMeter(
            label: 'Desequilibrio del libro',
            value: signal.orderBookImbalance / 100,
          ),
          LiquidMeter(label: 'Presión de cuerpo', value: signal.bodyPressure / 100),
          LiquidMeter(
            label: 'Inestabilidad',
            value: signal.instabilityScore / 100,
            bipolar: false,
            color: LiquidPalette.primary,
          ),
          if (consensus != null)
            LiquidMeter(
              label: 'Dispersión entre analistas',
              value: consensus.dispersion,
              bipolar: false,
              color: LiquidPalette.info,
            ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final hits = _outcomes.where((o) => o.hit).length;
    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiquidSectionTitle(
            title: 'Rondas cerradas en esta sesión',
            subtitle: '$hits aciertos de ${_outcomes.length} rondas evaluadas.',
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final outcome in _outcomes)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: outcome.hit
                        ? LiquidPalette.riseSoft
                        : LiquidPalette.fallSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (outcome.hit
                              ? LiquidPalette.rise
                              : LiquidPalette.fall)
                          .withValues(alpha: .35),
                    ),
                  ),
                  child: Text(
                    '${outcome.predictedUp ? '↑' : '↓'} '
                    '${outcome.movePct >= 0 ? '+' : ''}${outcome.movePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: outcome.hit
                          ? LiquidPalette.rise
                          : LiquidPalette.fall,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Tab 2: councils ------------------------------------------------------

  List<Widget> _councilsTab() {
    final consensus = _consensus;
    final verdict = _verdict;
    return [
      if (verdict != null) ...[
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LiquidSectionTitle(
                title: 'Cómo decidió el analista jefe',
                subtitle:
                    'Toda la data de los consejos converge en un solo agente que resuelve dentro del primer minuto.',
              ),
              for (final vote in verdict.councilVotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          '${vote.council} · ${vote.members}',
                          style: LiquidType.caption
                              .copyWith(color: LiquidPalette.ink),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: LiquidMeter(
                          label: '',
                          value: (vote.probabilityUp - .5) * 2,
                          trailing: vote.directionLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              for (final line in verdict.rationale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('· $line', style: LiquidType.caption),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (consensus != null) ...[
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidSectionTitle(
                title: 'Equipos de los 100 analistas',
                subtitle:
                    '${consensus.ensemble.upVotes} votan alza · ${consensus.ensemble.downVotes} votan baja · '
                    '${consensus.ensemble.activeAnalysts} activos',
              ),
              for (final team in consensus.ensemble.teamOpinions)
                LiquidMeter(
                  label:
                      '${team.family.label} · ${team.activeMembers}/10 activos',
                  value: (team.probabilityUp - .5) * 2,
                  trailing: '${(team.probabilityUp * 100).toStringAsFixed(0)}%',
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidSectionTitle(
                title: 'Consejo de 50 matemáticos',
                subtitle: consensus.briefing.isReady
                    ? 'Acuerdo interno ${(consensus.briefing.internalAgreement * 100).toStringAsFixed(0)}% · '
                        'dispersión ${(consensus.briefing.dispersion * 100).toStringAsFixed(0)}%'
                    : 'Reuniendo datos suficientes para las derivaciones.',
              ),
              for (final branch in MathBranch.values)
                LiquidMeter(
                  label: branch.label,
                  value: consensus.briefing.signalOf(branch),
                ),
              const SizedBox(height: 10),
              const Text('OPERACIONES MÁS DECISIVAS', style: LiquidType.micro),
              const SizedBox(height: 8),
              for (final theorem in consensus.briefing.topTheorems(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#${theorem.id} ${theorem.name}',
                              style: LiquidType.caption.copyWith(
                                color: LiquidPalette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          LiquidChip(
                            label: theorem.signal >= 0 ? 'ALZA' : 'BAJA',
                            dense: true,
                            color:
                                LiquidPalette.directional(theorem.signal >= 0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(theorem.formula, style: LiquidType.caption),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidSectionTitle(
                title: 'Archivo histórico · 100 analistas de patrones',
                subtitle: _patterns.isReady
                    ? '${_patterns.candlesStudied} velas estudiadas sobre '
                        '${_patterns.historyDays.toStringAsFixed(0)} días · '
                        '${_patterns.analogsExamined} análogos encontrados'
                    : 'Descargando el histórico multi-temporalidad de Bitcoin.',
              ),
              if (_patterns.isReady) ...[
                for (final lens in PatternLens.values)
                  LiquidMeter(
                    label: lens.label,
                    value: _patterns.signalOf(lens),
                  ),
                const SizedBox(height: 10),
                const Text('EPISODIOS MÁS PARECIDOS', style: LiquidType.micro),
                const SizedBox(height: 8),
                for (final match in _patterns.bestMatches.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '· ${_formatDate(match.at)} (${match.interval}) · '
                      'similitud ${(match.similarity * 100).toStringAsFixed(0)}% → '
                      '${match.nextMovePct >= 0 ? '+' : ''}${match.nextMovePct.toStringAsFixed(2)}%',
                      style: LiquidType.caption,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LiquidSectionTitle(
                title: 'Peso de cada modelo en la fusión',
                subtitle:
                    'Agregación logarítmica de probabilidades, no un promedio simple.',
              ),
              for (final contribution in consensus.contributions)
                LiquidMeter(
                  label:
                      '${contribution.name} · peso ${(contribution.weight * 100).toStringAsFixed(0)}%',
                  value: (contribution.probabilityUp - .5) * 2,
                  trailing:
                      '${(contribution.probabilityUp * 100).toStringAsFixed(0)}%',
                ),
            ],
          ),
        ),
      ] else
        const LiquidCard(
          child: Text('Reuniendo la primera lectura del mercado…',
              style: LiquidType.body),
        ),
    ];
  }

  // --- Tab 3: news ----------------------------------------------------------

  List<Widget> _newsTab() => [
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidSectionTitle(
                title: 'Sala de noticias · 50 analistas',
                subtitle: _news.isReady
                    ? '${_news.itemsAnalyzed} titulares vigilados · '
                        '${_news.breakingCount} de última hora · '
                        '${_news.bullishAnalysts} alcistas / ${_news.bearishAnalysts} bajistas'
                    : 'Conectando con los feeds de Bitcoin…',
                trailing: LiquidChip(
                  label: _newsLoading ? 'ACTUALIZANDO' : 'EN VIVO',
                  dense: true,
                  color: _newsLoading
                      ? LiquidPalette.inkFaint
                      : LiquidPalette.rise,
                  icon: Icons.rss_feed,
                ),
              ),
              if (_news.isReady)
                for (final desk in NewsDesk.values)
                  LiquidMeter(
                    label: desk.label,
                    value: _news.signalOf(desk),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LiquidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LiquidSectionTitle(
                title: 'Titulares en tiempo real',
                subtitle:
                    'Los feeds se releen cada 45 segundos; la antigüedad pondera el voto de cada analista.',
              ),
              if (_news.headlines.isEmpty)
                const Text(
                  'Sin titulares disponibles en este momento.',
                  style: LiquidType.body,
                )
              else
                for (final headline in _news.headlines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              margin: const EdgeInsets.only(right: 10, top: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: headline.score == 0
                                    ? LiquidPalette.border
                                    : LiquidPalette.directional(
                                        headline.score > 0),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                headline.item.title,
                                style: LiquidType.caption.copyWith(
                                  color: LiquidPalette.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Padding(
                          padding: const EdgeInsets.only(left: 13),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              LiquidChip(
                                label: headline.item.source,
                                dense: true,
                                color: LiquidPalette.inkFaint,
                              ),
                              LiquidChip(
                                label: headline.desk.shortLabel,
                                dense: true,
                                color: LiquidPalette.info,
                              ),
                              LiquidChip(
                                label: _formatAge(headline.ageMinutes),
                                dense: true,
                                color: headline.ageMinutes <= 10
                                    ? LiquidPalette.primary
                                    : LiquidPalette.inkFaint,
                              ),
                              if (headline.score.abs() >= .1)
                                LiquidChip(
                                  label: headline.score > 0
                                      ? 'ALCISTA'
                                      : 'BAJISTA',
                                  dense: true,
                                  color: LiquidPalette.directional(
                                      headline.score > 0),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ];

  // --- Tab 4: evolution -----------------------------------------------------

  List<Widget> _evolutionTab() {
    final ranked = _evolution.rankedRecords();
    final best = ranked.take(6).toList();
    final worst = ranked.reversed.take(3).toList();
    return [
      LiquidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LiquidSectionTitle(
              title: 'Evolución de los 100 analistas',
              subtitle:
                  'Aprenden de cada revisión del mercado y de cada ronda cerrada; los peores se reemplazan por cruces de los mejores.',
            ),
            Row(
              children: [
                Expanded(
                  child: LiquidStat(
                    label: 'Generación',
                    value: '${_evolution.generation}',
                    color: LiquidPalette.primary,
                  ),
                ),
                Expanded(
                  child: LiquidStat(
                    label: 'Rondas',
                    value: '${_evolution.roundsObserved}',
                  ),
                ),
                Expanded(
                  child: LiquidStat(
                    label: 'Aciertos',
                    value: _evolution.scored == 0
                        ? '—'
                        : '${(_evolution.accuracy * 100).toStringAsFixed(1)}%',
                    color: LiquidPalette.rise,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LiquidMeter(
              label: 'Experiencia acumulada',
              value: (_evolution.experience / 60).clamp(0.0, 1.0).toDouble(),
              bipolar: false,
              trailing: _evolution.experience.toStringAsFixed(1),
            ),
            LiquidMeter(
              label: 'Skill sobre el azar (Brier)',
              value: _evolution.consensusSkill,
              trailing: _evolution.consensusBrier.toStringAsFixed(4),
            ),
            LiquidMeter(
              label: 'Calibración aprendida (pendiente)',
              value:
                  (_evolution.calibrationSlope - 1).clamp(-1.0, 1.0).toDouble(),
              trailing: _evolution.calibrationSlope.toStringAsFixed(2),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      LiquidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LiquidSectionTitle(
              title: 'Analistas con mejor desempeño',
              subtitle:
                  'Fitness = skill de Brier y fiabilidad bayesiana, encogidos por experiencia.',
            ),
            for (final record in best)
              LiquidMeter(
                label: 'Analista #${record.id} · '
                    '${(record.reliability * 100).toStringAsFixed(0)}% acierto · '
                    'gen ${record.bornAtGeneration}',
                value: record.fitness,
                trailing: 'x${record.weight.toStringAsFixed(2)}',
              ),
            const SizedBox(height: 10),
            const Text('EN RIESGO DE REEMPLAZO', style: LiquidType.micro),
            const SizedBox(height: 6),
            for (final record in worst)
              LiquidMeter(
                label: 'Analista #${record.id}',
                value: record.fitness,
                trailing: 'x${record.weight.toStringAsFixed(2)}',
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      LiquidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LiquidSectionTitle(
              title: 'Composición del consejo',
              subtitle: 'Quién aporta qué a la decisión final.',
            ),
            _compositionRow('100 analistas de mercado',
                '10 equipos · genoma evolutivo', LiquidPalette.primary),
            _compositionRow('50 matemáticos',
                '10 ramas · 50 operaciones complejas', LiquidPalette.info),
            _compositionRow('100 analistas de patrones',
                '10 lentes sobre años de histórico', LiquidPalette.rise),
            _compositionRow('50 analistas de noticias',
                '10 mesas · feeds en vivo', LiquidPalette.fall),
            _compositionRow('1 analista jefe',
                'Decide en 60 segundos y no revisa', LiquidPalette.ink),
          ],
        ),
      ),
    ];
  }

  Widget _compositionRow(String title, String subtitle, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LiquidType.caption.copyWith(
                      color: LiquidPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(subtitle, style: LiquidType.caption),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _auditCard(AuditReport audit) {
    final tone = switch (audit.verdict) {
      AuditVerdict.approved => LiquidPalette.rise,
      AuditVerdict.caution => LiquidPalette.primary,
      AuditVerdict.vetoed => LiquidPalette.fall,
    };
    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiquidSectionTitle(
            title: 'Test final · 100 auditores',
            subtitle:
                'Auditan a todos los consejos antes de que el paquete llegue al analista jefe.',
            trailing:
                LiquidChip(label: audit.verdict.label, color: tone, dense: true),
          ),
          Row(
            children: [
              Expanded(
                child: LiquidStat(
                  label: 'Conformes',
                  value: '${audit.passed}/${audit.auditors}',
                  color: tone,
                ),
              ),
              Expanded(
                child: LiquidStat(
                  label: 'Recorte',
                  value: '${((1 - audit.shrinkFactor) * 100).toStringAsFixed(0)}%',
                ),
              ),
              Expanded(
                child: LiquidStat(
                  label: 'Calidad',
                  value: '${(audit.qualityScore * 100).toStringAsFixed(0)}%',
                  color: LiquidPalette.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final domain in AuditDomain.values)
            LiquidMeter(
              label: domain.label,
              value: 1 - audit.severityOf(domain) * 2,
              trailing:
                  audit.severityOf(domain) <= .35 ? 'OK' : 'REVISAR',
            ),
          if (audit.flags.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final flag in audit.flags)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: LiquidAlert(
                  message: flag,
                  tone: LiquidPalette.primary,
                  icon: Icons.report_gmailerrorred_outlined,
                ),
              ),
          ],
        ],
      ),
    );
  }

  // --- Tab: neural network --------------------------------------------------

  List<Widget> _networkTab() {
    final graph = _buildGraph();
    final verdict = _verdict;
    return [
      LiquidCard(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: LiquidSectionTitle(
                title: 'Red neuronal en vivo',
                subtitle:
                    'Datos → consejos → equipos de analistas → auditoría → analista jefe. '
                    'El color es la dirección y el grosor, la fuerza de la evidencia.',
              ),
            ),
            LiquidNeuralNetwork(graph: graph),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  LiquidChip(
                    label: 'Alcista',
                    dense: true,
                    color: LiquidPalette.rise,
                  ),
                  LiquidChip(
                    label: 'Bajista',
                    dense: true,
                    color: LiquidPalette.fall,
                  ),
                  LiquidChip(
                    label: 'Sin señal',
                    dense: true,
                    color: LiquidPalette.inkFaint,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      LiquidCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LiquidSectionTitle(
              title: 'Capas de la red',
              subtitle: 'Qué hace cada nivel antes de la decisión final.',
            ),
            _compositionRow('Capa 1 · Datos',
                'Velas, libro, trades, ETH y feeds de noticias', LiquidPalette.info),
            _compositionRow('Capa 2 · Consejos',
                '50 matemáticos, 100 patrones históricos y 50 de noticias',
                LiquidPalette.primary),
            _compositionRow('Capa 3 · Analistas',
                '100 analistas en 10 equipos, con genoma evolutivo',
                LiquidPalette.rise),
            _compositionRow('Capa 4 · Auditoría',
                '100 auditores en 10 mesas de control', LiquidPalette.fall),
            _compositionRow(
                'Capa 5 · Analista jefe',
                verdict == null
                    ? 'Deliberando dentro del primer minuto'
                    : 'Decisión ${verdict.isUp ? 'SUBE' : 'BAJA'} al '
                        '${verdict.confidence.toStringAsFixed(1)}%',
                LiquidPalette.ink),
            const SizedBox(height: 6),
            Text(
              'Histórico cargado: $_historyCandles velas · '
              '${_briefing.isReady ? '${_briefing.mathematicians} operaciones matemáticas activas' : 'consejo matemático calentando'}',
              style: LiquidType.caption,
            ),
          ],
        ),
      ),
    ];
  }

  NeuralGraph _buildGraph() {
    final consensus = _consensus;
    final signal = _signal;
    final audit = _audit;
    final nodes = <NeuralNode>[];
    final links = <NeuralLink>[];

    double activation(double? value) =>
        (value == null || !value.isFinite) ? 0.0 : value.clamp(-1.0, 1.0).toDouble();

    // Layer 0 — data sources (indices 0..4)
    nodes.addAll([
      NeuralNode(
        label: 'Velas',
        layer: 0,
        activation: activation((signal?.momentumScore ?? 0) / 100),
        strength: signal == null ? .2 : .6,
      ),
      NeuralNode(
        label: 'Libro',
        layer: 0,
        activation: activation((signal?.orderBookImbalance ?? 0) / 100),
        strength: signal == null ? .2 : .55,
      ),
      NeuralNode(
        label: 'Trades',
        layer: 0,
        activation: activation(_flowActivation),
        strength: .55,
      ),
      NeuralNode(
        label: 'ETH',
        layer: 0,
        activation: activation(_crossActivation),
        strength: .4,
      ),
      NeuralNode(
        label: 'Feeds',
        layer: 0,
        activation: activation(_news.consensusSignal),
        strength: _news.isReady ? .5 : .15,
      ),
    ]);

    // Layer 1 — councils (5..7)
    nodes.addAll([
      NeuralNode(
        label: 'Matemáticos',
        layer: 1,
        activation: activation(_briefing.consensusSignal),
        strength: _briefing.isReady ? .75 : .15,
        members: PulseMathCouncil.mathematicians,
      ),
      NeuralNode(
        label: 'Patrones',
        layer: 1,
        activation: activation(_patterns.consensusSignal),
        strength: _patterns.isReady ? .75 : .15,
        members: PulsePatternArchive.analysts,
      ),
      NeuralNode(
        label: 'Noticias',
        layer: 1,
        activation: activation(_news.consensusSignal),
        strength: _news.isReady ? .6 : .15,
        members: PulseNewsDesk.analysts,
      ),
    ]);

    // Layer 2 — the ten analyst teams (8..17)
    final teams = consensus?.ensemble.teamOpinions ?? const <TeamOpinion>[];
    for (final family in AnalystFamily.values) {
      TeamOpinion? team;
      for (final candidate in teams) {
        if (candidate.family == family) {
          team = candidate;
          break;
        }
      }
      nodes.add(NeuralNode(
        label: family.label,
        layer: 2,
        activation: team == null ? 0 : (team.probabilityUp - .5) * 2,
        strength: team == null ? .15 : (.25 + team.quality * .75),
        members: 10,
      ));
    }

    // Layer 3 — the ten audit desks (18..27)
    for (final domain in AuditDomain.values) {
      final severity = audit?.severityOf(domain) ?? 0;
      nodes.add(NeuralNode(
        label: domain.label.split(' ').first,
        layer: 3,
        activation:
            audit == null ? 0 : (1 - severity * 2).clamp(-1.0, 1.0).toDouble(),
        strength: audit == null ? .15 : .35 + severity * .5,
        members: 10,
      ));
    }

    // Layer 4 — the chief (28)
    final chiefActivation = _verdict != null
        ? (_verdict!.probabilityUp - .5) * 2
        : ((consensus?.probabilityUp ?? .5) - .5) * 2;
    nodes.add(NeuralNode(
      label: 'Jefe',
      layer: 4,
      activation: activation(chiefActivation),
      strength: _verdict == null ? .35 : (.5 + _verdict!.stability * .5),
    ));

    for (var d = 0; d < 5; d++) {
      for (var c = 5; c < 8; c++) {
        links.add(NeuralLink(from: d, to: c, weight: .28));
      }
    }
    for (var c = 5; c < 8; c++) {
      final councilStrength = nodes[c].strength;
      for (var team = 8; team < 18; team++) {
        links.add(NeuralLink(
          from: c,
          to: team,
          weight: (.15 + councilStrength * .45).clamp(.05, 1.0).toDouble(),
        ));
      }
    }
    for (var team = 8; team < 18; team++) {
      final strength = nodes[team].strength;
      for (var k = 0; k < 3; k++) {
        links.add(NeuralLink(
          from: team,
          to: 18 + ((team - 8) * 3 + k) % 10,
          weight: (.12 + strength * .5).clamp(.05, 1.0).toDouble(),
        ));
      }
    }
    for (var desk = 18; desk < 28; desk++) {
      links.add(NeuralLink(
        from: desk,
        to: 28,
        weight: (.2 + nodes[desk].strength * .6).clamp(.05, 1.0).toDouble(),
      ));
    }

    return NeuralGraph(nodes: nodes, links: links);
  }

  String _formatAge(double minutes) {
    if (!minutes.isFinite) return 'sin fecha';
    if (minutes < 1) return 'ahora';
    if (minutes < 60) return 'hace ${minutes.round()} min';
    final hours = minutes / 60;
    if (hours < 24) return 'hace ${hours.round()} h';
    return 'hace ${(hours / 24).round()} d';
  }

  String _formatDate(DateTime date) {
    final d = date.toUtc();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _clock?.cancel();
    _reviewTimer?.cancel();
    _newsTimer?.cancel();
    _historyTimer?.cancel();
    _syncTimer?.cancel();
    _klineSubscription?.cancel();
    // Nothing is feeding the panel once this screen is gone.
    if (_overlayOn) unawaited(_overlay.stop());
    unawaited(_store.save(_evolution));
    super.dispose();
  }
}
