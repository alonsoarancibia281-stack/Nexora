import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_math_council.dart';

MathContext context({
  required double drift,
  double noise = 0,
  int bars = 90,
  int secondsRemaining = 240,
  double bookImbalance = 0,
  double aggressorImbalance = 0,
}) {
  final random = math.Random(7);
  final closes = <double>[];
  final highs = <double>[];
  final lows = <double>[];
  final volumes = <double>[];
  var price = 60000.0;
  for (var i = 0; i < bars; i++) {
    price *= 1 + drift + (random.nextDouble() - .5) * noise;
    closes.add(price);
    highs.add(price * 1.0004);
    lows.add(price * .9996);
    volumes.add(120 + random.nextDouble() * 40);
  }
  return MathContext(
    closes: closes,
    highs: highs,
    lows: lows,
    volumes: volumes,
    roundStartPrice: closes[closes.length - 4],
    secondsRemaining: secondsRemaining,
    bookImbalance: bookImbalance,
    aggressorImbalance: aggressorImbalance,
    signedVolume: aggressorImbalance,
    spreadBps: .8,
    micropriceEdge: 0,
    instability: 25,
  );
}

void main() {
  const council = PulseMathCouncil();

  test('publishes exactly fifty theorems across ten branches', () {
    final briefing = council.deliberate(context(drift: .0004, noise: .0006));

    expect(briefing.isReady, isTrue);
    expect(briefing.theorems, hasLength(PulseMathCouncil.mathematicians));
    expect(briefing.theorems.map((t) => t.id).toSet(), hasLength(50));
    for (final branch in MathBranch.values) {
      expect(briefing.theoremsOf(branch), hasLength(5));
    }
  });

  test('every theorem stays numerically well behaved', () {
    final briefing = council.deliberate(context(drift: -.0007, noise: .0012));

    for (final theorem in briefing.theorems) {
      expect(theorem.signal.isFinite, isTrue, reason: theorem.name);
      expect(theorem.signal, inInclusiveRange(-1, 1), reason: theorem.name);
      expect(theorem.confidence, inInclusiveRange(0, 1), reason: theorem.name);
      expect(theorem.value.isFinite, isTrue, reason: theorem.name);
      expect(theorem.formula, isNotEmpty);
    }
    expect(briefing.probabilityUp, inInclusiveRange(.05, .95));
  });

  test('a clean uptrend leans bullish and a downtrend leans bearish', () {
    final up = council.deliberate(context(drift: .0009, noise: .0002));
    final down = council.deliberate(context(drift: -.0009, noise: .0002));

    expect(up.probabilityUp, greaterThan(down.probabilityUp));
    expect(up.consensusSignal, greaterThan(down.consensusSignal));
  });

  test('reports a neutral briefing when history is too short', () {
    final briefing = council.deliberate(context(drift: .001, bars: 12));

    expect(briefing.isReady, isFalse);
    expect(briefing.probabilityUp, .5);
    expect(briefing.mathematicians, 0);
  });

  test('flat noise keeps the council close to a coin flip', () {
    final briefing = council.deliberate(context(drift: 0, noise: .0004));

    expect((briefing.probabilityUp - .5).abs(), lessThan(.30));
  });
}
