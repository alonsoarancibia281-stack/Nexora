enum OrderBookBias { bullish, bearish, neutral }

enum OrderBookAnalystFamily {
  topOfBook,
  depthBalance,
  weightedDepth,
  microprice,
  walls,
  trend,
  momentum,
  candleStructure,
  volume,
  volatility,
}

extension OrderBookAnalystFamilyLabel on OrderBookAnalystFamily {
  String get label => switch (this) {
        OrderBookAnalystFamily.topOfBook => 'Mejor compra/venta',
        OrderBookAnalystFamily.depthBalance => 'Profundidad acumulada',
        OrderBookAnalystFamily.weightedDepth => 'Liquidez cercana',
        OrderBookAnalystFamily.microprice => 'Microprecio',
        OrderBookAnalystFamily.walls => 'Paredes de liquidez',
        OrderBookAnalystFamily.trend => 'Tendencia de velas',
        OrderBookAnalystFamily.momentum => 'Momentum',
        OrderBookAnalystFamily.candleStructure => 'Estructura de velas',
        OrderBookAnalystFamily.volume => 'Volumen y precio',
        OrderBookAnalystFamily.volatility => 'Volatilidad y ruptura',
      };
}

class OrderBookTeamOpinion {
  const OrderBookTeamOpinion({
    required this.family,
    required this.task,
    required this.probabilityUp,
    required this.quality,
    required this.disagreement,
  });

  final OrderBookAnalystFamily family;
  final String task;
  final double probabilityUp;
  final double quality;
  final double disagreement;
}

class OrderBookPrediction {
  const OrderBookPrediction({
    required this.bias,
    required this.score,
    required this.confidence,
    required this.upProbability,
    required this.imbalancePercent,
    required this.spreadBps,
    required this.micropriceEdgeBps,
    required this.activeAnalysts,
    required this.agreement,
    required this.teamOpinions,
    required this.summary,
    required this.reasons,
  });

  final OrderBookBias bias;
  final double score;
  final double confidence;
  final double upProbability;
  final double imbalancePercent;
  final double spreadBps;
  final double micropriceEdgeBps;
  final int activeAnalysts;
  final double agreement;
  final List<OrderBookTeamOpinion> teamOpinions;
  final String summary;
  final List<String> reasons;

  double get downProbability => 100 - upProbability;
}
