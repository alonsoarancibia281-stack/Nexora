import 'dart:math' as math;

import 'pulse_analyst_evolution.dart';
import 'pulse_analyst_genome.dart';
import 'pulse_math_council.dart';
import 'pulse_news_desk.dart';
import 'pulse_pattern_archive.dart';

export 'pulse_analyst_genome.dart' show AnalystFamily, AnalystFamilyLabel;

enum AnalystDirection { up, down, neutral }

class AnalystInput {
  const AnalystInput({
    required this.features,
    required this.instability,
    required this.secondsRemaining,
  });

  final Map<String, double> features;
  final double instability;
  final int secondsRemaining;

  double get(String key) {
    final value = features[key];
    if (value == null || !value.isFinite) return 0;
    return value.clamp(-1.0, 1.0).toDouble();
  }
}

class AnalystOpinion {
  const AnalystOpinion({
    required this.id,
    required this.family,
    required this.direction,
    required this.probabilityUp,
    required this.quality,
    required this.reliability,
    required this.trust,
    required this.active,
    required this.mathShare,
  });

  final int id;
  final AnalystFamily family;
  final AnalystDirection direction;
  final double probabilityUp;
  final double quality;
  final double reliability;

  /// Hedge weight earned through past performance.
  final double trust;

  final bool active;

  /// How much of this opinion came from the other councils.
  final double mathShare;

  double get influence => quality * reliability * trust;
}

class TeamOpinion {
  const TeamOpinion({
    required this.family,
    required this.probabilityUp,
    required this.quality,
    required this.disagreement,
    required this.activeMembers,
    required this.trust,
  });

  final AnalystFamily family;
  final double probabilityUp;
  final double quality;
  final double disagreement;
  final int activeMembers;
  final double trust;

  AnalystDirection get direction => probabilityUp > .52
      ? AnalystDirection.up
      : probabilityUp < .48
          ? AnalystDirection.down
          : AnalystDirection.neutral;
}

class PulseEnsemble100Result {
  const PulseEnsemble100Result({
    required this.probabilityUp,
    required this.confidence,
    required this.activeAnalysts,
    required this.agreement,
    required this.teamOpinions,
    required this.opinions,
    required this.votes,
    required this.upVotes,
    required this.downVotes,
    required this.dispersion,
    required this.effectiveSampleSize,
    required this.pooledLogit,
  });

  final double probabilityUp;
  final double confidence;
  final int activeAnalysts;
  final double agreement;
  final List<TeamOpinion> teamOpinions;
  final List<AnalystOpinion> opinions;
  final List<AnalystVote> votes;
  final int upVotes;
  final int downVotes;

  /// Jensen-Shannon divergence of the 100 opinions, normalized to [0,1].
  final double dispersion;

  /// Kish effective sample size after the redundancy correction.
  final double effectiveSampleSize;

  final double pooledLogit;

  int get neutralVotes => opinions.length - upVotes - downVotes;

  static PulseEnsemble100Result neutral(int population) =>
      PulseEnsemble100Result(
        probabilityUp: .5,
        confidence: 50,
        activeAnalysts: 0,
        agreement: 0,
        teamOpinions: const <TeamOpinion>[],
        opinions: const <AnalystOpinion>[],
        votes: const <AnalystVote>[],
        upVotes: 0,
        downVotes: 0,
        dispersion: 0,
        effectiveSampleSize: 0,
        pooledLogit: 0,
      );
}

/// Hierarchical ensemble: 100 evolving analysts → 10 family teams → one
/// meta-engine.
///
/// Every analyst reads the live market features *and* the theorems published
/// by the 50-mathematician council, weighted by its own genome. Opinions are
/// merged with a logarithmic opinion pool (log-odds averaging) rather than a
/// plain mean, because averaging probabilities systematically destroys
/// information when the voters are individually informative but noisy.
class PulseEnsemble100 {
  const PulseEnsemble100();

