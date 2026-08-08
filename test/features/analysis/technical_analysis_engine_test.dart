import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/analysis/services/technical_analysis_engine.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';

void main() {
  final engine = TechnicalAnalysisEngine();

  List<Candle> risingCandles() => List.generate(250, (index) {
        final base = 100 + index * 0.5;
        return Candle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
          open: base,
          high: base + 1.2,
          low: base - 0.8,
          close: base + 0.6,
          volume: 1000 + index.toDouble(),
        );
      });

  test('returns bounded score and finite indicators', () {
    final analysis = engine.analyze(risingCandles());

    expect(analysis.score, inInclusiveRange(-100, 100));
    expect(analysis.confidence, inInclusiveRange(0, 100));
    expect(analysis.rsi.isFinite, isTrue);
    expect(analysis.ema200.isFinite, isTrue);
    expect(analysis.atr, greaterThan(0));
    expect(analysis.resistance, greaterThanOrEqualTo(analysis.support));
  });

  test('rejects insufficient candle history', () {
    expect(
      () => engine.analyze(risingCandles().take(100).toList()),
      throwsArgumentError,
    );
  });
}
