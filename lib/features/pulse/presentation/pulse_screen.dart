import 'dart:async';
import 'package:flutter/material.dart';
import '../../market/data/binance_market_service.dart';
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
  DateTime _windowEnd = DateTime.now().add(const Duration(minutes: 4));
  PulseSignal? _signal;
  bool _loading = true;
  String? _error;
  double? _lastPrice;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_windowEnd)) {
        _windowEnd = DateTime.now().add(const Duration(minutes: 4));
        _load();
      }
      setState(() {});
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    final symbol = _symbolController.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        _service.loadCandles(symbol, '1m', limit: 40),
        _service.loadDepthVolume(symbol, limit: 100),
      ]);
      final candles = results[0] as List;
      final depth = results[1] as ({double bidVolume, double askVolume});
      final typedCandles = candles.cast();
      final signal = _engine.analyze(
        candles: typedCandles,
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
      );
      if (!mounted) return;
      setState(() {
        _signal = signal;
        _lastPrice = typedCandles.last.close;
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
    final remaining = _windowEnd.difference(DateTime.now());
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final signal = _signal;
    return Scaffold(
      appBar: AppBar(title: const Text('Nexora Pulse · 4 min')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Módulo experimental de lectura direccional de muy corto plazo. La confianza es del modelo, no una probabilidad garantizada de acierto.',
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
              onSubmitted: (_) {
                _windowEnd = DateTime.now().add(const Duration(minutes: 4));
                _load();
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                _windowEnd = DateTime.now().add(const Duration(minutes: 4));
                _load();
              },
              icon: const Icon(Icons.bolt),
              label: const Text('Iniciar nueva ventana de 4 min'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(_countdown, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
                    const Text('tiempo restante de la ventana'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading && signal == null)
              const Center(child: Padding(padding: EdgeInsets.all(36), child: CircularProgressIndicator()))
            else if (_error != null && signal == null)
              Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(_error!)))
            else if (signal != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        signal.directionLabel,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      if (_lastPrice != null) Text('Precio de referencia: ${_lastPrice!.toStringAsFixed(6)}'),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: signal.confidence / 100),
                      const SizedBox(height: 8),
                      Text('Confianza del modelo: ${signal.confidence.toStringAsFixed(0)}%'),
                      Text('Score Pulse: ${signal.score.toStringAsFixed(1)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Metric(label: 'Momentum', value: signal.momentumScore)),
                  const SizedBox(width: 8),
                  Expanded(child: _Metric(label: 'Tendencia', value: signal.trendScore)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _Metric(label: 'Order book', value: signal.orderBookImbalance)),
                  const SizedBox(width: 8),
                  Expanded(child: _Metric(label: 'Presión vela', value: signal.bodyPressure)),
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
                      const Text('¿Por qué?', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...signal.reasons.map((reason) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• $reason'),
                          )),
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
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
}
