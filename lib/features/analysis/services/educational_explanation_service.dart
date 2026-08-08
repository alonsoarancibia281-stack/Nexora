import '../domain/technical_analysis.dart';

class EducationalExplanation {
  const EducationalExplanation({
    required this.summary,
    required this.momentum,
    required this.trendStrength,
    required this.volatility,
    required this.levels,
    required this.riskNote,
  });

  final String summary;
  final String momentum;
  final String trendStrength;
  final String volatility;
  final String levels;
  final String riskNote;
}

class EducationalExplanationService {
  const EducationalExplanationService();

  EducationalExplanation explain(TechnicalAnalysis analysis) {
    final summary = analysis.score >= 35
        ? 'Los indicadores agregados muestran predominio alcista, aunque esto no implica que el precio deba continuar subiendo.'
        : analysis.score <= -35
            ? 'Los indicadores agregados muestran predominio bajista, aunque esto no implica que el precio deba continuar cayendo.'
            : 'Los indicadores no muestran una dirección suficientemente consistente; el mercado puede estar lateral o en transición.';

    final momentum = analysis.rsi >= 70
        ? 'El RSI está en una zona históricamente asociada con sobrecompra. No significa una caída inmediata, pero aumenta la importancia de esperar confirmación.'
        : analysis.rsi <= 30
            ? 'El RSI está en una zona históricamente asociada con sobreventa. No significa un rebote inmediato, pero puede indicar movimiento extendido.'
            : 'El RSI se encuentra fuera de extremos de sobrecompra y sobreventa.';

    final trendStrength = analysis.adx >= 25
        ? 'El ADX sugiere que la tendencia actual tiene fuerza suficiente para ser relevante.'
        : 'El ADX sugiere una tendencia débil; las señales direccionales tienen menor confirmación.';

    final volatility = analysis.volatilityPercent >= 5
        ? 'La volatilidad medida por ATR es elevada. Movimientos adversos amplios son más probables y el tamaño de posición debería ser especialmente conservador.'
        : analysis.volatilityPercent >= 2.5
            ? 'La volatilidad es moderada. El stop loss debe considerar el rango normal del activo para evitar quedar demasiado cerca del ruido de mercado.'
            : 'La volatilidad reciente es relativamente contenida, aunque puede cambiar rápidamente.';

    final levels = 'Soporte técnico aproximado: ${analysis.support.toStringAsFixed(4)}. '
        'Resistencia técnica aproximada: ${analysis.resistance.toStringAsFixed(4)}. '
        'Son zonas estimadas a partir de velas recientes, no precios garantizados de giro.';

    return EducationalExplanation(
      summary: summary,
      momentum: momentum,
      trendStrength: trendStrength,
      volatility: volatility,
      levels: levels,
      riskNote: 'Nexora explica condiciones observadas; no emite garantías ni ejecuta operaciones. Define primero tu pérdida máxima aceptable.',
    );
  }
}
