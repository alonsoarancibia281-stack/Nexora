import 'package:flutter/material.dart';
import '../domain/simulated_trade.dart';
import '../domain/simulator_engine.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _entry = TextEditingController();
  final _exit = TextEditingController();
  final _quantity = TextEditingController();
  final _fee = TextEditingController(text: '0.10');
  final _engine = const SimulatorEngine();
  SimulatedTradeSide _side = SimulatedTradeSide.long;
  SimulatedTradeResult? _result;
  String? _error;

  @override
  void dispose() {
    _entry.dispose();
    _exit.dispose();
    _quantity.dispose();
    _fee.dispose();
    super.dispose();
  }

  double _value(TextEditingController controller) =>
      double.parse(controller.text.trim().replaceAll(',', '.'));

  void _calculate() {
    try {
      final result = _engine.calculate(
        side: _side,
        entryPrice: _value(_entry),
        exitPrice: _value(_exit),
        quantity: _value(_quantity),
        feeRatePercent: _value(_fee),
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _result = null;
        _error = 'Revisa los valores. Los precios y la cantidad deben ser mayores que cero y la comisión no puede ser negativa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Simulador educativo')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Simula una operación sin dinero real',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Nexora calcula un resultado hipotético. No abre posiciones ni envía órdenes a ningún exchange.'),
            const SizedBox(height: 20),
            SegmentedButton<SimulatedTradeSide>(
              segments: const [
                ButtonSegment(value: SimulatedTradeSide.long, label: Text('Long'), icon: Icon(Icons.trending_up)),
                ButtonSegment(value: SimulatedTradeSide.short, label: Text('Short'), icon: Icon(Icons.trending_down)),
              ],
              selected: {_side},
              onSelectionChanged: (value) => setState(() => _side = value.first),
            ),
            const SizedBox(height: 18),
            _Field(controller: _entry, label: 'Precio de entrada'),
            const SizedBox(height: 12),
            _Field(controller: _exit, label: 'Precio de salida'),
            const SizedBox(height: 12),
            _Field(controller: _quantity, label: 'Cantidad del activo'),
            const SizedBox(height: 12),
            _Field(controller: _fee, label: 'Comisión por operación (%)'),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _calculate, icon: const Icon(Icons.calculate_outlined), label: const Text('Calcular simulación')),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_result case final result?) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resultado hipotético', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 14),
                      _Metric(label: 'PnL bruto', value: '${result.grossPnl.toStringAsFixed(2)} USDT'),
                      _Metric(label: 'Comisiones', value: '${result.fees.toStringAsFixed(2)} USDT'),
                      _Metric(label: 'PnL neto', value: '${result.netPnl.toStringAsFixed(2)} USDT'),
                      _Metric(label: 'Retorno', value: '${result.returnPercent.toStringAsFixed(2)}%'),
                      const Divider(height: 28),
                      Text(
                        result.isProfit
                            ? 'En este escenario hipotético la operación termina con beneficio neto.'
                            : result.isLoss
                                ? 'En este escenario hipotético la operación termina con pérdida neta.'
                                : 'En este escenario hipotético el resultado neto es neutro.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
