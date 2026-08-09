import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/order_book/domain/order_book_parser.dart';
import 'package:nexora_markets_ai/features/order_book/domain/order_book_prediction.dart';
import 'package:nexora_markets_ai/features/order_book/domain/order_book_prediction_engine.dart';

void main() {
  const parser = OrderBookParser();
  const engine = OrderBookPredictionEngine();

  test('detects stronger bid-side pressure without claiming certainty', () {
    final snapshot = parser.parse(
      '{"bids":[["100","12"],["99","8"]],"asks":[["101","2"],["102","2"]]}',
    );

    final result = engine.analyze(snapshot);

    expect(result.bias, OrderBookBias.bullish);
    expect(result.score, inInclusiveRange(-100, 100));
    expect(result.confidence, inInclusiveRange(45, 82));
    expect(result.upProbability, lessThanOrEqualTo(85));
    expect(result.activeAnalysts, 100);
    expect(result.teamOpinions, hasLength(10));
    expect(result.agreement, inInclusiveRange(0, 1));
  });

  test('returns neutral when both sides are balanced', () {
    final snapshot = parser.parse(
      '{"bids":[["100","5"]],"asks":[["101","5"]]}',
    );

    final result = engine.analyze(snapshot);

    expect(result.bias, OrderBookBias.neutral);
    expect(result.upProbability, closeTo(50, 0.01));
    expect(result.activeAnalysts, 100);
    expect(result.agreement, 0);
  });

  test('candle desks confirm a rising market with balanced liquidity', () {
    final snapshot = parser.parse(
      '{"bids":[["100.00","5"]],"asks":[["100.01","5"]]}',
    );
    final candles = List.generate(30, (index) {
      final open = 95 + index * .18;
      return Candle(
        openTime: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
        open: open,
        high: open + .24,
        low: open - .03,
        close: open + .20,
        volume: 100 + index * 4,
      );
    });

    final result = engine.analyze(snapshot, candles: candles);

    expect(result.bias, OrderBookBias.bullish);
    expect(result.teamOpinions, hasLength(10));
    expect(
      result.teamOpinions
          .where(
              (team) => team.family.index >= OrderBookAnalystFamily.trend.index)
          .every((team) => team.probabilityUp > .5),
      isTrue,
    );
  });
}
