import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

void main() {
  List<Candle> candles({required double drift, double volumeBase = 100}) {
    final result = <Candle>[];
    var price = 100.0;
    for (var i = 0; i < 30; i++) {
      final open = price;
      price += drift;
      result.add(Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch(i * 60000),
        open: open,
        high: (open > price ? open : price) + 0.05,
        low: (open < price ? open : price) - 0.05,
        close: price,
        volume: volumeBase + i * 3,
      ));
    }
    return result;
  }

  test('produces bullish signal when momentum and book agree', () {
    final signal = const PulseEngine().analyze(
      candles: candles(drift: 0.12),
      bidVolume: 1800,
      askVolume: 700,
    );

    expect(signal.score, greaterThan(0));
    expect(signal.confidence, inInclusiveRange(50, 90));
    expect(signal.direction, isNot(PulseDirection.down));
  });

  test('produces bearish signal when momentum and book agree', () {
    final signal = const PulseEngine().analyze(
      candles: candles(drift: -0.12),
      bidVolume: 650,
      askVolume: 1900,
    );

    expect(signal.score, lessThan(0));
    expect(signal.direction, isNot(PulseDirection.up));
  });

  test('uses no-trade when directional evidence is weak', () {
    final signal = const PulseEngine().analyze(
      candles: candles(drift: 0.001, volumeBase: 100),
      bidVolume: 1000,
      askVolume: 1000,
    );

    expect(signal.direction, PulseDirection.noTrade);
  });

  test('rejects insufficient candle history', () {
    expect(
      () => const PulseEngine().analyze(
        candles: candles(drift: 0.1).take(10).toList(),
        bidVolume: 100,
        askVolume: 100,
      ),
      throwsArgumentError,
    );
  });
}
