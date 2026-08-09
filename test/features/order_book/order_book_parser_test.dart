import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/order_book/domain/order_book_parser.dart';

void main() {
  const parser = OrderBookParser();

  test('parses Binance partial depth JSON', () {
    final snapshot = parser.parse(
      '{"lastUpdateId":1,"bids":[["100","2"],["99","3"]],"asks":[["101","4"],["102","5"]]}',
      defaultSymbol: 'BTCUSDT',
    );

    expect(snapshot.symbol, 'BTCUSDT');
    expect(snapshot.bestBid, 100);
    expect(snapshot.bestAsk, 101);
    expect(snapshot.bids, hasLength(2));
  });

  test('round trips Nexora clipboard format', () {
    final original = parser.parse(
      '{"bids":[["100","2"]],"asks":[["101","4"]]}',
      defaultSymbol: 'ETHUSDT',
    );

    final restored = parser.parse(original.toClipboardText());

    expect(restored.symbol, 'ETHUSDT');
    expect(restored.bestBid, original.bestBid);
    expect(restored.bestAsk, original.bestAsk);
  });

  test('rejects a snapshot without both sides', () {
    expect(() => parser.parse('VENTAS\n101 4'), throwsFormatException);
  });
}
