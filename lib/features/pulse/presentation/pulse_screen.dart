import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../data/pulse_ai_service.dart';
import '../domain/btc_5m_logistic_model.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_probability_calibrator.dart';
import '../domain/pulse_signal.dart';
import '../domain/pulse_statistical_engine.dart';

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen> {
  final _service = BinanceMarketService();
  final _engine = const PulseEngine();
  final _ai = const PulseAiService();
  final _calibrator = const PulseProbabilityCalibrator();
  final _statistical = const PulseStatisticalEngine();
  final _logistic5m = const Btc5mLogisticModel();
  final _ensemble100 = const PulseEnsemble100();

  Timer? _clock;
  Timer? _refreshTimer;
  Timer? _syncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime? _roundStart;
  DateTime? _roundEnd;
  PulseSignal? _signal;
  PulseAiConsensus? _aiPrediction;
  PulseProbabilityResult? _mathPrediction;
  PulseStatisticalResult? _statPrediction;
  Btc5mLogisticResult? _logisticPrediction;
  PulseEnsemble100Result? _ensemblePrediction;
  bool _loading = true;
  String? _error;
  double? _startPrice;

  DateTime get _binanceNow => DateTime.now().toUtc().add(_binanceOffset);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _syncBinanceClock();
    await _startCurrentRound();

    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final end = _roundEnd;
      if (end != null && !_binanceNow.isBefore(end)) {
        _startCurrentRound();
      } else {
        setState(() {});
      }
    });

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(silent: true),
    );

    _syncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncBinanceClock(),
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
      if (deltaMs > 1500 || _binanceOffset == Duration.zero) {
        _binanceOffset = measuredOffset;
      } else {
        _binanceOffset = Duration(
          microseconds: ((_binanceOffset.inMicroseconds * 0.65) +
                  (measuredOffset.inMicroseconds * 0.35))
              .round(),
        );
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Preserve last valid exchange-clock synchronization.
    }
  }

  Future<void> _startCurrentRound() async {
    await _syncBinanceClock();
    final now = _binanceNow;
    final minuteBucket = (now.minute ~/ 5) * 5;
    _roundStart = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      minuteBucket,
    );
    _roundEnd = _roundStart!.add(const Duration(minutes: 5));
    _startPrice = null;
    _aiPrediction = null;
    _mathPrediction = null;
    _statPrediction = null;
    _logisticPrediction = null;
    _ensemblePrediction = null;
    if (mounted) setState(() {});
    await _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _service.loadCandles('BTCUSDT', '1m', limit: 90),
        _service.loadCandles('BTCUSDT', '5m', limit: 40),
        _service.loadDepthMetrics('BTCUSDT', limit: 100),
        _service.loadAggTradeMetrics('BTCUSDT', limit: 500),
      ]);
      final List<Candle> candles = results[0] as List<Candle>;
      final List<Candle> fiveMinuteCandles = results[1] as List<Candle>;
      final depth = results[2] as ({
        double bidVolume,
        double askVolume,
        double bestBid,
        double bestAsk,
        double spreadBps,
        double micropriceEdge,
      });
      final trades = results[3] as ({
        double aggressorImbalance,
        double signedVolume,
        double tradeAcceleration,
        double priceImpulseBps,
        int trades,
      });

      double? startPrice = _startPrice;
      final start = _roundStart;
      if (start != null) {
        for (final c in candles.reversed) {
          if (c.openTime.toUtc().millisecondsSinceEpoch ==
              start.millisecondsSinceEpoch) {
            startPrice = c.open;
            break;
          }
        }
      }

      final seconds = _roundEnd == null
          ? 300
          : (_roundEnd!.difference(_binanceNow).inMilliseconds / 1000)
              .ceil()
              .clamp(0, 300);

      final signal = _engine.analyze(
        candles: candles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
        roundStartPrice: startPrice,
        secondsRemaining: seconds,
      );

      PulseProbabilityResult? mathPrediction;
      PulseStatisticalResult? statPrediction;
      PulseEnsemble100Result? ensemblePrediction;
      if (startPrice != null) {
        mathPrediction = _calibrator.calibrate(
          score: signal.score,
          instability: signal.instabilityScore,
          agreement: signal.agreementRatio,
          roundDistancePct: signal.roundDistancePct,
          expectedRemainingMovePct: signal.expectedRemainingMovePct,
          secondsRemaining: seconds,
        );
        statPrediction = _statistical.analyze(
          candles: candles,
          bidVolume: depth.bidVolume,
          askVolume: depth.askVolume,
          roundStartPrice: startPrice,
          secondsRemaining: seconds,
        );
        ensemblePrediction = _ensemble100.analyze(
          _buildAnalystInput(
            candles: candles,
            signal: signal,
            stat: statPrediction,
            startPrice: startPrice,
            secondsRemaining: seconds,
            bidVolume: depth.bidVolume,
            askVolume: depth.askVolume,
            spreadBps: depth.spreadBps,
            micropriceEdge: depth.micropriceEdge,
            aggressorImbalance: trades.aggressorImbalance,
            signedVolume: trades.signedVolume,
            tradeAcceleration: trades.tradeAcceleration,
            priceImpulseBps: trades.priceImpulseBps,
          ),
        );
      }

      final completed5m = start == null
          ? <Candle>[]
          : fiveMinuteCandles
              .where((c) => c.openTime.toUtc().isBefore(start))
              .toList(growable: false);
      final logisticPrediction = _logistic5m.analyze(completed5m);

      PulseAiConsensus? aiPrediction;
      if (startPrice != null) {
        aiPrediction = await _ai.evaluate(
          symbol: 'BTCUSDT',
          startPrice: startPrice,
          currentPrice: candles.last.close,
          secondsRemaining: seconds,
          quantitative: signal,
        );
      }

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _mathPrediction = mathPrediction;
        _statPrediction = statPrediction;
        _logisticPrediction = logisticPrediction;
        _ensemblePrediction = ensemblePrediction;
        _aiPrediction = aiPrediction;
        _startPrice = startPrice;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar Predicciones minutos BTC.';
      });
    }
  }

  AnalystInput _buildAnalystInput({
    required List<Candle> candles,
    required PulseSignal signal,
    required PulseStatisticalResult stat,
    required double startPrice,
    required int secondsRemaining,
    required double bidVolume,
    required double askVolume,
    required double spreadBps,
    required double micropriceEdge,
    required double aggressorImbalance,
    required double signedVolume,
    required double tradeAcceleration,
    required double priceImpulseBps,
  }) {
    double norm(double v, double scale) =>
        scale == 0 ? 0 : (v / scale).clamp(-1.0, 1.0).toDouble();
    final closes = candles.map((c) => c.close).toList(growable: false);
    final current = closes.last;
    final shortReturn = closes.length < 4
        ? 0.0
        : ((current - closes[closes.length - 4]) / closes[closes.length - 4]) * 100;
    final prevReturn = closes.length < 7
        ? 0.0
        : ((closes[closes.length - 4] - closes[closes.length - 7]) /
                closes[closes.length - 7]) *
            100;
    final acceleration = shortReturn - prevReturn;
    final recent = candles.sublist(math.max(0, candles.length - 20));
    final mean = recent.map((c) => c.close).reduce((a, b) => a + b) / recent.length;
    final variance = recent
            .map((c) => math.pow(c.close - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        recent.length;
    final sigma = math.sqrt(variance);
    final zPrice = sigma <= 0 ? 0.0 : ((current - mean) / sigma).clamp(-3.0, 3.0) / 3.0;
    final bookTotal = bidVolume + askVolume;
    final bookImbalance = bookTotal <= 0 ? 0.0 : (bidVolume - askVolume) / bookTotal;
    final roundEdge = ((current - startPrice) / startPrice * 100);
    final bodyPressure = signal.bodyPressure / 100;
    final trend = signal.trendScore / 100;
    final momentum = signal.momentumScore / 100;
    final vol = stat.ewmaVolatilityPerMinute;
    final rangeRecent = recent.map((c) => c.high - c.low).toList();
    final avgRange = rangeRecent.reduce((a, b) => a + b) / rangeRecent.length;
    final lastRange = candles.last.high - candles.last.low;
    final rangeExpansion = avgRange <= 0 ? 0.0 : ((lastRange / avgRange) - 1).clamp(-1.0, 1.0).toDouble();
    final directionPersistence = stat.autocorrelation.clamp(-1.0, 1.0).toDouble();

    return AnalystInput(
      instability: signal.instabilityScore,
      secondsRemaining: secondsRemaining,
      features: {
        'momentum': momentum,
        'acceleration': norm(acceleration, .18),
        'shortReturn': norm(shortReturn, .30),
        'trend': trend,
        'emaSpread': trend,
        'slope': norm(stat.driftPerMinute * 100, .05),
        'volatilityBreakout': norm(priceImpulseBps, 8),
        'atrExpansion': rangeExpansion,
        'rangeExpansion': rangeExpansion,
        'zPrice': zPrice,
        'rsiExtreme': 0,
        'vwapDistance': norm(roundEdge, .35),
        'bookImbalance': bookImbalance.clamp(-1.0, 1.0).toDouble(),
        'micropriceEdge': norm(micropriceEdge, 2.0),
        'spreadPressure': -norm(spreadBps, 3.0),
        'aggressorImbalance': aggressorImbalance,
        'tradeAcceleration': tradeAcceleration * aggressorImbalance.sign,
        'signedVolume': signedVolume,
        'volumeZ': norm(signal.volumeRatio - 1, 1.5),
        'obvSlope': signedVolume,
        'volumePriceAgreement': signedVolume * momentum.sign,
        'bodyPressure': bodyPressure,
        'breakoutQuality': norm(priceImpulseBps, 10),
        'wickBias': bodyPressure,
        'ethConfirmation': 0,
        'exchangeConsensus': 0,
        'betaResidual': 0,
        'regimeTrend': trend,
        'regimePersistence': directionPersistence,
        'roundEdge': norm(roundEdge, math.max(signal.expectedRemainingMovePct, .05)),
        'rawVolatility': vol,
      },
    );
  }

  double get _fusedProbabilityUp {
    final calibrated = _mathPrediction;
    final statistical = _statPrediction;
    final logistic = _logisticPrediction;
    final ensemble = _ensemblePrediction;
    if (calibrated == null && statistical == null && logistic == null && ensemble == null) return .5;

    final signal = _signal;
    final instability = signal?.instabilityScore ?? 50;
    final statQuality = statistical?.signalQuality ?? 0;

    var ensembleWeight = ensemble == null ? 0.0 : (.42 + ensemble.agreement * .18);
    var statWeight = statistical == null ? 0.0 : (.32 + statQuality * .12);
    var mathWeight = calibrated == null ? 0.0 : .18;

    var logisticWeight = 0.0;
    if (logistic != null && logistic.isReady) {
      final evidence = ((logistic.probabilityUp - .5).abs() * 2)
          .clamp(0.0, 1.0)
          .toDouble();
      logisticWeight = .05 + evidence * .03;
    }

    var aiWeight = 0.0;
    var aiProbability = .5;
    final ai = _aiPrediction;
    if (ai != null && ai.direction != PulseDirection.noTrade) {
      aiWeight = (.05 * (1 - instability / 120)).clamp(.01, .05).toDouble();
      aiProbability = ai.direction == PulseDirection.up
          ? ai.confidence / 100
          : 1 - ai.confidence / 100;
    }

    final total = ensembleWeight + statWeight + mathWeight + logisticWeight + aiWeight;
    if (total <= 0) return .5;
    var p = ((ensemble?.probabilityUp ?? .5) * ensembleWeight +
            (statistical?.probabilityUp ?? .5) * statWeight +
            (calibrated?.probabilityUp ?? .5) * mathWeight +
            (logistic?.probabilityUp ?? .5) * logisticWeight +
            aiProbability * aiWeight) /
        total;

    final stabilityShrink = (1 - instability / 165).clamp(.40, 1.0).toDouble();
    p = .5 + (p - .5) * stabilityShrink;
    return p.clamp(.08, .92).toDouble();
  }

  PulseDirection get _direction =>
      _fusedProbabilityUp >= .5 ? PulseDirection.up : PulseDirection.down;

  double get _confidence =>
      ((_fusedProbabilityUp - .5).abs() + .5) * 100;

  String get _directionLabel =>
      _direction == PulseDirection.up ? 'ALTA ↑' : 'BAJA ↓';

  String get _marketLabel {
    final s = _signal;
    if (s == null) return 'Analizando mercado';
    return s.stability == MarketStability.stable
        ? 'Mercado estable'
        : s.stability == MarketStability.unstable
            ? 'Mercado inestable'
            : 'Mercado muy inestable';
  }

  Duration get _remaining {
    final end = _roundEnd;
    if (end == null) return Duration.zero;
    final value = end.difference(_binanceNow);
    return value.isNegative ? Duration.zero : value;
  }

  int get _remainingSeconds {
    final ms = _remaining.inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  String get _countdown {
    final totalSeconds = _remainingSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double get _roundProgress =>
      ((300 - _remaining.inMilliseconds / 1000) / 300)
          .clamp(0.0, 1.0)
          .toDouble();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Predicciones minutos BTC')),
        body: RefreshIndicator(
          onRefresh: _startCurrentRound,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Predicción estadística de la dirección probable de Bitcoin al cierre de cada ronda de cinco minutos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('TIEMPO RESTANTE', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_countdown, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _roundProgress),
                      const SizedBox(height: 8),
                      const Text('sincronización frecuente con servidor Binance'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    children: [
                      const Text('PREDICCIÓN BTC', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),
                      if (_loading && _signal == null)
                        const CircularProgressIndicator()
                      else ...[
                        Text(_directionLabel, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 18),
                        Text('${_confidence.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_ensemblePrediction == null
                            ? 'calibrando 100 analistas'
                            : '100 analistas · ${(100 * _ensemblePrediction!.agreement).toStringAsFixed(0)}% de acuerdo'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insights),
                  title: Text(_marketLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                    'Los 100 analistas comparan momentum, tendencia, volatilidad, microestructura, flujo de trades, volumen, price action y régimen antes del consenso final.',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 18),
              const Text(
                'Modelo experimental: ensemble jerárquico de 100 analistas + microestructura Binance + aggTrades + motor estadístico + regresión logística BTC 5m + calibración + revisión secundaria de IA. No garantiza resultados.',
                textAlign: TextAlign.center,
              ),
            ],
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
