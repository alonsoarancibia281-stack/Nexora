import 'dart:math' as math;

import 'pulse_analyst_genome.dart';

/// One analyst's vote in a single evaluation, kept so the outcome can later be
/// attributed back to the analyst that produced it.
class AnalystVote {
  const AnalystVote({
    required this.id,
    required this.probabilityUp,
    required this.active,
    required this.quality,
  });

  final int id;
  final double probabilityUp;
  final bool active;
  final double quality;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'p': probabilityUp,
        'a': active,
        'q': quality,
      };

  static AnalystVote? fromJson(Map<String, dynamic> json) {
    try {
      return AnalystVote(
        id: (json['id'] as num).toInt(),
        probabilityUp: (json['p'] as num).toDouble(),
        active: json['a'] == true,
        quality: (json['q'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Rolling out-of-sample track record of one analyst.
class AnalystRecord {
  const AnalystRecord({
    required this.id,
    required this.alpha,
    required this.beta,
    required this.ewmaBrier,
    required this.weight,
    required this.experience,
    required this.bornAtGeneration,
  });

  const AnalystRecord.prior(this.id, {this.bornAtGeneration = 0})
      : alpha = 1,
        beta = 1,
        ewmaBrier = .25,
        weight = 1,
        experience = 0;

  final int id;

  /// Beta posterior of directional accuracy.
  final double alpha;
  final double beta;

  /// Exponentially weighted Brier score (0 perfect, .25 coin flip).
  final double ewmaBrier;

  /// Multiplicative-weights (Hedge) trust factor.
  final double weight;

  /// Accumulated learning intensity, not a raw count of rounds.
  final double experience;

  final int bornAtGeneration;

  double get reliability => alpha / (alpha + beta);

  /// Brier skill score against a coin flip; negative means harmful.
  double get skill => (1 - ewmaBrier / .25).clamp(-1.0, 1.0).toDouble();

  /// Shrunk fitness: young analysts cannot claim elite status on luck alone.
  double get fitness {
    final shrink = experience / (experience + 6);
    final directional = (reliability - .5) * 2;
    return ((skill * .62 + directional * .38) * shrink).clamp(-1.0, 1.0).toDouble();
  }

  AnalystRecord copyWith({
    double? alpha,
    double? beta,
    double? ewmaBrier,
    double? weight,
    double? experience,
    int? bornAtGeneration,
  }) =>
      AnalystRecord(
        id: id,
        alpha: alpha ?? this.alpha,
        beta: beta ?? this.beta,
        ewmaBrier: ewmaBrier ?? this.ewmaBrier,
        weight: weight ?? this.weight,
        experience: experience ?? this.experience,
        bornAtGeneration: bornAtGeneration ?? this.bornAtGeneration,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'al': alpha,
        'be': beta,
        'br': ewmaBrier,
        'w': weight,
        'x': experience,
        'g': bornAtGeneration,
      };

  static AnalystRecord? fromJson(Map<String, dynamic> json) {
    try {
      return AnalystRecord(
        id: (json['id'] as num).toInt(),
        alpha: (json['al'] as num).toDouble().clamp(.2, 400).toDouble(),
        beta: (json['be'] as num).toDouble().clamp(.2, 400).toDouble(),
        ewmaBrier: (json['br'] as num).toDouble().clamp(0.0, 1.0).toDouble(),
        weight: (json['w'] as num).toDouble().clamp(.02, 8.0).toDouble(),
        experience:
            ((json['x'] as num?)?.toDouble() ?? 0).clamp(0.0, 1e6).toDouble(),
        bornAtGeneration: (json['g'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Everything the council remembers between rounds.
class PulseEvolutionState {
  const PulseEvolutionState({
    required this.genomes,
    required this.records,
    required this.generation,
    required this.roundsObserved,
    required this.experience,
    required this.experienceSinceGeneration,
    required this.calibrationSlope,
    required this.calibrationIntercept,
    required this.hits,
    required this.scored,
    required this.consensusBrier,
    required this.lastEvolutionEpochMs,
  });

  final List<AnalystGenome> genomes;
  final Map<int, AnalystRecord> records;
  final int generation;

  /// Closed 5-minute rounds that produced a verdict.
  final int roundsObserved;

  /// Total accumulated learning intensity (rounds + continuous reviews).
  final double experience;
  final double experienceSinceGeneration;

  /// Online Platt calibration of the consensus probability.
  final double calibrationSlope;
  final double calibrationIntercept;

  final int hits;
  final int scored;
  final double consensusBrier;
  final int lastEvolutionEpochMs;

  static PulseEvolutionState bootstrap() {
    final genomes = AnalystGenome.foundingPopulation();
    return PulseEvolutionState(
      genomes: List<AnalystGenome>.unmodifiable(genomes),
      records: Map<int, AnalystRecord>.unmodifiable({
        for (final g in genomes) g.id: AnalystRecord.prior(g.id),
      }),
      generation: 0,
      roundsObserved: 0,
      experience: 0,
      experienceSinceGeneration: 0,
      calibrationSlope: 1,
      calibrationIntercept: 0,
      hits: 0,
      scored: 0,
      consensusBrier: .25,
      lastEvolutionEpochMs: 0,
    );
  }

  AnalystRecord recordOf(int id) =>
      records[id] ?? AnalystRecord.prior(id, bornAtGeneration: generation);

  double weightOf(int id) => recordOf(id).weight;

  double reliabilityOf(int id) => recordOf(id).reliability;

  double get accuracy => scored == 0 ? 0 : hits / scored;

  /// Brier skill score of the fused consensus against a coin flip.
  double get consensusSkill =>
      (1 - consensusBrier / .25).clamp(-1.0, 1.0).toDouble();

  bool get hasUsefulSample => scored >= 40;

  /// Applies the learned Platt transform to a raw consensus probability.
  double calibrate(double rawProbabilityUp) {
    final p = rawProbabilityUp.clamp(1e-4, 1 - 1e-4);
    final z = calibrationSlope * math.log(p / (1 - p)) + calibrationIntercept;
    return (1 / (1 + math.exp(-z.clamp(-30.0, 30.0))))
        .clamp(.02, .98)
        .toDouble();
  }

  List<AnalystRecord> rankedRecords() {
    final list = records.values.toList()
      ..sort((a, b) => b.fitness.compareTo(a.fitness));
    return list;
  }

  PulseEvolutionState copyWith({
    List<AnalystGenome>? genomes,
    Map<int, AnalystRecord>? records,
    int? generation,
    int? roundsObserved,
    double? experience,
    double? experienceSinceGeneration,
    double? calibrationSlope,
    double? calibrationIntercept,
    int? hits,
    int? scored,
    double? consensusBrier,
    int? lastEvolutionEpochMs,
  }) =>
      PulseEvolutionState(
        genomes: genomes ?? this.genomes,
        records: records ?? this.records,
        generation: generation ?? this.generation,
        roundsObserved: roundsObserved ?? this.roundsObserved,
        experience: experience ?? this.experience,
        experienceSinceGeneration:
            experienceSinceGeneration ?? this.experienceSinceGeneration,
        calibrationSlope: calibrationSlope ?? this.calibrationSlope,
        calibrationIntercept: calibrationIntercept ?? this.calibrationIntercept,
        hits: hits ?? this.hits,
        scored: scored ?? this.scored,
        consensusBrier: consensusBrier ?? this.consensusBrier,
        lastEvolutionEpochMs: lastEvolutionEpochMs ?? this.lastEvolutionEpochMs,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': 2,
        'genomes': [for (final g in genomes) g.toJson()],
        'records': [for (final r in records.values) r.toJson()],
        'generation': generation,
        'rounds': roundsObserved,
        'xp': experience,
        'xpGen': experienceSinceGeneration,
        'ca': calibrationSlope,
        'cb': calibrationIntercept,
        'hits': hits,
        'scored': scored,
        'brier': consensusBrier,
        'evo': lastEvolutionEpochMs,
      };

  static PulseEvolutionState? fromJson(Map<String, dynamic> json) {
    try {
      if ((json['v'] as num?)?.toInt() != 2) return null;
      final genomes = <AnalystGenome>[];
      for (final raw in (json['genomes'] as List<dynamic>)) {
        final g = AnalystGenome.fromJson(raw as Map<String, dynamic>);
        if (g != null) genomes.add(g);
      }
      if (genomes.length != PulseEvolutionEngine.populationSize) return null;
      final records = <int, AnalystRecord>{};
      for (final raw in (json['records'] as List<dynamic>)) {
        final r = AnalystRecord.fromJson(raw as Map<String, dynamic>);
        if (r != null) records[r.id] = r;
      }
      for (final g in genomes) {
        records.putIfAbsent(g.id, () => AnalystRecord.prior(g.id));
      }
      return PulseEvolutionState(
        genomes: List<AnalystGenome>.unmodifiable(genomes),
        records: Map<int, AnalystRecord>.unmodifiable(records),
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        roundsObserved: (json['rounds'] as num?)?.toInt() ?? 0,
        experience: (json['xp'] as num?)?.toDouble() ?? 0,
        experienceSinceGeneration: (json['xpGen'] as num?)?.toDouble() ?? 0,
        calibrationSlope:
            ((json['ca'] as num?)?.toDouble() ?? 1).clamp(.2, 3.0).toDouble(),
        calibrationIntercept:
            ((json['cb'] as num?)?.toDouble() ?? 0).clamp(-1.2, 1.2).toDouble(),
        hits: (json['hits'] as num?)?.toInt() ?? 0,
        scored: (json['scored'] as num?)?.toInt() ?? 0,
        consensusBrier:
            ((json['brier'] as num?)?.toDouble() ?? .25).clamp(0.0, 1.0).toDouble(),
        lastEvolutionEpochMs: (json['evo'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Online learning plus genetic evolution for the 100 analysts.
///
/// Learning happens on two clocks:
///  * every continuous market review, scoring the population against the move
///    that happened since the previous review. This is a *proxy*: the analysts
///    are forecasting a 5-minute close, not a 30-second wiggle, so these
///    updates run at low intensity and never touch the calibration.
///  * every closed 5-minute round, at full intensity, against the outcome the
///    analysts were actually asked to predict. This is the update that counts.
///
/// Once enough experience accumulates, the weakest analysts are replaced by
/// crossover children of the elite, which is what makes the population evolve
/// instead of merely re-weighting itself.
class PulseEvolutionEngine {
  const PulseEvolutionEngine({
    this.learningRate = 1.35,
    this.brierMemory = .06,
    this.posteriorDecay = .994,
    this.calibrationRate = .045,
    this.experiencePerGeneration = 9.0,
    this.replaceFraction = .18,
    this.eliteFraction = .25,
  });

  static const int populationSize = 100;

  /// Hedge learning rate for the multiplicative weights update.
  final double learningRate;

  /// Weight of a fresh observation inside the EWMA Brier score.
  final double brierMemory;

  /// Forgetting factor of the Beta posterior, so old skill decays.
  final double posteriorDecay;

  final double calibrationRate;
  final double experiencePerGeneration;
  final double replaceFraction;
  final double eliteFraction;

  /// Feeds one realised outcome back into the population.
  ///
  /// [intensity] is 1 for a closed round and a fraction for the continuous
  /// intra-round reviews.
  PulseEvolutionState learn(
    PulseEvolutionState state, {
    required bool wentUp,
    required List<AnalystVote> votes,
    required double consensusProbabilityUp,
    double intensity = 1.0,
    bool closedRound = true,
  }) {
    if (votes.isEmpty) return state;
    final y = wentUp ? 1.0 : 0.0;
    final k = intensity.clamp(.05, 1.0).toDouble();

    final records = Map<int, AnalystRecord>.from(state.records);
    var weightSum = 0.0;
    var counted = 0;

    for (final vote in votes) {
      final previous = records[vote.id] ??
          AnalystRecord.prior(vote.id, bornAtGeneration: state.generation);
      final p = vote.probabilityUp.clamp(.01, .99).toDouble();
      final brier = (p - y) * (p - y);
      // An inactive analyst is not punished as hard: it explicitly abstained.
      final share = vote.active ? k : k * .35;

      final memory = (brierMemory * share).clamp(0.0, .5);
      final ewma = previous.ewmaBrier * (1 - memory) + brier * memory;

      // Hedge / multiplicative weights: exp(-η·loss) relative to a coin flip.
      final regret = brier - .25;
      final updated = previous.weight *
          math.exp((-learningRate * share * regret).clamp(-1.5, 1.5));

      final correct = (p >= .5) == wentUp;
      final decay = math.pow(posteriorDecay, share).toDouble();
      final alpha = previous.alpha * decay + (correct ? share : 0);
      final beta = previous.beta * decay + (correct ? 0 : share);

      records[vote.id] = previous.copyWith(
        alpha: alpha.clamp(.2, 400).toDouble(),
        beta: beta.clamp(.2, 400).toDouble(),
        ewmaBrier: ewma.clamp(0.0, 1.0).toDouble(),
        weight: updated.clamp(.03, 8.0).toDouble(),
        experience: previous.experience + share,
      );
      weightSum += records[vote.id]!.weight;
      counted++;
    }

    // Renormalise so the average trust stays at 1 and the pool cannot drift.
    if (counted > 0 && weightSum > 0) {
      final mean = weightSum / counted;
      if (mean > 0) {
        for (final id in records.keys.toList()) {
          final r = records[id]!;
          records[id] =
              r.copyWith(weight: (r.weight / mean).clamp(.03, 8.0).toDouble());
        }
      }
    }

    // Online Platt calibration on the fused consensus.
    //
    // Only closed rounds may touch it. The calibration answers one specific
    // question — "when this engine says 62%, how often does the 5-minute
    // candle actually close up?" — and feeding it 30-second outcomes would fit
    // it to a different horizon entirely, which is worse than not fitting it.
    var slope = state.calibrationSlope;
    var intercept = state.calibrationIntercept;
    final raw = consensusProbabilityUp.clamp(1e-4, 1 - 1e-4).toDouble();
    if (closedRound) {
      final logit = math.log(raw / (1 - raw));
      final z = slope * logit + intercept;
      final q = 1 / (1 + math.exp(-z.clamp(-30.0, 30.0)));
      final gradient = (q - y) * k;
      slope = (slope - calibrationRate * gradient * logit)
          .clamp(.25, 2.6)
          .toDouble();
      intercept = (intercept - calibrationRate * gradient)
          .clamp(-1.0, 1.0)
          .toDouble();
    }

    final consensusBrier = closedRound
        ? state.consensusBrier * .94 + math.pow(raw - y, 2).toDouble() * .06
        : state.consensusBrier;

    var next = state.copyWith(
      records: Map<int, AnalystRecord>.unmodifiable(records),
      roundsObserved: state.roundsObserved + (closedRound ? 1 : 0),
      experience: state.experience + k,
      experienceSinceGeneration: state.experienceSinceGeneration + k,
      calibrationSlope: slope,
      calibrationIntercept: intercept,
      hits: state.hits + (closedRound && ((raw >= .5) == wentUp) ? 1 : 0),
      scored: state.scored + (closedRound ? 1 : 0),
      consensusBrier: consensusBrier,
    );

    if (next.experienceSinceGeneration >= experiencePerGeneration) {
      next = evolve(next);
    }
    return next;
  }

  /// Replaces the weakest analysts with crossover children of the elite.
  PulseEvolutionState evolve(PulseEvolutionState state) {
    final generation = state.generation + 1;
    final rng = math.Random(generation * 7919 + 13);

    final ranked = [...state.genomes]..sort((a, b) =>
        state.recordOf(b.id).fitness.compareTo(state.recordOf(a.id).fitness));
    if (ranked.length < 10) return state;

    final eliteCount = math.max(4, (ranked.length * eliteFraction).round());
    final replaceCount = math.max(1, (ranked.length * replaceFraction).round());
    final elite = ranked.take(eliteCount).toList();
    final doomed = ranked.reversed.take(replaceCount).toList();
    final doomedIds = doomed.map((g) => g.id).toSet();

    final genomes = <AnalystGenome>[];
    final records = Map<int, AnalystRecord>.from(state.records);
    final eliteBrier = elite.isEmpty
        ? .25
        : elite
                .map((g) => state.recordOf(g.id).ewmaBrier)
                .reduce((a, b) => a + b) /
            elite.length;

    for (final genome in state.genomes) {
      if (!doomedIds.contains(genome.id)) {
        // Elites are preserved; the rest drift slightly to keep exploring.
        final isElite = elite.any((e) => e.id == genome.id);
        genomes.add(isElite ? genome : genome.mutate(rng, .18, generation));
        continue;
      }

      final sameFamily =
          elite.where((e) => e.family == genome.family).toList();
      final pool = sameFamily.length >= 2 ? sameFamily : elite;
      final parentA = pool[rng.nextInt(pool.length)];
      var parentB = pool[rng.nextInt(pool.length)];
      if (parentB.id == parentA.id && pool.length > 1) {
        parentB = pool[(pool.indexOf(parentA) + 1) % pool.length];
      }
      final failure =
          ((1 - state.recordOf(genome.id).fitness).clamp(0.0, 2.0) / 2)
              .toDouble();
      final child = AnalystGenome.crossover(
        genome.id,
        genome.family,
        parentA,
        parentB,
        rng,
        generation,
      ).mutate(rng, .35 + failure * .5, generation);
      genomes.add(child);

      records[genome.id] = AnalystRecord(
        id: genome.id,
        alpha: 1,
        beta: 1,
        ewmaBrier: eliteBrier.clamp(.05, .35).toDouble(),
        weight: 1,
        experience: 0,
        bornAtGeneration: generation,
      );
    }

    return state.copyWith(
      genomes: List<AnalystGenome>.unmodifiable(genomes),
      records: Map<int, AnalystRecord>.unmodifiable(records),
      generation: generation,
      experienceSinceGeneration: 0,
      lastEvolutionEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
