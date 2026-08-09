import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../market/data/binance_futures_market_service.dart';
import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../../market/domain/market_asset.dart';
import '../../market/domain/symbol_trading_rules.dart';
import '../data/pulse_ai_service.dart';
import '../domain/btc_5m_logistic_model.dart';
import '../domain/futures_trade_planner.dart';
import '../domain/market_knowledge_framework.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_decision_gate.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_probability_calibrator.dart';
import '../domain/pulse_signal.dart';
import '../domain/pulse_statistical_engine.dart';
import 'pulse_dashboard_widgets.dart';

class NexoraFuturesDashboardScreen extends StatefulWidget {
  const NexoraFuturesDashboardScreen({super.key});

  @override
  State<NexoraFuturesDashboardScreen> createState() =>
      _NexoraFuturesDashboardScreenState();
}

class _NexoraFuturesDashboardScreenState
    extends State<NexoraFuturesDashboardScreen> {
  static const _supportedSymbols = <String>[
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'BNBUSDT',
    'XRPUSDT',
  ];

  final _service = BinanceFuturesMarketService();
  final _engine = const PulseEngine();
  final _ai = const PulseAiService();
  final _calibrator = const PulseProbabilityCalibrator();
  final _statistical = const PulseStatisticalEngine();
  final _logistic5m = const Btc5mLogisticModel();
  final _ensemble100 = const PulseEnsemble100();
  final _knowledge = const MarketKnowledgeFramework();
  final _futuresPlanner = const FuturesTradePlanner(
    minimumConfidence: 52,
    minimumAgreement: .45,
    minimumStatisticalQuality: .04,
    maximumInstability: 90,
  );

  Timer? _refreshTimer;
  Timer? _syncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime? _tickerLoadedAt;
  DateTime? _aiLoadedAt;
  DateTime? _planUpdatedAt;
  PulseSignal? _signal;
  PulseAiConsensus? _aiPrediction;
  PulseProbabilityResult? _mathPrediction;
  PulseStatisticalResult? _statPrediction;
  Btc5mLogisticResult? _logisticPrediction;
  PulseEnsemble100Result? _ensemblePrediction;
  LockedPulseDecision? _lockedDecision;
  FuturesTradePlan? _futuresPlan;
  OrderBookSnapshot? _book;
  AggTradeSnapshot? _trades;
  MarketAsset? _ticker;
  SymbolTradingRules? _tradingRules;
  List<Candle> _candles5m = const [];
  bool _loading = true;
  bool _loadInFlight = false;
  bool _clockSyncInFlight = false;
  String? _error;
  double _currentPrice = 0;
  double _rawProbabilityUp = .5;
  double _intermarketConfirmation = 0;
  String _symbol = 'BTCUSDT';

  DateTime get _binanceNow => DateTime.now().toUtc().add(_binanceOffset);

  String get _baseAsset => _symbol.substring(0, _symbol.length - 'USDT'.length);

  String get _confirmationSymbol =>
      _symbol == 'BTCUSDT' ? 'ETHUSDT' : 'BTCUSDT';

  Future<void> _changeSymbol(String symbol) async {
    if (symbol == _symbol || !_supportedSymbols.contains(symbol)) return;
    setState(() {
      _symbol = symbol;
      _tickerLoadedAt = null;
      _aiLoadedAt = null;
      _planUpdatedAt = null;
      _signal = null;
      _aiPrediction = null;
      _mathPrediction = null;
      _statPrediction = null;
      _logisticPrediction = null;
      _ensemblePrediction = null;
      _lockedDecision = null;
      _futuresPlan = null;
      _book = null;
      _trades = null;
      _ticker = null;
      _tradingRules = null;
      _candles5m = const [];
      _currentPrice = 0;
      _rawProbabilityUp = .5;
      _intermarketConfirmation = 0;
      _loading = true;
      _error = null;
    });
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _syncBinanceClock();
    await _load();
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
    if (_clockSyncInFlight) return;
    _clockSyncInFlight = true;
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
    } finally {
      _clockSyncInFlight = false;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final requestedSymbol = _symbol;
    final requestedConfirmationSymbol = _confirmationSymbol;
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
        _service.loadCandles(requestedSymbol, '1m', limit: 90),
        _service.loadCandles(requestedSymbol, '5m', limit: 60),
        _service.loadCandles(requestedConfirmationSymbol, '1m', limit: 30),
        _service.loadOrderBookSnapshot(requestedSymbol, limit: 100),
        _service.loadAggTradeSnapshot(requestedSymbol, limit: 500),
        tickerIsStale
            ? _service.loadTicker24h(requestedSymbol)
            : Future<MarketAsset?>.value(_ticker),
        _loadTradingRulesOrNull(requestedSymbol),
        _service.loadPremiumSnapshot(requestedSymbol),
      ]);
      final candles1m = results[0] as List<Candle>;
      final candles5m = results[1] as List<Candle>;
      final confirmationCandles = results[2] as List<Candle>;
      final book = results[3] as OrderBookSnapshot;
      final trades = results[4] as AggTradeSnapshot;
      final ticker = results[5] as MarketAsset?;
      final tradingRules = results[6] as SymbolTradingRules?;
      final premium = results[7] as FuturesPremiumSnapshot;
      final currentPrice = candles1m.last.close;
      final rollingStartIndex = math.max(0, candles1m.length - 6);
      final startPrice = candles1m[rollingStartIndex].open;
      const analysisHorizonSeconds = 300;
      final signal = _engine.analyze(
        candles: candles1m,
        bidVolume: book.bidVolume,
        askVolume: book.askVolume,
        roundStartPrice: startPrice,
        secondsRemaining: analysisHorizonSeconds,
      );

      PulseProbabilityResult? mathPrediction;
      PulseStatisticalResult? statPrediction;
      PulseEnsemble100Result? ensemblePrediction;
      var intermarketConfirmation = 0.0;
      mathPrediction = _calibrator.calibrate(
        score: signal.score,
        instability: signal.instabilityScore,
        agreement: signal.agreementRatio,
        roundDistancePct: signal.roundDistancePct,
        expectedRemainingMovePct: signal.expectedRemainingMovePct,
        secondsRemaining: analysisHorizonSeconds,
      );
      statPrediction = _statistical.analyze(
        candles: candles1m,
        bidVolume: book.bidVolume,
        askVolume: book.askVolume,
        roundStartPrice: startPrice,
        secondsRemaining: analysisHorizonSeconds,
      );
      final analystInput = _buildAnalystInput(
        candles: candles1m,
        confirmationCandles: confirmationCandles,
        signal: signal,
        stat: statPrediction,
        startPrice: startPrice,
        secondsRemaining: analysisHorizonSeconds,
        book: book,
        trades: trades,
        premium: premium,
      );
      intermarketConfirmation = analystInput.get('ethConfirmation');
      ensemblePrediction = _ensemble100.analyze(analystInput);

      final completed5m = candles5m.length <= 1
          ? <Candle>[]
          : candles5m.sublist(0, candles5m.length - 1);
      final logisticPrediction = requestedSymbol == 'BTCUSDT'
          ? _logistic5m.analyze(completed5m)
          : const Btc5mLogisticResult(
              probabilityUp: .5,
              logit: 0,
              isReady: false,
            );

      var aiPrediction = _aiPrediction;
      final aiIsStale = _aiLoadedAt == null ||
          _binanceNow.difference(_aiLoadedAt!) >= const Duration(seconds: 30);
      var aiWasRefreshed = false;
      if (aiIsStale && _ai.isConfigured) {
        aiPrediction = await _ai.evaluate(
          symbol: requestedSymbol,
          startPrice: startPrice,
          currentPrice: currentPrice,
          secondsRemaining: analysisHorizonSeconds,
          quantitative: signal,
        );
        aiWasRefreshed = true;
      }
      final rawProbability = _fuseProbability(
        signal: signal,
        calibrated: mathPrediction,
        statistical: statPrediction,
        logistic: logisticPrediction,
        ensemble: ensemblePrediction,
        ai: aiPrediction,
      );
      final previousProbability = _lockedDecision?.probabilityUp;
      final continuousProbability = previousProbability == null
          ? rawProbability
          : (previousProbability * .65 + rawProbability * .35)
              .clamp(.08, .92)
              .toDouble();
      final decision = LockedPulseDecision(
        direction: continuousProbability >= .5
            ? PulseDirection.up
            : PulseDirection.down,
        probabilityUp: continuousProbability,
        lockedAt: _binanceNow,
      );
      final planUpdatedAt = _binanceNow;
      final futuresPlan = tradingRules == null
          ? FuturesTradePlan.noTrade(
              reason: 'Esperando los filtros oficiales de Binance Futures.',
            )
          : _futuresPlanner.build(
              decision: decision,
              entryCandles: candles1m,
              contextCandles: candles5m,
              bestBid: book.bestBid,
              bestAsk: book.bestAsk,
              analystAgreement: ensemblePrediction.agreement,
              statisticalQuality: statPrediction.signalQuality,
              instability: signal.instabilityScore,
              rules: tradingRules,
              premium: premium,
              validUntil: planUpdatedAt.add(const Duration(seconds: 30)),
              autoAdjustMargin: true,
            );

      if (!mounted || requestedSymbol != _symbol) return;
      setState(() {
        _candles5m = candles5m;
        _book = book;
        _trades = trades;
        _ticker = ticker;
        if (tickerIsStale && ticker != null) _tickerLoadedAt = DateTime.now();
        if (aiWasRefreshed) _aiLoadedAt = planUpdatedAt;
        _planUpdatedAt = planUpdatedAt;
        _currentPrice = currentPrice;
        _signal = signal;
        _mathPrediction = mathPrediction;
        _statPrediction = statPrediction;
        _logisticPrediction = logisticPrediction;
        _ensemblePrediction = ensemblePrediction;
        _aiPrediction = aiPrediction;
        _lockedDecision = decision;
        _futuresPlan = futuresPlan;
        _tradingRules = tradingRules ?? _tradingRules;
        _rawProbabilityUp = continuousProbability;
        _intermarketConfirmation = intermarketConfirmation;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || requestedSymbol != _symbol) return;
      setState(() {
        _loading = false;
        _error =
            'No se pudieron actualizar los datos reales. Se conservó la última lectura válida.';
      });
    } finally {
      _loadInFlight = false;
      if (mounted && requestedSymbol != _symbol) {
        unawaited(_load());
      }
    }
  }

  Future<SymbolTradingRules?> _loadTradingRulesOrNull(String symbol) async {
    if (_tradingRules != null) return _tradingRules;
    try {
      return await _service.loadTradingRules(symbol);
    } catch (_) {
      return null;
    }
  }

  AnalystInput _buildAnalystInput({
    required List<Candle> candles,
    required List<Candle> confirmationCandles,
    required PulseSignal signal,
    required PulseStatisticalResult stat,
    required double startPrice,
    required int secondsRemaining,
    required OrderBookSnapshot book,
    required AggTradeSnapshot trades,
    required FuturesPremiumSnapshot premium,
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
    final confirmationCloses = confirmationCandles
        .map((candle) => candle.close)
        .toList(growable: false);
    final confirmationReturn = confirmationCloses.length < 4
        ? 0.0
        : (confirmationCloses.last -
                confirmationCloses[confirmationCloses.length - 4]) /
            confirmationCloses[confirmationCloses.length - 4] *
            100;
    final fundingPressure = norm(-premium.fundingRate, .0005);
    final basisPressure = norm(-premium.basisBps, 12);

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
        // The ensemble feature keeps its historic key, but it now represents
        // ETH confirmation for BTC and BTC confirmation for every altcoin.
        'ethConfirmation': norm(confirmationReturn, .25),
        'exchangeConsensus': fundingPressure * .55 + basisPressure * .45,
        'betaResidual': norm(shortReturn - confirmationReturn, .25),
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
    final knowledgeMultiplier = _knowledgeMultiplierFor(
      signal: signal,
      calibrated: calibrated,
      statistical: statistical,
      ensemble: ensemble,
    );
    probability = .5 + (probability - .5) * math.sqrt(knowledgeMultiplier);
    return probability.clamp(.08, .92).toDouble();
  }

  double _knowledgeMultiplierFor({
    required PulseSignal signal,
    required PulseProbabilityResult? calibrated,
    required PulseStatisticalResult? statistical,
    required PulseEnsemble100Result? ensemble,
  }) {
    return _knowledge.confidenceMultiplier(
      instability: signal.instabilityScore / 100,
      analystAgreement: ensemble?.agreement ?? 0,
      statisticalEdge: calibrated?.statisticalEdge ?? 0,
      baselineAdvantage: .5,
      robustness: statistical?.signalQuality ?? 0,
    );
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

  BreakoutView get _breakout {
    final completed = _candles5m.length <= 1
        ? <Candle>[]
        : _candles5m.sublist(0, _candles5m.length - 1);
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
    final stable = (_signal?.instabilityScore ?? 100) <= 72;
    final spreadOk = (_book?.spreadBps ?? 99) <= 2;
    final technical = (_signal?.agreementRatio ?? 0) >= .55;
    final intermarketAligned = _intermarketConfirmation.abs() >= .08;
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
        status: 'CONTROL ACTIVO',
        positive: true,
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
        focus: 'contexto $_symbol/$_confirmationSymbol',
        status: intermarketAligned ? 'ACTIVO' : 'NEUTRO',
        positive: intermarketAligned,
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
        status: _lockedDecision == null ? 'RECOPILANDO' : 'ACTUALIZANDO',
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
              final desktop = available >= 1180;
              final columns = available >= 700 ? 2 : 1;
              final columnWidth = (available - gap * (columns - 1)) / columns;
              double widthFor(int desiredSpan) {
                final span = math.min(desiredSpan, columns);
                return columnWidth * span + gap * (span - 1);
              }

              final breakout = _breakout;
              final distributionPanel = AnalystDistributionPanel(
                ensemble: _ensemblePrediction,
              );
              final selectorPanel = FuturesSymbolSelector(
                symbols: _supportedSymbols,
                selectedSymbol: _symbol,
                onChanged: (symbol) => unawaited(_changeSymbol(symbol)),
              );
              final futuresPlanPanel = FuturesTradePlanPanel(
                symbol: _symbol,
                plan: _futuresPlan,
                updatedAt: _planUpdatedAt,
              );
              final teamsPanel = AnalystTeamsPanel(
                ensemble: _ensemblePrediction,
              );
              final knowledgePanel = KnowledgePanel(
                entries: _knowledgeEntries,
              );
              final chartPanel = MarketChartPanel(
                candles: _candles5m,
                currentPrice: _currentPrice,
                boxHigh: breakout.boxHigh,
                boxLow: breakout.boxLow,
                title: 'Gráfico $_symbol Perp · 5m',
              );
              final microstructurePanel = MicrostructurePanel(
                book: _book,
                trades: _trades,
                baseAsset: _baseAsset,
              );
              final biasPanel = AuditPanel(
                title: 'Detector de sesgos · Kahneman',
                entries: _biasEntries,
              );
              final breakoutPanel = BreakoutPanel(breakout: breakout);

              Widget desktopColumn(List<Widget> children) => Column(
                    children: [
                      for (var index = 0; index < children.length; index++) ...[
                        if (index > 0) const SizedBox(height: gap),
                        children[index],
                      ],
                    ],
                  );

              final overview = desktop
                  ? Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 22,
                              child: desktopColumn([futuresPlanPanel]),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              flex: 24,
                              child: desktopColumn([
                                distributionPanel,
                                teamsPanel,
                              ]),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              flex: 24,
                              child: desktopColumn([
                                knowledgePanel,
                                biasPanel,
                                breakoutPanel,
                              ]),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              flex: 30,
                              child: desktopColumn([
                                chartPanel,
                                microstructurePanel,
                              ]),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(width: widthFor(1), child: futuresPlanPanel),
                        SizedBox(width: widthFor(1), child: distributionPanel),
                        SizedBox(width: widthFor(1), child: teamsPanel),
                        SizedBox(width: widthFor(1), child: knowledgePanel),
                        SizedBox(width: widthFor(columns), child: chartPanel),
                        SizedBox(
                          width: widthFor(1),
                          child: microstructurePanel,
                        ),
                        SizedBox(width: widthFor(1), child: biasPanel),
                        SizedBox(width: widthFor(1), child: breakoutPanel),
                      ],
                    );
              return RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(horizontalPadding),
                  children: [
                    NexoraDashboardHeader(
                      price: _currentPrice,
                      change24h: _ticker?.changePercent24h ?? 0,
                      countdown: '',
                      roundNumber: 0,
                      loading: _loading || _loadInFlight,
                      continuousMode: true,
                      brandTitle: 'NEXORA FUTURES',
                      brandSubtitle: 'PLAN USDⓈ-M · POOL DE 100 ANALISTAS',
                      symbolLabel: '$_symbol PERP.',
                      sourceLabel: 'BINANCE USDⓈ-M',
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
                    selectorPanel,
                    const SizedBox(height: gap),
                    overview,
                    const SizedBox(height: 14),
                    const Text(
                      'Nexora Futures calcula planes experimentales de riesgo. No garantiza resultados, no custodia fondos y no ejecuta operaciones.',
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
    _refreshTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
