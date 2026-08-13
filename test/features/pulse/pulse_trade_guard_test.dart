import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_round_plan.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_trade_guard.dart';

void main() {
  final start = DateTime.utc(2026, 8, 13, 12);

  PulseRoundPlan plan({required bool up}) => PulseRoundPlan(
        roundStart: start,
        roundEnd: start.add(const Duration(minutes: 5)),
        entryPrice: 45000,
        direction: up ? PulseDirection.up : PulseDirection.down,
        probabilityUp: up ? .68 : .32,
        expectedMovePct: .12,
        targetPrice: up ? 45054 : 44946,
        invalidationPrice: up ? 44955 : 45045,
        drivers: const <String>['prueba'],
        strategy: 'prueba',
        lockedAtSecondsRemaining: 240,
        analystAgreement: .7,
        councilAgreement: .7,
      );

  group('trade guard', () {
    test('a long is watched from the price it was armed at', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45010);

      expect(guard.state, GuardState.armed);
      expect(guard.action, TradeAction.buy);
      expect(guard.entryPrice, 45010);
      expect(guard.invalidationPrice, 44955);
    });

    test('a position in profit never reports an adverse move', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 45080, probabilityUp: .7, secondsRemaining: 180);

      expect(guard.state, GuardState.armed);
      expect(guard.adversePct, 0);
    });

    test('breaking the invalidation level closes the long', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 44950, probabilityUp: .6, secondsRemaining: 180);

      expect(guard.state, GuardState.triggered);
      expect(guard.reason, GuardReason.invalidation);
      expect(guard.adversePct, closeTo(.111, .01));
    });

    test('breaking the invalidation level closes the short', () {
      final guard = TradeGuard.arm(plan: plan(up: false), price: 45000)
          .evaluate(price: 45050, probabilityUp: .4, secondsRemaining: 180);

      expect(guard.action, TradeAction.sell);
      expect(guard.state, GuardState.triggered);
      expect(guard.reason, GuardReason.invalidation);
    });

    test('the council turning around closes the position on its own', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 44990, probabilityUp: .30, secondsRemaining: 180);

      expect(guard.state, GuardState.triggered);
      expect(guard.reason, GuardReason.councilReversed);
    });

    test('a reversal in the last seconds is not worth acting on', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 44990, probabilityUp: .30, secondsRemaining: 12);

      expect(guard.state, GuardState.armed);
    });

    test('the end of the round closes whatever is still open', () {
      final guard = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 45010, probabilityUp: .7, secondsRemaining: 0);

      expect(guard.state, GuardState.triggered);
      expect(guard.reason, GuardReason.roundClosed);
    });

    test('once triggered a bounce does not un-trigger it', () {
      final triggered = TradeGuard.arm(plan: plan(up: true), price: 45000)
          .evaluate(price: 44950, probabilityUp: .6, secondsRemaining: 180);
      final after = triggered
          .evaluate(price: 45100, probabilityUp: .8, secondsRemaining: 120);

      expect(after.state, GuardState.triggered);
      expect(after.reason, GuardReason.invalidation);
      expect(after.adversePct, 0);
    });

    test('an unwatched position is left alone', () {
      final guard = TradeGuard.off
          .evaluate(price: 1, probabilityUp: .01, secondsRemaining: 10);

      expect(guard.state, GuardState.off);
    });

    test('an abstention is not an order', () {
      expect(
        TradeGuard.actionFor(direction: PulseDirection.up, hasReading: false),
        TradeAction.wait,
      );
      expect(
        TradeGuard.actionFor(direction: PulseDirection.down, hasReading: true),
        TradeAction.sell,
      );
    });
  });
}
