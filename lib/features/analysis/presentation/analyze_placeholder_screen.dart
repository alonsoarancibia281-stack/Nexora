import 'package:flutter/material.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';

class AnalyzePlaceholderScreen extends StatelessWidget {
  const AnalyzePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => MainNavigationScaffold(
        currentIndex: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('Analizar')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Motor de análisis Nexora', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text('Esta sección queda preparada para la Fase 3: RSI, MACD, EMA, Bollinger, ATR, ADX, soportes, resistencias y puntuación de -100 a +100.'),
              SizedBox(height: 20),
              Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Los resultados serán probabilísticos y educativos. Nexora no garantizará ganancias ni ejecutará operaciones.'))),
            ]),
          ),
        ),
      );
}
