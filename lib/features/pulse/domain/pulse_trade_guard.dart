import 'dart:math' as math;

import 'pulse_round_plan.dart';
import 'pulse_signal.dart';

/// The call expressed as the action the user would take on the exchange.
enum TradeAction { buy, sell, wait }

/// Lifecycle of the protection the user arms over their own position.
enum GuardState {
  /// Not watching anything.
  off,

  /// Watching a position against the round's invalidation level.
  armed,

  /// The market went against the call; the position should be closed.
  triggered,
}

/// Why the guard fired.
enum GuardReason { none, invalidation, councilReversed, roundClosed }

/// Watches a position the user opened by hand and says when to get out.
///
/// Nexora places no orders: it holds no exchange credentials and cannot touch
/// anyone's balance. What it can do is watch the same round it predicted and
/// call the position dead the moment the premise breaks — while the user is
/// looking at the exchange, not at Nexora.
class TradeGuard {
  const TradeGuard({
    required this.state,
    required this.action,
    required this.entryPrice,
    required this.invalidationPrice,
    required this.adversePct,
    required this.reason,
  });

  final GuardState state;
  final TradeAction action;

  /// Price the position is measured from — the price when the guard was armed.
  final double entryPrice;

  /// Level that kills the thesis, from the round plan.
  final double invalidationPrice;

  /// How far the market has moved against the position, in percent. Never
  /// negative: a position in profit reads zero.
  final double adversePct;

  final GuardReason reason;

  static const TradeGuard off = TradeGuard(
    state: GuardState.off,
    action: TradeAction.wait,
    entryPrice: 0,
    invalidationPrice: 0,
    adversePct: 0,
    reason: GuardReason.none,
  );

  bool get isArmed => state == GuardState.armed;

  bool get isTriggered => state == GuardState.triggered;

  /// Probability of the called side below which the council is considered to
  /// have changed its mind rather than merely hesitated.
  static const double reversalProbability = .40;

  String get actionLabel => switch (action) {
        TradeAction.buy => 'COMPRAR',
        TradeAction.sell => 'VENDER',
        TradeAction.wait => 'ESPERAR',
      };

  String get reasonLabel => switch (reason) {
        GuardReason.invalidation => 'el precio rompió el nivel de invalidación',
        GuardReason.councilReversed => 'el consejo se dio la vuelta',
        GuardReason.roundClosed => 'la ronda terminó',
        GuardReason.none => '',
      };

  /// Arms the guard over the position the user just opened.
  static TradeGuard arm({
    required PulseRoundPlan plan,
    required double price,
  }) =>
      TradeGuard(
        state: GuardState.armed,
        action: plan.isUp ? TradeAction.buy : TradeAction.sell,
        entryPrice: price > 0 ? price : plan.entryPrice,
        invalidationPrice: plan.invalidationPrice,
        adversePct: 0,
        reason: GuardReason.none,
      );

  /// Re-reads the position against the market. Once triggered it stays
  /// triggered: a stop that un-trips itself on a bounce is not a stop.
  TradeGuard evaluate({
    required double price,
    required double probabilityUp,
    required int secondsRemaining,
  }) {
    if (state == GuardState.off || price <= 0 || entryPrice <= 0) return this;

    final long = action == TradeAction.buy;
    final movePct = (price - entryPrice) / entryPrice * 100;
    final adverse = math.max(long ? -movePct : movePct, 0).toDouble();

    if (state == GuardState.triggered) {
      return _copy(adversePct: adverse);
    }

    if (secondsRemaining <= 0) {
      return _copy(
        state: GuardState.triggered,
        adversePct: adverse,
        reason: GuardReason.roundClosed,
      );
    }

    final broken = invalidationPrice > 0 &&
        (long ? price <= invalidationPrice : price >= invalidationPrice);
    if (broken) {
      return _copy(
        state: GuardState.triggered,
        adversePct: adverse,
        reason: GuardReason.invalidation,
      );
    }

    // The council changing its mind is its own exit signal, but only while
    // there is still round left to lose money in.
    final sideProbability = long ? probabilityUp : 1 - probabilityUp;
    if (secondsRemaining > 30 && sideProbability < reversalProbability) {
      return _copy(
        state: GuardState.triggered,
        adversePct: adverse,
        reason: GuardReason.councilReversed,
      );
    }

    return _copy(adversePct: adverse);
  }

  TradeGuard _copy({
    GuardState? state,
    double? adversePct,
    GuardReason? reason,
  }) =>
      TradeGuard(
        state: state ?? this.state,
        action: action,
        entryPrice: entryPrice,
        invalidationPrice: invalidationPrice,
        adversePct: adversePct ?? this.adversePct,
        reason: reason ?? this.reason,
      );

  /// The action a verdict implies, before any position exists.
  static TradeAction actionFor({
    required PulseDirection direction,
    required bool hasReading,
  }) {
    if (!hasReading) return TradeAction.wait;
    return switch (direction) {
      PulseDirection.up => TradeAction.buy,
      PulseDirection.down => TradeAction.sell,
      PulseDirection.noTrade => TradeAction.wait,
    };
  }
}
