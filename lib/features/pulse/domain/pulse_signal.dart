enum PulseDirection { up, down, noTrade }

enum MarketStability { stable, unstable, veryUnstable }

class PulseSignal {
  const PulseSignal({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.momentumScore,
    required this.trendScore,
    required this.orderBookImbalance,
    required this.volumeRatio,
    required this.bodyPressure,
    required this.instabilityScore,
    required this.stability,
    required this.reasons,
  });

  final PulseDirection direction;
  final double score;
  final double confidence;
  final double momentumScore;
  final double trendScore;
  final double orderBookImbalance;
  final double volumeRatio;
  final double bodyPressure;
  final double instabilityScore;
  final MarketStability stability;
  final List<String> reasons;

  String get directionLabel => switch (direction) {
        PulseDirection.up => 'SUBE',
        PulseDirection.down => 'BAJA',
        PulseDirection.noTrade => 'NO TRADE',
      };

  String get stabilityLabel => switch (stability) {
        MarketStability.stable => 'ESTABLE',
        MarketStability.unstable => 'INESTABLE',
        MarketStability.veryUnstable => 'MUY INESTABLE',
      };
}
