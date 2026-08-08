import 'dart:async';
import 'package:flutter/material.dart';
import '../data/binance_market_service.dart';
import '../domain/candle.dart';
import '../widgets/candlestick_chart.dart';

class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({super.key, required this.symbol});
  final String symbol;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final service = BinanceMarketService();
  String interval = '1h';
  late Future<List<Candle>> candles;
  Timer? refreshTimer;
  DateTime? lastRefresh;

  @override
  void initState() {
    super.initState();
    _reloadCandles();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _reloadCandles(silent: true));
  }

  void _reloadCandles({bool silent = false}) {
    final next = service.loadCandles(widget.symbol, interval);
    if (!mounted) return;
    setState(() {
      candles = next;
      lastRefresh = DateTime.now();
    });
  }

  void changeInterval(String value) {
    interval = value;
    _reloadCandles();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.symbol),
          actions: [
            IconButton(
              tooltip: 'Actualizar velas',
              onPressed: _reloadCandles,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StreamBuilder<double>(
              stream: service.livePrice(widget.symbol),
              builder: (context, snapshot) {
                final connected = snapshot.hasData;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connected ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(connected ? 'Tiempo real conectado' : 'Conectando/reintentando…'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      connected ? '${_price(snapshot.data!)} USDT' : '—',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Text('Datos públicos de mercado. No constituye una recomendación de inversión.'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['5m', '15m', '1h', '4h', '1d', '1w']
                  .map((value) => ChoiceChip(
                        label: Text(value),
                        selected: interval == value,
                        onSelected: (_) => changeInterval(value),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 18),
            FutureBuilder<List<Candle>>(
              future: candles,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return SizedBox(
                    height: 300,
                    child: Center(child: Text('No se pudieron cargar las velas: ${snapshot.error}')),
                  );
                }

                final data = snapshot.data ?? const <Candle>[];
                if (data.isEmpty) return const SizedBox(height: 300, child: Center(child: Text('Sin velas disponibles.')));
                final latest = data.last;

                return Column(
                  children: [
                    _OhlcCard(candle: latest),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: CandlestickChart(candles: data),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        lastRefresh == null
                            ? ''
                            : 'Actualizado ${TimeOfDay.fromDateTime(lastRefresh!).format(context)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Siguiente: análisis técnico', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('La Fase 3 calculará indicadores y puntuaciones sobre estas mismas velas reales, separando tendencia, riesgo y confianza.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  String _price(double value) => value >= 1000
      ? value.toStringAsFixed(2)
      : value >= 1
          ? value.toStringAsFixed(4)
          : value.toStringAsPrecision(6);
}

class _OhlcCard extends StatelessWidget {
  const _OhlcCard({required this.candle});
  final Candle candle;

  @override
  Widget build(BuildContext context) {
    final change = candle.open == 0 ? 0.0 : ((candle.close - candle.open) / candle.open) * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Última vela', style: TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                  style: TextStyle(color: change >= 0 ? Colors.greenAccent : Colors.redAccent),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Metric(label: 'Apertura', value: candle.open)),
                Expanded(child: _Metric(label: 'Máximo', value: candle.high)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Metric(label: 'Mínimo', value: candle.low)),
                Expanded(child: _Metric(label: 'Cierre', value: candle.close)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Volumen: ${candle.volume.toStringAsFixed(4)}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value.toStringAsPrecision(8), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}
