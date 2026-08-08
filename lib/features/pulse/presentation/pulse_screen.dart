import 'dart:async';
import 'package:flutter/material.dart';
import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
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
  final _symbolController = TextEditingController(text: 'BTCUSDT');
  Timer? _clock;
  Timer? _refreshTimer;
  Timer? _serverSyncTimer;
  Duration _binanceOffset = Duration.zero;
  DateTime _windowStart = DateTime.now().toUtc();
  DateTime _windowEnd = DateTime.now().toUtc().add(const Duration(minutes: 4));
  PulseSignal? _signal;
  bool _loading = true;
  bool _clockSynced = false;
  String? _error;
  double? _lastPrice;

  DateTime get _binanceNow => DateTime.now().toUtc().add(_binanceOffset);

  @override
  void initState() {
    super.initState();
    _initialize();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = _binanceNow;
      if (!now.isBefore(_windowEnd)) {
        _alignWindow(now);
        _load(silent: true);
      }
      setState(() {});
    });
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
    _serverSyncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncBinanceClock(silent: true),
    );
  }

  Future<void> _initialize() async {
    await _syncBinanceClock();
    await _load();
  }

  Future<void> _syncBinanceClock({bool silent = false}) async {
    try {
      final before = DateTime.now().toUtc();
      final serverTime = await _service.loadServerTime();
      final after = DateTime.now().toUtc();
      final midpoint = before.add(after.difference(before) ~/ 2);
      final offset = serverTime.difference(midpoint);
      final adjustedNow = DateTime.now().toUtc().add(offset);

      if (!mounted) return;
      setState(() {
        _binanceOffset = offset;
        _clockSynced = true;
        _alignWindow(adjustedNow);
      });
    } catch (error) {
      if (!mounted || silent) return;
      setState(() {
        _clockSynced = false;
        _error = 'No se pudo sincronizar la hora con Binance. $error';
      });
    }
  }

  void _alignWindow(DateTime binanceNow) {
    const windowMs = 4 * 60 * 1000;
    final nowMs = binanceNow.millisecondsSinceEpoch;
    final startMs = (nowMs ~/ windowMs) * windowMs;
    _windowStart = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    _windowEnd = DateTime.fromMillisecondsSinceEpoch(startMs + windowMs, isUtc: true);
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
      final signal = _engine.analyze(
        candles: candles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
      );

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _lastPrice = candles.last.close;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo calcular Pulse. $error';
      });
    }
  }

  String get _countdown {
    final remaining = _windowEnd.difference(_binanceNow);
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _windowLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    final start = _windowStart.toLocal();
    final end = _windowEnd.toLocal();
    return '${two(start.hour)}:${two(start.minute)} – ${two(end.hour)}:${two(end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final signal = _signal;
    return Scaffold(
      appBar: AppBar(title: const Text('Nexora Pulse · 4 min')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _syncBinanceClock(silent: true);
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Módulo experimental de lectura direccional de muy corto plazo. La confianza es del modelo, no una probabilidad garantizada de acierto.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _clockSynced ? Icons.cloud_done_outlined : Icons.schedule_outlined,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _clockSynced
                        ? 'Temporizador sincronizado con la hora del servidor de Binance.'
                        : 'Usando reloj local mientras se intenta sincronizar con Binance.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
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
              onSubmitted: (_) async {
                await _syncBinanceClock(silent: true);
                await _load();
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await _syncBinanceClock(silent: true);
                await _load();
              },
              icon: const Icon(Icons.sync),
              label: const Text('Actualizar con Binance'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      _countdown,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('tiempo real restante de la ventana'),
                    const SizedBox(height: 6),
                    Text(
                      'Ventana: $_windowLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading && signal == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(36),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null && signal == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_error!),
                ),
              )
            else if (signal != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        signal.directionLabel,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_lastPrice != null)
                        Text(
                          'Precio de referencia: ${_lastPrice!.toStringAsFixed(6)}',
                        ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: signal.confidence / 100),
                      const SizedBox(height: 8),
                      Text(
                        'Confianza del modelo: ${signal.confidence.toStringAsFixed(0)}%',
                      ),
                      Text('Score Pulse: ${signal.score.toStringAsFixed(1)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                'NO TRADE significa que Nexora no detecta suficiente calidad para emitir una dirección. En ventanas tan cortas, abstenerse puede ser una mejor decisión que forzar una señal.',
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
    _serverSyncTimer?.cancel();
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
