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
  final _symbolController = TextEditingController(text: 'BTCUSDT');
  Timer? _clock;
  Timer? _refreshTimer;
  Timer? _syncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime? _roundStart;
  DateTime? _roundEnd;
  PulseSignal? _signal;
  PulseAiConsensus? _aiSignal;
  bool _loading = true;
  String? _error;
  double? _startPrice;
  double? _lastPrice;

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
      if (!mounted) return;
      final end = _roundEnd;
      if (end != null && !_binanceNow.isBefore(end)) {
        _startCurrentRound();
      } else {
        setState(() {});
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
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _startCurrentRound() async {
    final now = _binanceNow;
    final minuteBucket = (now.minute ~/ 5) * 5;
    final start = DateTime.utc(now.year, now.month, now.day, now.hour, minuteBucket);
    _roundStart = start;
    _roundEnd = start.add(const Duration(minutes: 5));
    _startPrice = null;
    _aiSignal = null;
    await _load();
  }

  Future<void> _load({bool silent = false}) async {
    final symbol = _symbolController.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final List<Candle> candles =
          await _service.loadCandles(symbol, '1m', limit: 40);
      final depth = await _service.loadDepthVolume(symbol, limit: 100);

      final start = _roundStart;
      double? startPrice = _startPrice;
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

      final currentPrice = candles.last.close;
      PulseAiConsensus? aiSignal;
      if (startPrice != null && _roundEnd != null) {
        aiSignal = await _ai.evaluate(
          symbol: symbol,
          startPrice: startPrice,
          currentPrice: currentPrice,
          secondsRemaining: secondsRemaining,
          quantitative: signal,
        );
      }

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _aiSignal = aiSignal;
        _startPrice = startPrice;
        _lastPrice = currentPrice;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar Pulse con Binance. $error';
      });
    }
  }

  PulseDirection get _consensusDirection {
    final q = _signal;
    final ai = _aiSignal;
    if (q == null) return PulseDirection.noTrade;
    if (q.stability == MarketStability.veryUnstable) {
      return PulseDirection.noTrade;
    }
    if (ai == null) return q.direction;
    if (q.direction == PulseDirection.noTrade ||
        ai.direction == PulseDirection.noTrade) {
      return PulseDirection.noTrade;
    }
    if (q.direction != ai.direction) return PulseDirection.noTrade;
    return q.direction;
  }

  double get _consensusConfidence {
    final q = _signal;
    if (q == null) return 50;
    final ai = _aiSignal;
    if (ai == null) return q.confidence;
    if (_consensusDirection == PulseDirection.noTrade) {
      return ((q.confidence + ai.confidence) / 2)
          .clamp(50.0, 70.0)
          .toDouble();
    }
    return (q.confidence * 0.65 + ai.confidence * 0.35 + 3)
        .clamp(50.0, 90.0)
        .toDouble();
  }

  String get _consensusLabel => switch (_consensusDirection) {
        PulseDirection.up => 'SUBE',
        PulseDirection.down => 'BAJA',
        PulseDirection.noTrade => 'NO TRADE',
      };

  String get _countdown {
    final end = _roundEnd;
    if (end == null) return '--:--';
    final remaining = end.difference(_binanceNow);
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safe.inMinutes.toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _time(DateTime? value) {
    if (value == null) return '--:--';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  double? get _priceDelta => _startPrice == null || _lastPrice == null
      ? null
      : _lastPrice! - _startPrice!;

  double? get _priceDeltaPct => _startPrice == null || _priceDelta == null
      ? null
      : (_priceDelta! / _startPrice!) * 100;

  String get _currentSide {
    final delta = _priceDelta;
    if (delta == null) return 'SIN REFERENCIA';
    if (delta > 0) return 'UP ↑';
    if (delta < 0) return 'DOWN ↓';
    return 'EN PRECIO INICIAL';
  }

  @override
  Widget build(BuildContext context) {
    final signal = _signal;
    final aiSignal = _aiSignal;
    final delta = _priceDelta;
    final deltaPct = _priceDeltaPct;

    return Scaffold(
      appBar: AppBar(title: const Text('Nexora Pulse · BTC Up/Down 5m')),
      body: RefreshIndicator(
        onRefresh: _startCurrentRound,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Analiza rondas de 5 minutos alineadas con el reloj de Binance. Nexora no ejecuta órdenes ni garantiza el resultado de la ronda.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _symbolController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Par de Binance',
                hintText: 'BTCUSDT',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _startCurrentRound(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _startCurrentRound,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar ronda con Binance'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text('Ronda ${_time(_roundStart)} → ${_time(_roundEnd)}'),
                    const SizedBox(height: 10),
                    Text(
                      _countdown,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('cuenta regresiva sincronizada con Binance'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentSide,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Precio inicial: ${_startPrice?.toStringAsFixed(2) ?? 'cargando…'}',
                    ),
                    Text(
                      'Precio actual: ${_lastPrice?.toStringAsFixed(2) ?? 'cargando…'}',
                    ),
                    if (delta != null && deltaPct != null)
                      Text(
                        'Distancia: ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} '
                        '(${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(3)}%)',
                      ),
                  ],
                ),
              ),
            ),
            if (_loading && signal == null)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && signal == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_error!),
                ),
              )
            else if (signal != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(
                    signal.stability == MarketStability.stable
                        ? Icons.check_circle_outline
                        : signal.stability == MarketStability.unstable
                            ? Icons.warning_amber_rounded
                            : Icons.report_gmailerrorred,
                  ),
                  title: Text(
                    'Mercado ${signal.stabilityLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    signal.stability == MarketStability.stable
                        ? 'Las condiciones actuales tienen un nivel de ruido controlado.'
                        : signal.stability == MarketStability.unstable
                            ? 'Hay volatilidad, cambios de dirección o señales en conflicto. Opera con cautela.'
                            : 'Ruido y volatilidad elevados. Nexora bloquea UP/DOWN y recomienda NO TRADE.',
                  ),
                  trailing: Text(
                    '${signal.instabilityScore.toStringAsFixed(0)}/100',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'CONSENSO NEXORA',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _consensusLabel,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _consensusConfidence / 100,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Confianza combinada: ${_consensusConfidence.toStringAsFixed(0)}%',
                      ),
                      Text(
                        'Motor cuantitativo: ${signal.directionLabel} · ${signal.confidence.toStringAsFixed(0)}%',
                      ),
                      Text(
                        aiSignal == null
                            ? (_ai.isConfigured
                                ? 'IA: no disponible en esta actualización'
                                : 'IA opcional no configurada; usando solo motor local')
                            : 'IA ${aiSignal.provider}: ${aiSignal.direction.name.toUpperCase()} · ${aiSignal.confidence.toStringAsFixed(0)}%',
                      ),
                    ],
                  ),
                ),
              ),
              if (aiSignal != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Segunda opinión de IA',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(aiSignal.explanation),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Momentum',
                      value: signal.momentumScore,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(
                      label: 'Tendencia',
                      value: signal.trendScore,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Order book',
                      value: signal.orderBookImbalance,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(
                      label: 'Presión vela',
                      value: signal.bodyPressure,
                    ),
                  ),
                ],
              ),
              Card(
                child: ListTile(
                  title: const Text('Volumen reciente / referencia'),
                  trailing: Text('${signal.volumeRatio.toStringAsFixed(2)}x'),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¿Por qué?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...signal.reasons.map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $reason'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Si la IA y el motor cuantitativo discrepan, Nexora fuerza NO TRADE. '
                'Si el mercado es muy inestable, Nexora también bloquea UP/DOWN. '
                'La IA interpreta datos estructurados; no inventa precios ni noticias.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
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
    _symbolController.dispose();
    super.dispose();
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
}
