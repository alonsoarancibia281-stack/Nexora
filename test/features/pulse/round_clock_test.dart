import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_horizon.dart';
import 'package:nexora_markets_ai/features/pulse/domain/round_clock.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 14, 37, 20);

  test('five minute round snaps to the closest five minute bucket', () {
    final window = RoundWindow.at(PredictionHorizon.m5, now);
    expect(window.start, DateTime.utc(2026, 8, 16, 14, 35));
    expect(window.end, DateTime.utc(2026, 8, 16, 14, 40));
    expect(window.secondsLeft(now), 160);
  });

  test('fifteen minute round snaps to the quarter', () {
    final window = RoundWindow.at(PredictionHorizon.m15, now);
    expect(window.start, DateTime.utc(2026, 8, 16, 14, 30));
    expect(window.end, DateTime.utc(2026, 8, 16, 14, 45));
  });

  test('one hour round snaps to the hour', () {
    final window = RoundWindow.at(PredictionHorizon.h1, now);
    expect(window.start, DateTime.utc(2026, 8, 16, 14));
    expect(window.end, DateTime.utc(2026, 8, 16, 15));
    expect(window.secondsLeft(now), 1360);
  });

  test('progress grows from zero to one inside the round', () {
    final window = RoundWindow.at(PredictionHorizon.m5, now);
    expect(window.progress(window.start), 0);
    expect(window.progress(window.end), 1);
    expect(
      window.progress(window.start.add(const Duration(minutes: 1))),
      closeTo(.2, .001),
    );
  });

  test('closed round rolls into the next one', () {
    final window = RoundWindow.at(PredictionHorizon.m5, now);
    expect(window.isClosed(now), isFalse);
    expect(window.isClosed(window.end), isTrue);
    expect(window.next.start, window.end);
    expect(window.nextCloses(3), [
      DateTime.utc(2026, 8, 16, 14, 40),
      DateTime.utc(2026, 8, 16, 14, 45),
      DateTime.utc(2026, 8, 16, 14, 50),
    ]);
  });

  test('exchange clock adopts the first measurement and smooths the rest', () {
    final clock = ExchangeClock();
    expect(clock.isSynced, isFalse);

    final before = DateTime.utc(2026, 8, 16, 14, 0, 0);
    final after = DateTime.utc(2026, 8, 16, 14, 0, 0, 200);
    clock.apply(
      before: before,
      serverTime: before.add(const Duration(seconds: 4)),
      after: after,
    );
    expect(clock.isSynced, isTrue);
    expect(clock.offset.inMilliseconds, closeTo(3900, 120));

    // A small correction only moves the offset part of the way.
    clock.apply(
      before: before,
      serverTime: before.add(const Duration(seconds: 4, milliseconds: 400)),
      after: after,
    );
    expect(clock.offset.inMilliseconds, lessThan(4300));
    expect(clock.offset.inMilliseconds, greaterThan(3900));
  });
}
