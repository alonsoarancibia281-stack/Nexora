import 'dart:async';

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../data/pulse_ai_service.dart';
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_signal.dart';

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen> {
  final _service = BinanceMarketService();
  final _engine = const PulseEngine();
  final _ai = const PulseAiService();

  Timer? _clock;
  Timer? _refreshTimer;
  Timer? _syncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime? _roundStart;
  DateTime? _roundEnd;
  PulseSignal? _signal;
  PulseAiConsensus? _unifiedPrediction;
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
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _roundEnd;
      if (end != null && !_binanceNow.isBefore(end)) {
        _startCurrentRound();
      }
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
    _syncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncBinanceClock(),
    );
  }

  Future<void> _syncBinanceClock() async {
    try {
      final serverTime = await _service.loadServerTime();
      _binanceOffset = serverTime.difference(DateTime.now().toUtc());
    } catch (_) {
      // Mantiene la última sincronización válida.
    }
  }

  Future<void> _startCurrentRound() async {
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
    _unifiedPrediction = null;
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
      final List<Candle> candles =
          await _service.loadCandles('BTCUSDT', '1m', limit: 40);
      final depth = await _service.loadDepthVolume('BTCUSDT', limit: 100);

      double? startPrice = _startPrice;
      final start = _roundStart;
      if (start != null) {
        for (final candle in candles.reversed) {
          if (candle.openTime.toUtc().millisecondsSinceEpoch ==
              start.millisecondsSinceEpoch) {
            startPrice = candle.open;
            break;
          }
        }
      }

      final secondsRemaining = _roundEnd == null
          ? 300
          : _roundEnd!.difference(_binanceNow).inSeconds.clamp(0, 300);

      final signal = _engine.analyze(
        candles: candles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
        roundStartPrice: startPrice,
        secondsRemaining: secondsRemaining,
      );

      PulseAiConsensus? prediction;
      if (startPrice != null) {
        prediction = await _ai.evaluate(
          symbol: 'BTCUSDT',
          startPrice: startPrice,
          currentPrice: candles.last.close,
          secondsRemaining: secondsRemaining,
          quantitative: signal,
        );
      }

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _unifiedPrediction = prediction;
        _startPrice = startPrice;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar Predicciones minutos BTC.';
      });
    }
  }

  PulseDirection get _direction {
    final prediction = _unifiedPrediction;
    if (prediction != null && prediction.direction != PulseDirection.noTrade) {
      return prediction.direction;
    }
    final signal = _signal;
    if (signal == null) return PulseDirection.noTrade;
    return signal.score >= 0 ? PulseDirection.up : PulseDirection.down;
  }

  double get _confidence {
    final prediction = _unifiedPrediction;
    if (prediction != null) {
      return prediction.confidence.clamp(50.0, 88.0).toDouble();
    }
    final signal = _signal;
    if (signal == null) return 50;
    var value = signal.confidence;
    if (signal.stability == MarketStability.unstable) value -= 7;
    if (signal.stability == MarketStability.veryUnstable) value -= 14;
    return value.clamp(50.0, 82.0).toDouble();
  }

  String get _directionLabel => switch (_direction) {
        PulseDirection.up => 'ALTA ↑',
        PulseDirection.down => 'BAJA ↓',
        PulseDirection.noTrade => 'CALCULANDO',
      };

  String get _marketLabel {
    final signal = _signal;
    if (signal == null) return 'Analizando mercado';
    return switch (signal.stability) {
      MarketStability.stable => 'Mercado estable',
      MarketStability.unstable => 'Mercado inestable',
      MarketStability.veryUnstable => 'Mercado muy inestable',
    };
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _unifiedPrediction;

    return Scaffold(
      appBar: AppBar(title: const Text('Predicciones minutos BTC')),
      body: RefreshIndicator(
        onRefresh: _startCurrentRound,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Motor único para estimar la dirección probable de Bitcoin al cierre de la ronda de cinco minutos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
                        '${_confidence.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('confianza del motor único'),
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
                  'La confianza se reduce automáticamente cuando aumenta el ruido o las señales se contradicen.',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'El motor fusiona datos de Binance, patrones de velas, volumen, volatilidad, libro de órdenes, referencias de otros exchanges, noticias recientes sobre Bitcoin, Gemini y OpenCode en una sola salida.',
                ),
              ),
            ),
            if (prediction != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(prediction.explanation),
                ),
              ),
            ],
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
              'La lectura es probabilística y puede cambiar durante la ronda. No constituye una garantía de resultado ni una recomendación financiera.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _refreshTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
