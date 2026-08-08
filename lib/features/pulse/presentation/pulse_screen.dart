import 'dart:async';

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../data/pulse_ai_service.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_engine.dart';
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

    // 250 ms refresh keeps the displayed second aligned to the exchange clock
    // instead of drifting with a one-second periodic timer.
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

    // Re-sample Binance frequently. The offset calculation compensates for
    // half the network round-trip time, giving a much tighter clock estimate.
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

      // Smooth tiny network-jitter changes, but correct large clock errors
      // immediately.
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
      // Preserve the last valid synchronization when the network is transient.
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
      // A longer return history makes volatility/drift estimates less fragile
      // while PulseEngine continues to use its most recent 30 candles.
      final List<Candle> candles =
          await _service.loadCandles('BTCUSDT', '1m', limit: 90);
      final depth = await _service.loadDepthVolume('BTCUSDT', limit: 100);

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
      }

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

  double get _fusedProbabilityUp {
    final calibrated = _mathPrediction;
    final statistical = _statPrediction;
    if (calibrated == null && statistical == null) return .5;

    final signal = _signal;
    final instability = signal?.instabilityScore ?? 50;
    final statQuality = statistical?.signalQuality ?? 0;

    // Statistical evidence receives the highest weight. The original
    // calibrated technical model remains an independent second estimator.
    var statWeight = statistical == null ? 0.0 : (.52 + statQuality * .18);
    var mathWeight = calibrated == null ? 0.0 : .32;

    // Generative AI is only a small contextual reviewer; it must never dominate
    // a five-minute numerical forecast.
    var aiWeight = 0.0;
    var aiProbability = .5;
    final ai = _aiPrediction;
    if (ai != null && ai.direction != PulseDirection.noTrade) {
      aiWeight = (.10 * (1 - instability / 120)).clamp(.02, .10).toDouble();
      aiProbability = ai.direction == PulseDirection.up
          ? ai.confidence / 100
          : 1 - ai.confidence / 100;
    }

    // In very unstable markets reduce every directional edge toward 50%.
    final total = statWeight + mathWeight + aiWeight;
    if (total <= 0) return .5;
    var p = ((statistical?.probabilityUp ?? .5) * statWeight +
            (calibrated?.probabilityUp ?? .5) * mathWeight +
            aiProbability * aiWeight) /
        total;

    final stabilityShrink = (1 - instability / 155).clamp(.35, 1.0).toDouble();
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
                      const Text(
                        'TIEMPO RESTANTE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _countdown,
                        style: const TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'PREDICCIÓN BTC',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      if (_loading && _signal == null)
                        const CircularProgressIndicator()
                      else ...[
                        Text(
                          _directionLabel,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${_confidence.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statPrediction == null
                              ? 'calibrando datos'
                              : 'probabilidad estadística fusionada',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insights),
                  title: Text(
                    _marketLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'La confianza baja automáticamente cuando la volatilidad, el ruido o la contradicción entre señales aumentan.',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Modelo experimental: retornos logarítmicos, volatilidad EWMA, dependencia serial, difusión del precio, microestructura, calibración técnica y revisión secundaria de IA. Debe validarse con rondas cerradas; no garantiza resultados.',
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
