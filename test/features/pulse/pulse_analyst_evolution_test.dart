import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_analyst_evolution.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_analyst_genome.dart';

List<AnalystVote> votes(PulseEvolutionState state, {required bool bullish}) => [
      for (final genome in state.genomes)
        AnalystVote(
          // Odd analysts always call "up", even analysts always call "down",
          // so a known half of the population must be rewarded.
          id: genome.id,
          probabilityUp: genome.id.isOdd ? .82 : .18,
          active: true,
          quality: .6,
        ),
    ];

void main() {
  const engine = PulseEvolutionEngine();

  test('bootstraps one hundred analysts with distinct genomes', () {
    final state = PulseEvolutionState.bootstrap();

    expect(state.genomes, hasLength(PulseEvolutionEngine.populationSize));
    expect(state.genomes.map((g) => g.id).toSet(), hasLength(100));
    for (final family in AnalystFamily.values) {
      expect(state.genomes.where((g) => g.family == family), hasLength(10));
    }
    final temperatures = state.genomes.map((g) => g.temperature).toSet();
    expect(temperatures.length, greaterThan(50));
  });

  test('rewards the analysts that called the round correctly', () {
    var state = PulseEvolutionState.bootstrap();
    for (var round = 0; round < 5; round++) {
      state = engine.learn(
        state,
        wentUp: true,
        votes: votes(state, bullish: true),
        consensusProbabilityUp: .62,
      );
    }

    final bullish = state.recordOf(1);
    final bearish = state.recordOf(2);
    expect(bullish.weight, greaterThan(bearish.weight));
    expect(bullish.reliability, greaterThan(bearish.reliability));
    expect(bullish.ewmaBrier, lessThan(bearish.ewmaBrier));
    expect(state.roundsObserved, 5);
    expect(state.hits, 5);
  });

  test('continuous reviews add experience without counting as rounds', () {
    var state = PulseEvolutionState.bootstrap();
    state = engine.learn(
      state,
      wentUp: false,
      votes: votes(state, bullish: false),
      consensusProbabilityUp: .44,
      intensity: .3,
      closedRound: false,
    );

    expect(state.roundsObserved, 0);
    expect(state.scored, 0);
    expect(state.experience, closeTo(.3, 1e-9));
  });

  test('evolves a new generation once enough experience accumulates', () {
    var state = PulseEvolutionState.bootstrap();
    for (var round = 0; round < 10; round++) {
      state = engine.learn(
        state,
        wentUp: true,
        votes: votes(state, bullish: true),
        consensusProbabilityUp: .66,
      );
    }

    expect(state.generation, greaterThanOrEqualTo(1));
    expect(state.genomes, hasLength(PulseEvolutionEngine.populationSize));
    final children =
        state.genomes.where((g) => g.lineage.startsWith('g')).toList();
    expect(children, isNotEmpty);
    // Children keep the family slot they were born into.
    for (final child in children) {
      expect(
        state.genomes.firstWhere((g) => g.id == child.id).family,
        child.family,
      );
    }
  });

  test('learned calibration survives a JSON round trip', () {
    var state = PulseEvolutionState.bootstrap();
    for (var round = 0; round < 4; round++) {
      state = engine.learn(
        state,
        wentUp: round.isEven,
        votes: votes(state, bullish: round.isEven),
        consensusProbabilityUp: round.isEven ? .70 : .35,
      );
    }

    final restored = PulseEvolutionState.fromJson(state.toJson());
    expect(restored, isNotNull);
    expect(restored!.genomes, hasLength(100));
    expect(restored.generation, state.generation);
    expect(restored.roundsObserved, state.roundsObserved);
    expect(restored.calibrationSlope, closeTo(state.calibrationSlope, 1e-9));
    expect(restored.recordOf(1).weight, closeTo(state.recordOf(1).weight, 1e-9));
  });

  test('short-horizon reviews never move the round calibration', () {
    var state = PulseEvolutionState.bootstrap();
    final slope = state.calibrationSlope;
    final intercept = state.calibrationIntercept;

    // Ten intra-round reviews, all resolving the same way.
    for (var review = 0; review < 10; review++) {
      state = engine.learn(
        state,
        wentUp: true,
        votes: votes(state, bullish: true),
        consensusProbabilityUp: .30,
        intensity: .10,
        closedRound: false,
      );
    }

    expect(state.calibrationSlope, slope);
    expect(state.calibrationIntercept, intercept);
    // The analysts still learn from them, only the calibration is protected.
    expect(state.experience, greaterThan(0));
    expect(state.recordOf(1).weight, greaterThan(state.recordOf(2).weight));

    final closed = engine.learn(
      state,
      wentUp: true,
      votes: votes(state, bullish: true),
      consensusProbabilityUp: .30,
    );
    expect(
      closed.calibrationSlope != slope ||
          closed.calibrationIntercept != intercept,
      isTrue,
      reason: 'a closed round must be allowed to move the calibration',
    );
  });

  test('calibration maps probabilities back into a valid range', () {
    final state = PulseEvolutionState.bootstrap();
    for (final p in <double>[.01, .2, .5, .8, .99]) {
      final calibrated = state.calibrate(p);
      expect(calibrated, inInclusiveRange(.02, .98));
      expect(calibrated.isFinite, isTrue);
    }
    expect(state.calibrate(.5), closeTo(.5, 1e-9));
  });
}
