import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/nexora_theme.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../../shared/widgets/nexora_button.dart';
import '../../market/domain/candle.dart';
import '../../market/widgets/candlestick_chart.dart';
import '../data/binance_order_book_service.dart';
import '../domain/order_book_parser.dart';
import '../domain/order_book_prediction.dart';
import '../domain/order_book_prediction_engine.dart';
import '../domain/order_book_snapshot.dart';

enum _BookSource { live, pasted }

enum _TradeSide { buy, sell }

class OrderBookScreen extends StatefulWidget {
  const OrderBookScreen({super.key});

  @override
  State<OrderBookScreen> createState() => _OrderBookScreenState();
}

class _OrderBookScreenState extends State<OrderBookScreen> {
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _pasted = TextEditingController();
  final _limitPrice = TextEditingController();
  final _quantity = TextEditingController();
  final _total = TextEditingController();
  final _takeProfit = TextEditingController();
  final _stopTrigger = TextEditingController();
  final _stopLimit = TextEditingController();
  final _service = const BinanceOrderBookService();
  final _parser = const OrderBookParser();
  final _engine = const OrderBookPredictionEngine();

  _BookSource _source = _BookSource.live;
  _TradeSide _side = _TradeSide.buy;
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
  bool _marginEnabled = true;
  bool _tpSlEnabled = true;
  bool _icebergEnabled = false;
  double _amountFraction = 0;

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
    _limitPrice.dispose();
    _quantity.dispose();
    _total.dispose();
    _takeProfit.dispose();
    _stopTrigger.dispose();
    _stopLimit.dispose();
    super.dispose();
  }

  void _connect() {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    setState(() {
      _stream = _service.liveDepth(symbol);
      _visibleSnapshot = null;
      _limitPrice.clear();
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

  void _fillBbo(OrderBookSnapshot snapshot) {
    final price = _side == _TradeSide.buy ? snapshot.bestBid : snapshot.bestAsk;
    _limitPrice.text = _priceInput(price);
    _recalculateTotal();
  }

  void _recalculateTotal() {
    final price = double.tryParse(_limitPrice.text.replaceAll(',', ''));
    final quantity = double.tryParse(_quantity.text.replaceAll(',', ''));
    if (price == null || quantity == null || price <= 0 || quantity <= 0) {
      return;
    }
    _total.text = (price * quantity).toStringAsFixed(2);
  }

  void _ensureInitialPrice(OrderBookSnapshot snapshot) {
    if (_limitPrice.text.isNotEmpty) return;
    final price = _side == _TradeSide.buy ? snapshot.bestBid : snapshot.bestAsk;
    _limitPrice.text = _priceInput(price);
  }

  void _showManualExecutionNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Orden preparada. Nexora no ejecuta operaciones automaticas.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MainNavigationScaffold(
        currentIndex: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Trade'),
            actions: [
              IconButton(
                tooltip: 'Copiar snapshot',
                onPressed: _visibleSnapshot == null ? null : _copySnapshot,
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              _symbolBar(),
              const SizedBox(height: 10),
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
                    label: Text('Pegar'),
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
              const SizedBox(height: 12),
              if (_source == _BookSource.live) _liveBook() else _pastePanel(),
            ],
          ),
        ),
      );

  Widget _symbolBar() {
    final change = _latestChange();
    final color = change >= 0 ? NexoraTheme.up : Colors.redAccent;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _symbol,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _connect(),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'BTCUSDT',
              suffixIcon: Icon(Icons.keyboard_arrow_down),
            ),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Conectar',
          onPressed: _connect,
          icon: const Icon(Icons.sync),
        ),
      ],
    );
  }

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
                child: NexoraButton(
                  label: 'Pegar',
                  icon: Icons.content_paste,
                  level: NexoraLevel.tertiary,
                  expand: true,
                  onPressed: _pasteFromClipboard,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NexoraButton(
                  label: 'Analizar',
                  icon: Icons.analytics_outlined,
                  expand: true,
                  onPressed: _analyzePasted,
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
            const SizedBox(height: 12),
            _snapshotView(snapshot, connected: false),
          ],
        ],
      );

  Widget _snapshotView(OrderBookSnapshot snapshot, {required bool connected}) {
    _ensureInitialPrice(snapshot);
    final prediction = _engine.analyze(
      snapshot,
      candles: connected ? _candles : const [],
    );
    return Column(
      children: [
        _tradeTerminal(snapshot, prediction, connected: connected),
        const SizedBox(height: 10),
        if (connected) _chartPanel(snapshot.symbol),
        const SizedBox(height: 10),
        _analystDesk(prediction),
        const SizedBox(height: 8),
        const Text(
          'Senales educativas. El libro puede cambiar en milisegundos; confirma con riesgo, tendencia y liquidez antes de operar.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _tradeTerminal(
    OrderBookSnapshot snapshot,
    OrderBookPrediction prediction, {
    required bool connected,
  }) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final form = _orderForm(snapshot, prediction);
          final book = _LiveOrderBook(snapshot: snapshot);
          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: form),
                const SizedBox(width: 10),
                Expanded(flex: 8, child: book),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 340, child: form),
              const SizedBox(width: 16),
              Expanded(child: book),
            ],
          );
        },
      );

  Widget _orderForm(
      OrderBookSnapshot snapshot, OrderBookPrediction prediction) {
    final isBuy = _side == _TradeSide.buy;
    final actionColor =
        isBuy ? NexoraTheme.up : NexoraTheme.down;
    final available = isBuy ? '7.35110019 USDT' : '0.014820 BTC';
    final max = isBuy ? '73.57722803 USDT' : '0.148200 BTC';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sideTabs(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _pill('Aislado', selected: true)),
            const SizedBox(width: 6),
            Expanded(child: _pill('10x', selected: true)),
            const SizedBox(width: 6),
            Expanded(child: _pill('Prestamo', selected: false)),
          ],
        ),
        const SizedBox(height: 8),
        _orderTypeRow(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _tradeInput(
                controller: _limitPrice,
                label: 'Limite(USDT)',
                hint: 'Completar',
                onChanged: (_) => _recalculateTotal(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              height: 58,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _fillBbo(snapshot),
                child: const Text(
                  'BBO',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _tradeInput(
          controller: _quantity,
          label: 'Cantidad(BTC)',
          hint: 'Completar',
          onChanged: (_) => _recalculateTotal(),
        ),
        Slider(
          value: _amountFraction,
          divisions: 4,
          label: '${(_amountFraction * 100).toStringAsFixed(0)}%',
          onChanged: (value) => setState(() => _amountFraction = value),
        ),
        _tradeInput(
          controller: _total,
          label: 'Total(USDT)',
          hint: 'Se calcula o se cambia',
        ),
        const SizedBox(height: 6),
        _tpSlControls(),
        const SizedBox(height: 8),
        if (_tpSlEnabled) ...[
          _tradeInput(
            controller: _takeProfit,
            label: 'Limit TP (USDT)',
            hint: 'Take Profit',
          ),
          const SizedBox(height: 8),
          _tradeInput(
            controller: _stopTrigger,
            label: 'Activador SL (USDT)',
            hint: 'Stop Loss',
          ),
          const SizedBox(height: 8),
          _tradeInput(
            controller: _stopLimit,
            label: 'SL Limit (USDT)',
            hint: 'Stop Limit',
          ),
          const SizedBox(height: 6),
        ],
        _checkboxLine(
          value: _icebergEnabled,
          label: 'Iceberg',
          onChanged: (value) => setState(() => _icebergEnabled = value),
        ),
        const SizedBox(height: 8),
        _accountRow('Disponible', available),
        _accountRow('Max.', max),
        _accountRow('Prestamo', '-- USDT'),
        _accountRow('Precio de liq.', '-- USDT'),
        const SizedBox(height: 10),
        NexoraButton(
          label: isBuy ? 'Preparar compra' : 'Preparar venta',
          icon: isBuy ? Icons.arrow_upward : Icons.arrow_downward,
          tone: actionColor,
          expand: true,
          onPressed: _showManualExecutionNotice,
        ),
        const SizedBox(height: 8),
        _poolAction(prediction),
      ],
    );
  }

  Widget _sideTabs() => Row(
        children: [
          Expanded(
            child: _sideButton(
              label: 'Comprar',
              side: _TradeSide.buy,
              color: NexoraTheme.up,
            ),
          ),
          Expanded(
            child: _sideButton(
              label: 'Vender',
              side: _TradeSide.sell,
              color: NexoraTheme.down,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Margin',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              Switch(
                value: _marginEnabled,
                activeThumbColor: NexoraTheme.brand,
                onChanged: (value) => setState(() => _marginEnabled = value),
              ),
            ],
          ),
        ],
      );

  Widget _sideButton({
    required String label,
    required _TradeSide side,
    required Color color,
  }) {
    final selected = _side == side;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _side = side;
        _limitPrice.clear();
      }),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? color
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, {required bool selected}) => Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: selected ? .9 : .45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );

  Widget _orderTypeRow() => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Orden limite',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      );

  Widget _tradeInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    ValueChanged<String>? onChanged,
  }) =>
      SizedBox(
        height: 58,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

  Widget _tpSlControls() => Row(
        children: [
          Expanded(
            child: _checkboxLine(
              value: _tpSlEnabled,
              label: 'TP/SL',
              onChanged: (value) => setState(() => _tpSlEnabled = value),
            ),
          ),
          if (_tpSlEnabled)
            const Row(
              children: [
                Text('Avanzado', style: TextStyle(fontSize: 13)),
                Icon(Icons.keyboard_arrow_down, size: 20),
              ],
            ),
        ],
      );

  Widget _checkboxLine({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) =>
      InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: (next) => onChanged(next ?? false),
            ),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _accountRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _poolAction(OrderBookPrediction prediction) {
    final color = switch (prediction.bias) {
      OrderBookBias.bullish => NexoraTheme.up,
      OrderBookBias.bearish => NexoraTheme.down,
      OrderBookBias.neutral => NexoraTheme.warn,
    };
    final decision = switch (prediction.bias) {
      OrderBookBias.bullish => 'COMPRA',
      OrderBookBias.bearish => 'VENTA',
      OrderBookBias.neutral => 'ESPERAR',
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pool 100',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          Text(
            decision,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${prediction.confidence.toStringAsFixed(0)}% confianza · ${(prediction.agreement * 100).toStringAsFixed(0)}% acuerdo',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _chartPanel(String symbol) {
    if (_candlesLoading && _candles.isEmpty) {
      return const SizedBox(
        height: 88,
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
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text(
          'Grafico ${_displaySymbol(symbol)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
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
                  child: _CandleMetric(label: 'Apertura', value: latest.open)),
              Expanded(
                  child: _CandleMetric(label: 'Maximo', value: latest.high)),
              Expanded(
                  child: _CandleMetric(label: 'Minimo', value: latest.low)),
              Expanded(
                  child: _CandleMetric(label: 'Cierre', value: latest.close)),
            ],
          ),
          const Divider(height: 24),
          const _GuideLine(
            title: 'Cuerpo',
            text:
                'Apertura contra cierre. Verde cierra arriba; rojo cierra abajo.',
          ),
          const _GuideLine(
            title: 'Mechas',
            text:
                'Maximo y minimo. Mechas largas muestran rechazo, no certeza.',
          ),
          const _GuideLine(
            title: 'Contexto',
            text:
                'El pool cruza vela, momentum, volumen, volatilidad y liquidez.',
          ),
        ],
      ),
    );
  }

  Widget _analystDesk(OrderBookPrediction prediction) => ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text(
          'Analistas del pool',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(prediction.summary),
        children: [
          ...prediction.reasons.map(
            (reason) => Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(reason),
              ),
            ),
          ),
          const Divider(),
          ...prediction.teamOpinions.map(
            (team) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${team.family.label}: ${team.task}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${(team.probabilityUp * 100).toStringAsFixed(0)}% alta',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  double _latestChange() {
    if (_candles.isEmpty) return 0;
    final latest = _candles.last;
    if (latest.open == 0) return 0;
    return (latest.close - latest.open) / latest.open * 100;
  }

  String _displaySymbol(String symbol) {
    final normalized = symbol.toUpperCase();
    if (normalized.endsWith('USDT')) {
      return '${normalized.substring(0, normalized.length - 4)}/USDT';
    }
    return normalized;
  }

  String _priceInput(double value) =>
      value >= 1000 ? value.toStringAsFixed(2) : value.toStringAsPrecision(7);
}