  PulseEnsemble100Result analyze(
    AnalystInput input, {
    MathBriefing? briefing,
    NewsBriefing? news,
    PatternBriefing? patterns,
    PulseEvolutionState? evolution,
  }) {
    final state = evolution ?? PulseEvolutionState.bootstrap();
    final council = briefing ?? MathBriefing.neutral();
    final newsroom = news ?? NewsBriefing.empty();
    final archive = patterns ?? PatternBriefing.empty();
    final genomes = state.genomes;
    if (genomes.isEmpty) {
      return PulseEnsemble100Result.neutral(0);
    }

    final instability = input.instability.clamp(0.0, 100.0) / 100.0;
    final dispersions = <double>[
      if (council.isReady) council.dispersion,
      if (newsroom.isReady) newsroom.dispersion,
      if (archive.isReady) archive.dispersion,
    ];
    final meanCouncilDispersion = dispersions.isEmpty
        ? 0.0
        : dispersions.reduce((a, b) => a + b) / dispersions.length;
    final coherence =
        (1 - meanCouncilDispersion * .6).clamp(.2, 1.0).toDouble();

    final opinions = <AnalystOpinion>[];
    for (final genome in genomes) {
      opinions.add(_run(
        genome,
        input,
        council,
        newsroom,
        archive,
        state,
        instability,
        coherence,
      ));
    }

    final teams = <TeamOpinion>[];
    for (final family in AnalystFamily.values) {
      final members = opinions.where((o) => o.family == family).toList();
      if (members.isEmpty) continue;
      teams.add(_aggregateTeam(family, members));
    }

    // --- Meta pooling -------------------------------------------------------
    var pooled = 0.0;
    var weightSum = 0.0;
    var weightSquareSum = 0.0;
    for (final team in teams) {
      final independence = (1 - team.disagreement * .32).clamp(.25, 1.0);
      final coverage = team.activeMembers / 10.0;
      final weight =
          (team.quality * team.trust * independence * (.35 + coverage * .65))
              .clamp(.01, 4.0)
              .toDouble();
      pooled += _logit(team.probabilityUp) * weight;
      weightSum += weight;
      weightSquareSum += weight * weight;
    }

    if (weightSum <= 0) {
      return PulseEnsemble100Result.neutral(genomes.length);
    }
    var logit = pooled / weightSum;

    // Kish effective sample size, then corrected for the correlation between
    // analysts that ends up making them redundant voters.
    final kish = weightSquareSum <= 0
        ? 0.0
        : (weightSum * weightSum) / weightSquareSum;
    final meanDisagreement = teams.isEmpty
        ? 0.0
        : teams.map((t) => t.disagreement).reduce((a, b) => a + b) /
            teams.length;
    final redundancy = ((1 - meanDisagreement) * .65).clamp(0.0, .95);
    final effective = kish / (1 + (math.max(kish - 1, 0)) * redundancy);
    final breadth = teams.isEmpty
        ? 0.0
        : math.sqrt((effective / teams.length).clamp(0.0, 1.0));

    // Jensen-Shannon divergence over the individual Bernoulli opinions.
    final dispersion = _jensenShannon(opinions.map((o) => o.probabilityUp));

    logit *= breadth;
    logit *= (1 - dispersion * .55).clamp(.30, 1.0);
    logit *= (1 - instability * .50).clamp(.35, 1.0);
    logit *= (.55 + coherence * .45);

    final probabilityUp = _sigmoid(logit).clamp(.04, .96).toDouble();

    final upVotes = opinions.where((o) => o.direction == AnalystDirection.up).length;
    final downVotes =
        opinions.where((o) => o.direction == AnalystDirection.down).length;
    final decided = upVotes + downVotes;
    final agreement = decided == 0 ? 0.0 : math.max(upVotes, downVotes) / decided;

    return PulseEnsemble100Result(
      probabilityUp: probabilityUp,
      confidence: math.max(probabilityUp, 1 - probabilityUp) * 100,
      activeAnalysts: opinions.where((o) => o.active).length,
      agreement: agreement,
      teamOpinions: List<TeamOpinion>.unmodifiable(teams),
      opinions: List<AnalystOpinion>.unmodifiable(opinions),
      votes: List<AnalystVote>.unmodifiable([
        for (final o in opinions)
          AnalystVote(
            id: o.id,
            probabilityUp: o.probabilityUp,
            active: o.active,
            quality: o.quality,
          ),
      ]),
      upVotes: upVotes,
      downVotes: downVotes,
      dispersion: dispersion,
      effectiveSampleSize: effective,
      pooledLogit: logit,
    );
  }

