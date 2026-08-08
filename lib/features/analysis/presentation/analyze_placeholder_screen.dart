import 'package:flutter/material.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../market/data/binance_market_service.dart';
import '../domain/multi_timeframe_analysis.dart';
import '../domain/technical_analysis.dart';
import '../services/educational_explanation_service.dart';
import '../services/multi_timeframe_analysis_service.dart';
import '../services/technical_analysis_engine.dart';

class AnalyzePlaceholderScreen extends StatefulWidget {
  const AnalyzePlaceholderScreen({super.key});

  @override
  State<AnalyzePlaceholderScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzePlaceholderScreen> {
  final _service = BinanceMarketService();
  final _engine = TechnicalAnalysisEngine();
  final _multiTimeframe = MultiTimeframeAnalysisService();
  final _explanation = const EducationalExplanationService();
  final _symbol = TextEditingController(text: 'BTCUSDT');

  String _interval = '1h';
  Future<TechnicalAnalysis>? _analysis;
  Future<MultiTimeframeAnalysis>? _multiAnalysis;

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
      _multiAnalysis = _multiTimeframe.analyze(symbol);
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
                    tooltip: 'Analizar',
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
              if (_multiAnalysis != null) _buildMultiTimeframe(),
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
                    final explanation = _explanation.explain(analysis);
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
                        _educationalCard(explanation),
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

  Widget _buildMultiTimeframe() => FutureBuilder<MultiTimeframeAnalysis>(
        future: _multiAnalysis,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('Confirmando 15m · 1h · 4h · 1d…')),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'El análisis principal sigue disponible, pero no se pudo completar la confirmación multitemporal.',
                ),
              ),
            );
          }

          final multi = snapshot.data!;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        multi.isConfirmed ? Icons.verified : Icons.rule,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Confirmación multitemporal',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${multi.compositeScore >= 0 ? '+' : ''}${multi.compositeScore} · ${multi.bias}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Acuerdo ${multi.agreementPercent.toStringAsFixed(0)}% · Confianza ${multi.confidence.toStringAsFixed(0)}%',
                  ),
                  const Divider(height: 24),
                  ...['15m', '1h', '4h', '1d'].map((interval) {
                    final item = multi.byInterval[interval]!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              interval,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(child: Text(item.trend)),
                          Text(
                            '${item.score >= 0 ? '+' : ''}${item.score}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    multi.isConfirmed
                        ? 'Varias temporalidades apuntan en la misma dirección. Aun así, la confirmación no elimina el riesgo.'
                        : 'Las temporalidades no muestran suficiente acuerdo. Conviene interpretar cualquier sesgo con mayor cautela.',
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _educationalCard(EducationalExplanation explanation) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.school_outlined),
                  SizedBox(width: 8),
                  Text(
                    'Asistente educativo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _explanationLine('Lectura general', explanation.summary),
              _explanationLine('Momentum', explanation.momentum),
              _explanationLine('Fuerza de tendencia', explanation.trendStrength),
              _explanationLine('Volatilidad', explanation.volatility),
              _explanationLine('Niveles', explanation.levels),
              const Divider(),
              Text(
                explanation.riskNote,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );

  Widget _explanationLine(String label, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(text),
          ],
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
