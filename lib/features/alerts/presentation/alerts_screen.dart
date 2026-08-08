import 'package:flutter/material.dart';
import '../../market/data/binance_market_service.dart';
import '../data/local_alerts_repository.dart';
import '../domain/price_alert.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final repo = LocalAlertsRepository();
  final market = BinanceMarketService();
  final symbol = TextEditingController(text: 'BTCUSDT');
  final target = TextEditingController();
  String direction = 'above';
  bool loading = true;
  List<PriceAlert> alerts = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final data = await repo.load();
    if (mounted) setState(() { alerts = data; loading = false; });
  }

  Future<void> _add() async {
    final value = double.tryParse(target.text.replaceAll(',', '.'));
    final pair = symbol.text.trim().toUpperCase();
    if (pair.isEmpty || value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un par y un precio objetivo válidos.')));
      return;
    }
    final alert = PriceAlert(id: DateTime.now().microsecondsSinceEpoch.toString(), symbol: pair, targetPrice: value, direction: direction, createdAt: DateTime.now());
    await repo.add(alert);
    target.clear();
    await _load();
  }

  Future<void> _checkNow() async {
    if (alerts.isEmpty) return;
    setState(() => loading = true);
    try {
      final assets = await market.loadUsdtMarket();
      final prices = {for (final a in assets) a.symbol: a.price};
      alerts = await repo.evaluate(prices);
      if (mounted) {
        final hit = alerts.where((a) => a.triggeredAt != null).length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Alertas revisadas. $hit activadas en total.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin conexión. Las alertas permanecen guardadas.')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alertas locales'), actions: [IconButton(onPressed: loading ? null : _checkNow, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Se guardan en este dispositivo. En el MVP se comprueban al abrir esta pantalla o al pulsar actualizar.'),
      const SizedBox(height: 16),
      TextField(controller: symbol, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Par', hintText: 'BTCUSDT', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio objetivo', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'above', label: Text('Precio ≥ objetivo')), ButtonSegment(value: 'below', label: Text('Precio ≤ objetivo'))], selected: {direction}, onSelectionChanged: (v) => setState(() => direction = v.first)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_alert), label: const Text('Crear alerta')),
      const SizedBox(height: 20),
      if (loading) const Center(child: CircularProgressIndicator()) else if (alerts.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Todavía no tienes alertas.'))) else ...alerts.map((a) => Card(child: ListTile(
        leading: Icon(a.triggeredAt == null ? Icons.notifications_active_outlined : Icons.check_circle_outline),
        title: Text('${a.symbol} ${a.direction == 'above' ? '≥' : '≤'} ${a.targetPrice}'),
        subtitle: Text(a.triggeredAt == null ? 'Activa' : 'Activada ${a.triggeredAt}'),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await repo.remove(a.id); await _load(); }),
      ))),
    ]),
  );

  @override
  void dispose() { symbol.dispose(); target.dispose(); super.dispose(); }
}