  AnalystOpinion _run(
    AnalystGenome genome,
    AnalystInput input,
    MathBriefing council,
    NewsBriefing newsroom,
    PatternBriefing archive,
    PulseEvolutionState state,
    double instability,
    double coherence,
  ) {
    final keys = genome.family.featureKeys;
    var technical = 0.0;
    var magnitude = 0.0;
    for (var i = 0; i < keys.length && i < genome.featureWeights.length; i++) {
      final w = genome.featureWeights[i];
      technical += w * input.get(keys[i]);
      magnitude += w.abs();
    }
    technical = magnitude <= 1e-9 ? 0.0 : technical / magnitude;

    var mathematical = 0.0;
    if (council.isReady) {
      for (final branch in MathBranch.values) {
        final affinity = branch.index < genome.branchAffinity.length
            ? genome.branchAffinity[branch.index]
            : 0.0;
        mathematical += affinity *
            council.signalOf(branch) *
            (.45 + .55 * council.confidenceOf(branch));
      }
    }

    var editorial = 0.0;
    if (newsroom.isReady) {
      for (final desk in NewsDesk.values) {
        final affinity = desk.index < genome.deskAffinity.length
            ? genome.deskAffinity[desk.index]
            : 0.0;
        editorial += affinity *
            newsroom.signalOf(desk) *
            (.45 + .55 * newsroom.confidenceOf(desk));
      }
    }

    var historical = 0.0;
    if (archive.isReady) {
      for (final lens in PatternLens.values) {
        final affinity = lens.index < genome.lensAffinity.length
            ? genome.lensAffinity[lens.index]
            : 0.0;
        historical += affinity *
            archive.signalOf(lens) *
            (.45 + .55 * archive.confidenceOf(lens));
      }
    }

    var trustMath = council.isReady ? genome.mathTrust : 0.0;
    var trustNews = newsroom.isReady ? genome.newsTrust : 0.0;
    var trustPattern = archive.isReady ? genome.patternTrust : 0.0;
    final delegated = trustMath + trustNews + trustPattern;
    // The analyst always keeps a majority stake in its own reading.
    if (delegated > .78) {
      final scale = .78 / delegated;
      trustMath *= scale;
      trustNews *= scale;
      trustPattern *= scale;
    }
    final own = 1 - (trustMath + trustNews + trustPattern);

    var edge = technical * own +
        mathematical * trustMath +
        editorial * trustNews +
        historical * trustPattern;
    edge = (edge + genome.bias).clamp(-1.0, 1.0).toDouble();

    final probabilityUp = _sigmoid(edge / math.max(genome.temperature, .05));
    final active = edge.abs() >= genome.gate;
    final quality = (edge.abs() *
            (1 - instability * .45) *
            (.55 + coherence * .45) *
            (active ? 1.0 : .35))
        .clamp(0.0, 1.0)
        .toDouble();

    final record = state.recordOf(genome.id);
    final reliability = (.35 + record.reliability * .65).clamp(.2, 1.0).toDouble();

    return AnalystOpinion(
      id: genome.id,
      family: genome.family,
      direction: probabilityUp > .52
          ? AnalystDirection.up
          : probabilityUp < .48
              ? AnalystDirection.down
              : AnalystDirection.neutral,
      probabilityUp: probabilityUp.clamp(.02, .98).toDouble(),
      quality: quality,
      reliability: reliability,
      trust: record.weight.clamp(.03, 8.0).toDouble(),
      active: active,
      mathShare: trustMath + trustNews + trustPattern,
    );
  }

  TeamOpinion _aggregateTeam(AnalystFamily family, List<AnalystOpinion> members) {
    var pooled = 0.0;
    var weightSum = 0.0;
    final probabilities = <double>[];
    var trustSum = 0.0;
    for (final m in members) {
      final weight = math.max(m.influence, .01);
      pooled += _logit(m.probabilityUp) * weight;
      weightSum += weight;
      probabilities.add(m.probabilityUp);
      trustSum += m.trust;
    }
    final mean = weightSum <= 0 ? .5 : _sigmoid(pooled / weightSum);
    final spread = _std(probabilities);
    final disagreement = (spread * 2.6).clamp(0.0, 1.0).toDouble();
    final quality = members.isEmpty
        ? 0.0
        : members.map((m) => m.quality).reduce((a, b) => a + b) / members.length;

    return TeamOpinion(
      family: family,
      probabilityUp: mean.clamp(.03, .97).toDouble(),
      quality: quality,
      disagreement: disagreement,
      activeMembers: members.where((m) => m.active).length,
      trust: members.isEmpty
          ? 1.0
          : (trustSum / members.length).clamp(.05, 4.0).toDouble(),
    );
  }
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

double _logit(double p) {
  final q = p.clamp(1e-5, 1 - 1e-5);
  return math.log(q / (1 - q));
}

double _std(List<double> x) {
  if (x.length < 2) return 0;
  var mean = 0.0;
  for (final v in x) {
    mean += v;
  }
  mean /= x.length;
  var acc = 0.0;
  for (final v in x) {
    final d = v - mean;
    acc += d * d;
  }
  final variance = acc / (x.length - 1);
  return variance <= 0 ? 0 : math.sqrt(variance);
}

double _binaryEntropy(double p) {
  final q = p.clamp(1e-9, 1 - 1e-9);
  return -(q * math.log(q) + (1 - q) * math.log(1 - q));
}

/// Jensen-Shannon divergence of a set of Bernoulli opinions, scaled to [0,1].
double _jensenShannon(Iterable<double> probabilities) {
  final list = probabilities.toList(growable: false);
  if (list.length < 2) return 0;
  var mean = 0.0;
  for (final p in list) {
    mean += p;
  }
  mean /= list.length;
  var meanEntropy = 0.0;
  for (final p in list) {
    meanEntropy += _binaryEntropy(p);
  }
  meanEntropy /= list.length;
  final divergence = _binaryEntropy(mean) - meanEntropy;
  return (divergence / math.ln2).clamp(0.0, 1.0).toDouble();
}
