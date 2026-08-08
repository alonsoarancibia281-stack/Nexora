class TechnicalAnalysis {
  const TechnicalAnalysis({
    required this.rsi,
    required this.macd,
    required this.macdSignal,
    required this.ema9,
    required this.ema21,
    required this.ema50,
    required this.ema200,
    required this.bollingerUpper,
    required this.bollingerMiddle,
    required this.bollingerLower,
    required this.atr,
    required this.adx,
    required this.stochasticK,
    required this.stochasticD,
    required this.support,
    required this.resistance,
    required this.volatilityPercent,
    required this.score,
    required this.trend,
    required this.risk,
    required this.confidence,
  });

  final double rsi;
  final double macd;
  final double macdSignal;
  final double ema9;
  final double ema21;
  final double ema50;
  final double ema200;
  final double bollingerUpper;
  final double bollingerMiddle;
  final double bollingerLower;
  final double atr;
  final double adx;
  final double stochasticK;
  final double stochasticD;
  final double support;
  final double resistance;
  final double volatilityPercent;
  final int score;
  final String trend;
  final String risk;
  final double confidence;
}
