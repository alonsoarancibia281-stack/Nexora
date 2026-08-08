import 'package:flutter/material.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../market/data/binance_market_service.dart';
import '../domain/technical_analysis.dart';
import '../services/technical_analysis_engine.dart';

class AnalyzePlaceholderScreen extends StatefulWidget {
  const AnalyzePlaceholderScreen({super.key});

  @override
  State<AnalyzePlaceholderScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzePlaceholderScreen> {
  final _service = BinanceMarketService();
  final _engine = TechnicalAnalysisEngine();
  final _symbol = TextEditingController(text: 'BTCUSDT');

  String _interval = '1h';
  Future<TechnicalAnalysis>? _analysis;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _symbol.dispose();
    super.dispose();
  }

  void _run() {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    setState(() {
      _analysis = _service
          .loadCandles(symbol, _interval, limit: 250)
          .then(_engine.analyze);
    });
  }

  @override
  Widget build(BuildContext context) => MainNavigationScaffold(
        currentIndex: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('Analizar')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Motor de análisis Nexora',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Indicadores calculados sobre velas públicas de Binance. Resultado educativo y probabilístico.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _symbol,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _run(),
                decoration: InputDecoration(
                  labelText: 'Par',
                  hintText: 'BTCUSDT',
                  suffixIcon: IconButton(
                    onPressed: _run,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['15m', '1h', '4h', '1d']
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: _interval == value,
                        onSelected: (_) {
                          setState(() => _interval = value);
                          _run();
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              if (_analysis != null)
                FutureBuilder<TechnicalAnalysis>(
                  future: _analysis,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'No se pudo analizar el activo: ${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final analysis = snapshot.data!;
                    return Column(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                Text(
                                  '${analysis.score >= 0 ? '+' : ''}${analysis.score}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const Text('Nexora Score · -100 a +100'),
                                const SizedBox(height: 8),
                                Text(
                                  analysis.trend,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Confianza técnica ${analysis.confidence.toStringAsFixed(0)}% · Riesgo ${analysis.risk}',
                                ),
                              ],
                            ),
                          ),
                        ),
                        _section('Tendencia', [
                          ['EMA 9', analysis.ema9],
                          ['EMA 21', analysis.ema21],
                          ['EMA 50', analysis.ema50],
                          ['EMA 200', analysis.ema200],
                          ['ADX', analysis.adx],
                        ]),
                        _section('Momentum', [
                          ['RSI 14', analysis.rsi],
                          ['MACD', analysis.macd],
                          ['Señal MACD', analysis.macdSignal],
                          ['Estocástico %K', analysis.stochasticK],
                          ['Estocástico %D', analysis.stochasticD],
                        ]),
                        _section('Volatilidad', [
                          ['Bollinger superior', analysis.bollingerUpper],
                          ['Bollinger media', analysis.bollingerMiddle],
                          ['Bollinger inferior', analysis.bollingerLower],
                          ['ATR 14', analysis.atr],
                          ['Volatilidad %', analysis.volatilityPercent],
                        ]),
                        _section('Niveles', [
                          ['Soporte', analysis.support],
                          ['Resistencia', analysis.resistance],
                        ]),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No es una señal de compra o venta ni garantiza resultados. Confirma el contexto, liquidez y riesgo antes de tomar decisiones.',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      );

  Widget _section(String title, List<List<Object>> values) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(),
              ...values.map(
                (value) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(value[0] as String),
                      Text(
                        (value[1] as double).toStringAsFixed(4),
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
