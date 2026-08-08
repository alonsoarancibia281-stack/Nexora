import '../../market/data/binance_market_service.dart';
import '../domain/multi_timeframe_analysis.dart';
import '../domain/technical_analysis.dart';
import 'technical_analysis_engine.dart';

class MultiTimeframeAnalysisService {
  MultiTimeframeAnalysisService({
    BinanceMarketService? marketService,
    TechnicalAnalysisEngine? engine,
  })  : _marketService = marketService ?? BinanceMarketService(),
        _engine = engine ?? TechnicalAnalysisEngine();

  final BinanceMarketService _marketService;
  final TechnicalAnalysisEngine _engine;

  static const _intervals = ['15m', '1h', '4h', '1d'];
  static const _weights = {
    '15m': 0.15,
    '1h': 0.25,
    '4h': 0.35,
    '1d': 0.25,
  };

  Future<MultiTimeframeAnalysis> analyze(String symbol) async {
    final results = await Future.wait(
      _intervals.map((interval) async {
        final candles = await _marketService.loadCandles(
          symbol,
          interval,
          limit: 250,
        );
        return MapEntry(interval, _engine.analyze(candles));
      }),
    );

    final byInterval = Map<String, TechnicalAnalysis>.fromEntries(results);
    var weightedScore = 0.0;
    var weightedConfidence = 0.0;

    for (final entry in byInterval.entries) {
      final weight = _weights[entry.key]!;
      weightedScore += entry.value.score * weight;
      weightedConfidence += entry.value.confidence * weight;
    }

    final compositeScore = weightedScore.round().clamp(-100, 100);
    final referenceSign = compositeScore == 0 ? 0 : compositeScore.sign;
    final agreeingWeight = byInterval.entries.fold<double>(0, (sum, entry) {
      final sign = entry.value.score == 0 ? 0 : entry.value.score.sign;
      return sign == referenceSign ? sum + _weights[entry.key]! : sum;
    });
    final agreementPercent = (agreeingWeight * 100).clamp(0, 100).toDouble();

    final bias = compositeScore >= 70
        ? 'Sesgo alcista fuerte confirmado'
        : compositeScore >= 35
            ? 'Sesgo alcista moderado'
            : compositeScore <= -70
                ? 'Sesgo bajista fuerte confirmado'
                : compositeScore <= -35
                    ? 'Sesgo bajista moderado'
                    : 'Sin sesgo multitemporal claro';

    final confidence = (weightedConfidence * (0.5 + agreementPercent / 200))
        .clamp(0, 100)
        .toDouble();

    return MultiTimeframeAnalysis(
      byInterval: byInterval,
      compositeScore: compositeScore,
      agreementPercent: agreementPercent,
      bias: bias,
      confidence: confidence,
    );
  }
}