class _LiveOrderBook extends StatelessWidget {
  const _LiveOrderBook({required this.snapshot});

  final OrderBookSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final asks = snapshot.asks.take(12).toList();
    final bids = snapshot.bids.take(12).toList();
    final totalAsk = asks.fold<double>(0, (sum, level) => sum + level.quantity);
    final totalBid = bids.fold<double>(0, (sum, level) => sum + level.quantity);
    final totalDepth = totalAsk + totalBid;
    final bidRatio = totalDepth == 0 ? 0.5 : totalBid / totalDepth;
    final askRatio = 1 - bidRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Precio\n(USDT)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                'Monto\n(BTC)',
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...asks.reversed.map(
          (level) => _BookLevelRow(
            level: level,
            color: NexoraTheme.down,
            maxQuantity: totalAsk,
            alignRight: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                snapshot.midpoint >= 1000
                    ? snapshot.midpoint.toStringAsFixed(2)
                    : snapshot.midpoint.toStringAsPrecision(7),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: bidRatio >= .5 ? NexoraTheme.up : NexoraTheme.down,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Spread ${_spread(snapshot)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...bids.map(
          (level) => _BookLevelRow(
            level: level,
            color: NexoraTheme.up,
            maxQuantity: totalBid,
            alignRight: false,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${(bidRatio * 100).toStringAsFixed(2)}%',
              style: const TextStyle(color: NexoraTheme.up, fontSize: 12),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 7,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (bidRatio * 1000).round().clamp(1, 999),
                        child: Container(color: NexoraTheme.up),
                      ),
                      Expanded(
                        flex: (askRatio * 1000).round().clamp(1, 999),
                        child: Container(color: NexoraTheme.down),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(askRatio * 100).toStringAsFixed(2)}%',
              style: const TextStyle(color: NexoraTheme.down, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Expanded(child: Text('0.01', style: TextStyle(fontSize: 12))),
              const Icon(Icons.keyboard_arrow_down, size: 18),
              Icon(
                Icons.view_module,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _spread(OrderBookSnapshot snapshot) {
    final spread = snapshot.bestAsk - snapshot.bestBid;
    if (spread <= 0) return '--';
    return spread >= 1
        ? spread.toStringAsFixed(2)
        : spread.toStringAsPrecision(4);
  }
}

class _BookLevelRow extends StatelessWidget {
  const _BookLevelRow({
    required this.level,
    required this.color,
    required this.maxQuantity,
    required this.alignRight,
  });

  final OrderBookLevel level;
  final Color color;
  final double maxQuantity;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final ratio = maxQuantity == 0 ? 0.0 : (level.quantity / maxQuantity);
    return SizedBox(
      height: 24,
      child: Stack(
        children: [
          Align(
            alignment:
                alignRight ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio.clamp(0.04, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.09)),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  level.price >= 1000
                      ? level.price.toStringAsFixed(2)
                      : level.price.toStringAsPrecision(7),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  level.quantity.toStringAsPrecision(5),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: text),
                  ],
                ),
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
