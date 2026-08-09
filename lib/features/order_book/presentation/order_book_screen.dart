import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../market/domain/candle.dart';
import '../../market/widgets/candlestick_chart.dart';
import '../data/binance_order_book_service.dart';
import '../domain/order_book_parser.dart';
import '../domain/order_book_prediction.dart';
import '../domain/order_book_prediction_engine.dart';
import '../domain/order_book_snapshot.dart';

enum _BookSource { live, pasted }

class OrderBookScreen extends StatefulWidget {
  const OrderBookScreen({super.key});

  @override
  State<OrderBookScreen> createState() => _OrderBookScreenState();
}

class _OrderBookScreenState extends State<OrderBookScreen> {
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _pasted = TextEditingController();
  final _service = const BinanceOrderBookService();
  final _parser = const OrderBookParser();
  final _engine = const OrderBookPredictionEngine();

  _BookSource _source = _BookSource.live;
  late Stream<OrderBookSnapshot> _stream;
  StreamSubscription<Candle>? _candleSubscription;
  List<Candle> _candles = const [];
  String _interval = '1m';
  bool _candlesLoading = true;
  String? _candlesError;
  int _candleRequest = 0;
  OrderBookSnapshot? _visibleSnapshot;
  OrderBookSnapshot? _pastedSnapshot;
  String? _pasteError;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _candleSubscription?.cancel();
    _symbol.dispose();
    _pasted.dispose();
    super.dispose();
  }

  void _connect() {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    setState(() {
      _stream = _service.liveDepth(symbol);
      _visibleSnapshot = null;
    });
    _connectCandles(symbol);
  }

  Future<void> _connectCandles(String symbol) async {
    final request = ++_candleRequest;
    await _candleSubscription?.cancel();
    if (mounted) {
      setState(() {
        _candlesLoading = true;
        _candlesError = null;
      });
    }
    try {
      final history = await _service.loadCandles(symbol, _interval, limit: 60);
      if (!mounted || request != _candleRequest) return;
      setState(() {
        _candles = history;
        _candlesLoading = false;
      });
      _candleSubscription = _service.liveCandles(symbol, _interval).listen(
            _mergeCandle,
          );
    } catch (_) {
      if (!mounted || request != _candleRequest) return;
      setState(() {
        _candlesLoading = false;
        _candlesError = 'No se pudieron cargar las velas de Binance.';
      });
    }
  }

  void _mergeCandle(Candle candle) {
    if (!mounted) return;
    final next = List<Candle>.of(_candles);
    final index = next.indexWhere(
      (item) =>
          item.openTime.millisecondsSinceEpoch ==
          candle.openTime.millisecondsSinceEpoch,
    );
    if (index >= 0) {
      next[index] = candle;
    } else {
      next.add(candle);
    }
    if (next.length > 60) next.removeRange(0, next.length - 60);
    setState(() => _candles = List.unmodifiable(next));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text?) {
      _pasted.text = text;
      _analyzePasted();
    }
  }

  void _analyzePasted() {
    try {
      final snapshot = _parser.parse(
        _pasted.text,
        defaultSymbol: _symbol.text.trim().toUpperCase(),
      );
      setState(() {
        _pastedSnapshot = snapshot;
        _visibleSnapshot = snapshot;
        _pasteError = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _pastedSnapshot = null;
        _visibleSnapshot = null;
        _pasteError = error.message;
      });
    } catch (_) {
      setState(() {
        _pastedSnapshot = null;
        _visibleSnapshot = null;
        _pasteError = 'No pudimos interpretar esos datos.';
      });
    }
  }

  Future<void> _copySnapshot() async {
    final snapshot = _visibleSnapshot;
    if (snapshot == null) return;
    await Clipboard.setData(ClipboardData(text: snapshot.toClipboardText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snapshot copiado al portapapeles.')),
    );
  }

  @override
  Widget build(BuildContext context) => MainNavigationScaffold(
        currentIndex: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Flujo'),
            actions: [
              IconButton(
                tooltip: 'Copiar snapshot',
                onPressed: _visibleSnapshot == null ? null : _copySnapshot,
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Libro de ordenes',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Movimiento, velas y liquidez de corto plazo revisados por un pool de 100 analistas cuantitativos.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _symbol,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _connect(),
                decoration: InputDecoration(
                  labelText: 'Par de Binance',
                  hintText: 'BTCUSDT',
                  prefixIcon: const Icon(Icons.currency_bitcoin),
                  suffixIcon: IconButton(
                    tooltip: 'Conectar',
                    onPressed: _connect,
                    icon: const Icon(Icons.sync),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_BookSource>(
                segments: const [
                  ButtonSegment(
                    value: _BookSource.live,
                    icon: Icon(Icons.wifi),
                    label: Text('En vivo'),
                  ),
                  ButtonSegment(
                    value: _BookSource.pasted,
                    icon: Icon(Icons.content_paste),
                    label: Text('Pegar datos'),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (value) {
                  setState(() {
                    _source = value.first;
                    _visibleSnapshot =
                        _source == _BookSource.pasted ? _pastedSnapshot : null;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_source == _BookSource.live) _liveBook() else _pastePanel(),
            ],
          ),
        ),
      );

  Widget _liveBook() => StreamBuilder<OrderBookSnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _visibleSnapshot = snapshot.data;
            return _snapshotView(snapshot.data!, connected: true);
          }
          if (snapshot.hasError) {
            return const _MessagePanel(
              icon: Icons.cloud_off_outlined,
              message:
                  'No se pudo conectar con Binance. Revisa la red e intenta otra vez.',
            );
          }
          return const _MessagePanel(
            icon: Icons.sync,
            message: 'Conectando con el libro publico de Binance...',
            loading: true,
          );
        },
      );

  Widget _pastePanel() => Column(
        children: [
          TextField(
            controller: _pasted,
            minLines: 7,
            maxLines: 12,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Snapshot Nexora o JSON de Binance',
              hintText: 'VENTAS\n64916.00 0.25\nCOMPRAS\n64915.00 0.30',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Pegar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _analyzePasted,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Analizar'),
                ),
              ),
            ],
          ),
          if (_pasteError != null) ...[
            const SizedBox(height: 10),
            Text(
              _pasteError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_pastedSnapshot case final snapshot?) ...[
            const SizedBox(height: 16),
            _snapshotView(snapshot, connected: false),
          ],
        ],
      );

  Widget _snapshotView(OrderBookSnapshot snapshot, {required bool connected}) {
    final prediction = _engine.analyze(
      snapshot,
      candles: connected ? _candles : const [],
    );
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: connected ? Colors.greenAccent : Colors.amberAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                connected
                    ? '${snapshot.symbol} · Binance en vivo'
                    : '${snapshot.symbol} · Snapshot pegado',
              ),
            ),
            Text(
              _price(snapshot.midpoint),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (connected) ...[
          _liveChart(snapshot.symbol),
          const SizedBox(height: 12),
        ],
        _predictionPanel(prediction),
        const SizedBox(height: 12),
        _OrderBookTable(snapshot: snapshot),
        const SizedBox(height: 12),
        const Text(
          'El libro puede cambiar en milisegundos y mostrar ordenes que luego se cancelan. Confirma con precio, volumen, tendencia y gestion del riesgo.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _liveChart(String symbol) {
    if (_candlesLoading && _candles.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_candlesError != null && _candles.isEmpty) {
      return _MessagePanel(
        icon: Icons.candlestick_chart_outlined,
        message: _candlesError!,
      );
    }

    final visible = _candles.length <= 40
        ? _candles
        : _candles.sublist(_candles.length - 40);
    final latest = visible.last;
    final change = latest.open == 0
        ? 0.0
        : (latest.close - latest.open) / latest.open * 100;
    final candleColor = change >= 0 ? Colors.greenAccent : Colors.redAccent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Grafico $symbol',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(3)}%',
                  style: TextStyle(
                      color: candleColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ['1m', '5m', '15m']
                  .map(
                    (interval) => ChoiceChip(
                      label: Text(interval),
                      selected: _interval == interval,
                      onSelected: (_) {
                        setState(() => _interval = interval);
                        _connectCandles(_symbol.text.trim().toUpperCase());
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            CandlestickChart(candles: visible),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child:
                        _CandleMetric(label: 'Apertura', value: latest.open)),
                Expanded(
                    child: _CandleMetric(label: 'Maximo', value: latest.high)),
                Expanded(
                    child: _CandleMetric(label: 'Minimo', value: latest.low)),
                Expanded(
                    child: _CandleMetric(label: 'Cierre', value: latest.close)),
              ],
            ),
            const Divider(height: 24),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.only(bottom: 8),
              leading: Icon(Icons.school_outlined),
              title: Text('Como leer estas velas'),
              children: [
                _GuideLine(
                  title: 'Cuerpo',
                  text:
                      'Muestra la distancia entre apertura y cierre; verde indica cierre superior y rojo cierre inferior.',
                ),
                _GuideLine(
                  title: 'Mechas',
                  text:
                      'Marcan maximo y minimo. Una mecha larga puede mostrar rechazo, pero necesita confirmacion posterior.',
                ),
                _GuideLine(
                  title: 'Contexto',
                  text:
                      'El pool combina la forma de la vela con tendencia, momentum, volumen, volatilidad y libro de ordenes.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _predictionPanel(OrderBookPrediction prediction) {
    final color = switch (prediction.bias) {
      OrderBookBias.bullish => Colors.greenAccent,
      OrderBookBias.bearish => Colors.redAccent,
      OrderBookBias.neutral => Colors.amberAccent,
    };
    final decision = switch (prediction.bias) {
      OrderBookBias.bullish => 'COMPRA',
      OrderBookBias.bearish => 'VENTA',
      OrderBookBias.neutral => 'ESPERAR',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DECISION DEL POOL'),
                      Text(
                        decision,
                        style: TextStyle(
                          color: color,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(prediction.summary),
                    ],
                  ),
                ),
                Text(
                  '${prediction.score >= 0 ? '+' : ''}${prediction.score.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Probabilidad alcista ${prediction.upProbability.toStringAsFixed(0)}% · bajista ${prediction.downProbability.toStringAsFixed(0)}%',
            ),
            Text(
              'Confianza del pool ${prediction.confidence.toStringAsFixed(0)}%',
            ),
            Text(
              '${prediction.activeAnalysts} analistas cuantitativos · ${(prediction.agreement * 100).toStringAsFixed(0)}% de acuerdo',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text('50 revisan liquidez · 50 revisan velas e indicadores'),
            const Divider(height: 24),
            ...prediction.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(reason),
              ),
            ),
            const Divider(height: 24),
            const Text(
              'Mesa de analistas',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...prediction.teamOpinions.map(
              (team) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(team.family.label),
                          Text(
                            team.task,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(team.probabilityUp * 100).toStringAsFixed(0)}% alta',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _price(double value) =>
      value >= 1000 ? value.toStringAsFixed(2) : value.toStringAsPrecision(7);
}

class _CandleMetric extends StatelessWidget {
  const _CandleMetric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value >= 1000
                ? value.toStringAsFixed(2)
                : value.toStringAsPrecision(6),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      );
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: '$title: ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: text),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _OrderBookTable extends StatelessWidget {
  const _OrderBookTable({required this.snapshot});

  final OrderBookSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final asks = snapshot.asks.take(8).toList().reversed;
    final bids = snapshot.bids.take(8);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Precio (USDT)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Cantidad',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Divider(),
            ...asks.map((level) => _level(level, Colors.redAccent)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                snapshot.midpoint >= 1000
                    ? snapshot.midpoint.toStringAsFixed(2)
                    : snapshot.midpoint.toStringAsPrecision(7),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...bids.map((level) => _level(level, Colors.greenAccent)),
          ],
        ),
      ),
    );
  }

  Widget _level(OrderBookLevel level, Color color) => SizedBox(
        height: 26,
        child: Row(
          children: [
            Expanded(
              child: Text(
                level.price.toStringAsPrecision(8),
                style: TextStyle(color: color),
              ),
            ),
            Expanded(
              child: Text(
                level.quantity.toStringAsPrecision(6),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.loading = false,
  });

  final IconData icon;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 34),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}
