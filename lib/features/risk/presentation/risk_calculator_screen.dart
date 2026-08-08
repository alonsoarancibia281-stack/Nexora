import 'package:flutter/material.dart';
import '../domain/risk_calculator.dart';

class RiskCalculatorScreen extends StatefulWidget {
  const RiskCalculatorScreen({super.key});

  @override
  State<RiskCalculatorScreen> createState() => _RiskCalculatorScreenState();
}

class _RiskCalculatorScreenState extends State<RiskCalculatorScreen> {
  final _capital = TextEditingController(text: '1000');
  final _risk = TextEditingController(text: '1');
  final _entry = TextEditingController(text: '100');
  final _stop = TextEditingController(text: '95');
  final _target = TextEditingController(text: '110');
  static const _calculator = RiskCalculator();

  RiskPlan? _plan;
  String? _error;

  @override
  void dispose() {
    _capital.dispose();
    _risk.dispose();
    _entry.dispose();
    _stop.dispose();
    _target.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final plan = _calculator.calculate(
        capital: double.parse(_capital.text.replaceAll(',', '.')),
        riskPercent: double.parse(_risk.text.replaceAll(',', '.')),
        entryPrice: double.parse(_entry.text.replaceAll(',', '.')),
        stopLossPrice: double.parse(_stop.text.replaceAll(',', '.')),
        takeProfitPrice: double.parse(_target.text.replaceAll(',', '.')),
      );
      setState(() {
        _plan = plan;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _plan = null;
        _error = 'Revisa los valores ingresados. Todos deben ser números válidos y positivos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gestión de riesgo')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Calculadora de posición',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Define cuánto estás dispuesto a perder antes de pensar en cuánto quieres ganar.',
            ),
            const SizedBox(height: 20),
            _field(_capital, 'Capital disponible', 'USDT'),
            _field(_risk, 'Riesgo máximo', '%'),
            _field(_entry, 'Precio de entrada', 'USDT'),
            _field(_stop, 'Stop loss', 'USDT'),
            _field(_target, 'Objetivo', 'USDT'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Calcular plan de riesgo'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_plan != null) ...[
              const SizedBox(height: 20),
              _resultCard(_plan!),
            ],
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Esta herramienta es educativa. No abre posiciones, no mueve fondos y no sustituye una evaluación completa del riesgo de mercado.',
                ),
              ),
            ),
          ],
        ),
      );

  Widget _field(TextEditingController controller, String label, String suffix) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _resultCard(RiskPlan plan) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plan calculado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              _row('Pérdida máxima', '${plan.maxLoss.toStringAsFixed(2)} USDT'),
              _row('Riesgo por unidad', plan.riskPerUnit.toStringAsFixed(6)),
              _row('Tamaño de posición', plan.positionUnits.toStringAsFixed(6)),
              _row('Valor de posición', '${plan.positionValue.toStringAsFixed(2)} USDT'),
              _row('Beneficio/riesgo', '1 : ${plan.riskRewardRatio.toStringAsFixed(2)}'),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );
}
