import 'technical_analysis.dart';

class MultiTimeframeAnalysis {
  const MultiTimeframeAnalysis({
    required this.byInterval,
    required this.compositeScore,
    required this.agreementPercent,
    required this.bias,
    required this.confidence,
  });

  final Map<String, TechnicalAnalysis> byInterval;
  final int compositeScore;
  final double agreementPercent;
  final String bias;
  final double confidence;

  bool get isConfirmed => agreementPercent >= 75;
}
