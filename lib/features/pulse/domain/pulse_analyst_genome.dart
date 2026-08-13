import 'dart:math' as math;

import 'pulse_math_council.dart';
import 'pulse_news_desk.dart';
import 'pulse_pattern_archive.dart';

/// The ten specialities covered by the 100 market analysts.
enum AnalystFamily {
  momentum,
  trend,
  volatility,
  meanReversion,
  orderBook,
  tradeFlow,
  volume,
  priceAction,
  intermarket,
  regime,
}

extension AnalystFamilyLabel on AnalystFamily {
  String get label {
    switch (this) {
      case AnalystFamily.momentum:
        return 'Momentum';
      case AnalystFamily.trend:
        return 'Tendencia';
      case AnalystFamily.volatility:
        return 'Volatilidad';
      case AnalystFamily.meanReversion:
        return 'Reversión';
      case AnalystFamily.orderBook:
        return 'Libro';
      case AnalystFamily.tradeFlow:
        return 'Flujo';
      case AnalystFamily.volume:
        return 'Volumen';
      case AnalystFamily.priceAction:
        return 'Price action';
      case AnalystFamily.intermarket:
        return 'Intermercado';
      case AnalystFamily.regime:
        return 'Régimen';
    }
  }

  /// Six observable features every member of the family reasons about.
  List<String> get featureKeys {
    switch (this) {
      case AnalystFamily.momentum:
        return const [
          'momentum',
          'acceleration',
          'shortReturn',
          'velocityRatio',
          'impulse',
          'momentumPersistence',
        ];
      case AnalystFamily.trend:
        return const [
          'trend',
          'emaSpread',
          'slope',
          'trendQuality',
          'higherTrend',
          'pullbackDepth',
        ];
      case AnalystFamily.volatility:
        return const [
          'volatilityBreakout',
          'atrExpansion',
          'rangeExpansion',
          'volatilityRegime',
          'squeeze',
          'gapRisk',
        ];
      case AnalystFamily.meanReversion:
        return const [
          'zPrice',
          'rsiExtreme',
          'vwapDistance',
          'bandPosition',
          'exhaustion',
          'reversionPull',
        ];
      case AnalystFamily.orderBook:
        return const [
          'bookImbalance',
          'micropriceEdge',
          'spreadPressure',
          'depthSlope',
          'queueDepletion',
          'bookStability',
        ];
      case AnalystFamily.tradeFlow:
        return const [
          'aggressorImbalance',
          'tradeAcceleration',
          'signedVolume',
          'flowPersistence',
          'absorption',
          'largeTradeBias',
        ];
      case AnalystFamily.volume:
        return const [
          'volumeZ',
          'obvSlope',
          'volumePriceAgreement',
          'volumeTrend',
          'effortResult',
          'liquidityShift',
        ];
      case AnalystFamily.priceAction:
        return const [
          'bodyPressure',
          'breakoutQuality',
          'wickBias',
          'closeLocation',
          'swingStructure',
          'rejectionBias',
        ];
      case AnalystFamily.intermarket:
        return const [
          'ethConfirmation',
          'exchangeConsensus',
          'betaResidual',
          'crossFlow',
          'correlationRegime',
          'leadLag',
        ];
      case AnalystFamily.regime:
        return const [
          'regimeTrend',
          'regimePersistence',
          'roundEdge',
          'timeDecayEdge',
          'sessionBias',
          'stabilityEdge',
        ];
    }
  }

  /// Mean-reversion analysts read their features with inverted polarity.
  double get polarity => this == AnalystFamily.meanReversion ? -1.0 : 1.0;
}

/// Heritable configuration of a single analyst.
///
/// The genome is what evolution actually optimises: which observable features
/// the analyst trusts, which mathematical branches of the 50-mathematician
/// council it listens to, how sharply it converts evidence into probability
/// and how much evidence it demands before voting at all.
class AnalystGenome {
  const AnalystGenome({
    required this.id,
    required this.family,
    required this.featureWeights,
    required this.branchAffinity,
    required this.deskAffinity,
    required this.lensAffinity,
    required this.temperature,
    required this.bias,
    required this.gate,
    required this.mathTrust,
    required this.newsTrust,
    required this.patternTrust,
    required this.generation,
    required this.lineage,
  });

  final int id;
  final AnalystFamily family;

  /// Six weights aligned with [AnalystFamilyLabel.featureKeys].
  final List<double> featureWeights;

  /// Ten weights aligned with [MathBranch.values].
  final List<double> branchAffinity;

  /// Ten weights aligned with [NewsDesk.values].
  final List<double> deskAffinity;

  /// Ten weights aligned with [PatternLens.values].
  final List<double> lensAffinity;

  /// Logistic temperature: lower means a sharper opinion.
  final double temperature;

  /// Structural prior of the analyst (small on purpose).
  final double bias;

  /// Minimum absolute edge required before the analyst counts as active.
  final double gate;

  /// Share of the analyst's conviction delegated to the mathematicians.
  final double mathTrust;

  /// Share of the analyst's conviction delegated to the news floor.
  final double newsTrust;

  /// Share of the analyst's conviction delegated to the historical archive.
  final double patternTrust;

  final int generation;

  /// Ancestry marker, e.g. `seed` or `g7:12x41`.
  final String lineage;

  static const int featureCount = 6;

  /// Builds the deterministic founding population.
  static List<AnalystGenome> foundingPopulation({int seed = 20260813}) {
    final rng = math.Random(seed);
    final genomes = <AnalystGenome>[];
    var id = 1;
    for (final family in AnalystFamily.values) {
      for (var variant = 0; variant < 10; variant++) {
        genomes.add(AnalystGenome.seeded(id++, family, variant, rng));
      }
    }
    return genomes;
  }

  factory AnalystGenome.seeded(
    int id,
    AnalystFamily family,
    int variant,
    math.Random rng,
  ) {
    // Base profile: the first feature dominates, the rest add diversity.
    const base = <double>[.34, .22, .16, .12, .09, .07];
    final weights = <double>[];
    for (var i = 0; i < featureCount; i++) {
      final jitter = (rng.nextDouble() - .5) * .22;
      weights.add((base[i] + jitter) * family.polarity);
    }

    // Every analyst listens to the council, but with a personal bias toward
    // two or three branches so the 100 opinions stay genuinely different.
    final affinity = List<double>.filled(MathBranch.values.length, 0);
    for (var i = 0; i < affinity.length; i++) {
      affinity[i] = .04 + rng.nextDouble() * .10;
    }
    final favourite = variant % MathBranch.values.length;
    final secondary = (variant * 7 + family.index * 3) % MathBranch.values.length;
    affinity[favourite] += .34;
    affinity[secondary] += .18;

    final desks = List<double>.filled(NewsDesk.values.length, 0);
    for (var i = 0; i < desks.length; i++) {
      desks[i] = .04 + rng.nextDouble() * .10;
    }
    desks[(variant * 3 + family.index) % desks.length] += .30;
    desks[(variant + family.index * 5) % desks.length] += .16;

    final lenses = List<double>.filled(PatternLens.values.length, 0);
    for (var i = 0; i < lenses.length; i++) {
      lenses[i] = .04 + rng.nextDouble() * .10;
    }
    lenses[(variant * 5 + family.index * 2) % lenses.length] += .32;
    lenses[(variant + family.index) % lenses.length] += .15;

    return AnalystGenome(
      id: id,
      family: family,
      featureWeights: List<double>.unmodifiable(weights),
      branchAffinity: List<double>.unmodifiable(_normalize(affinity)),
      deskAffinity: List<double>.unmodifiable(_normalize(desks)),
      lensAffinity: List<double>.unmodifiable(_normalize(lenses)),
      temperature: .14 + variant * .009 + rng.nextDouble() * .02,
      bias: (rng.nextDouble() - .5) * .06,
      gate: .04 + rng.nextDouble() * .07,
      mathTrust: .24 + rng.nextDouble() * .26,
      newsTrust: .05 + rng.nextDouble() * .16,
      patternTrust: .10 + rng.nextDouble() * .22,
      generation: 0,
      lineage: 'seed',
    );
  }

  AnalystGenome mutate(math.Random rng, double strength, int generation) {
    final s = strength.clamp(.02, 1.0);
    final weights = [
      for (final w in featureWeights) w + (rng.nextDouble() - .5) * .30 * s,
    ];
    final affinity = [
      for (final a in branchAffinity)
        math.max(.005, a + (rng.nextDouble() - .5) * .18 * s),
    ];
    final desks = [
      for (final a in deskAffinity)
        math.max(.005, a + (rng.nextDouble() - .5) * .18 * s),
    ];
    final lenses = [
      for (final a in lensAffinity)
        math.max(.005, a + (rng.nextDouble() - .5) * .18 * s),
    ];
    return AnalystGenome(
      id: id,
      family: family,
      featureWeights: List<double>.unmodifiable(weights),
      branchAffinity: List<double>.unmodifiable(_normalize(affinity)),
      deskAffinity: List<double>.unmodifiable(_normalize(desks)),
      lensAffinity: List<double>.unmodifiable(_normalize(lenses)),
      temperature: (temperature + (rng.nextDouble() - .5) * .05 * s)
          .clamp(.06, .40)
          .toDouble(),
      bias: (bias + (rng.nextDouble() - .5) * .05 * s)
          .clamp(-.22, .22)
          .toDouble(),
      gate: (gate + (rng.nextDouble() - .5) * .05 * s)
          .clamp(.01, .28)
          .toDouble(),
      mathTrust: (mathTrust + (rng.nextDouble() - .5) * .22 * s)
          .clamp(.05, .80)
          .toDouble(),
      newsTrust: (newsTrust + (rng.nextDouble() - .5) * .16 * s)
          .clamp(.0, .40)
          .toDouble(),
      patternTrust: (patternTrust + (rng.nextDouble() - .5) * .18 * s)
          .clamp(.0, .50)
          .toDouble(),
      generation: generation,
      lineage: '$lineage*',
    );
  }

  /// Uniform crossover between two elite parents, keeping the slot [id].
  static AnalystGenome crossover(
    int id,
    AnalystFamily family,
    AnalystGenome a,
    AnalystGenome b,
    math.Random rng,
    int generation,
  ) {
    final weights = <double>[];
    for (var i = 0; i < featureCount; i++) {
      final wa = i < a.featureWeights.length ? a.featureWeights[i] : 0.0;
      final wb = i < b.featureWeights.length ? b.featureWeights[i] : 0.0;
      final blend = rng.nextDouble();
      weights.add(wa * blend + wb * (1 - blend));
    }
    // A child inherits the family polarity of the slot it fills, not of the
    // parents, so team structure is preserved across generations.
    final sameFamily = a.family == family;
    if (!sameFamily) {
      final flip = family.polarity * a.family.polarity;
      for (var i = 0; i < weights.length; i++) {
        weights[i] *= flip;
      }
    }
    final affinity = <double>[];
    for (var i = 0; i < MathBranch.values.length; i++) {
      final aa = i < a.branchAffinity.length ? a.branchAffinity[i] : .1;
      final bb = i < b.branchAffinity.length ? b.branchAffinity[i] : .1;
      affinity.add(rng.nextBool() ? aa : bb);
    }
    final desks = <double>[];
    for (var i = 0; i < NewsDesk.values.length; i++) {
      final aa = i < a.deskAffinity.length ? a.deskAffinity[i] : .1;
      final bb = i < b.deskAffinity.length ? b.deskAffinity[i] : .1;
      desks.add(rng.nextBool() ? aa : bb);
    }
    final lenses = <double>[];
    for (var i = 0; i < PatternLens.values.length; i++) {
      final aa = i < a.lensAffinity.length ? a.lensAffinity[i] : .1;
      final bb = i < b.lensAffinity.length ? b.lensAffinity[i] : .1;
      lenses.add(rng.nextBool() ? aa : bb);
    }
    return AnalystGenome(
      id: id,
      family: family,
      featureWeights: List<double>.unmodifiable(weights),
      branchAffinity: List<double>.unmodifiable(_normalize(affinity)),
      deskAffinity: List<double>.unmodifiable(_normalize(desks)),
      lensAffinity: List<double>.unmodifiable(_normalize(lenses)),
      temperature: (a.temperature + b.temperature) / 2,
      bias: (a.bias + b.bias) / 2,
      gate: (a.gate + b.gate) / 2,
      mathTrust: (a.mathTrust + b.mathTrust) / 2,
      newsTrust: (a.newsTrust + b.newsTrust) / 2,
      patternTrust: (a.patternTrust + b.patternTrust) / 2,
      generation: generation,
      lineage: 'g$generation:${a.id}x${b.id}',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'f': family.index,
        'w': featureWeights,
        'a': branchAffinity,
        'd': deskAffinity,
        'ls': lensAffinity,
        't': temperature,
        'b': bias,
        'g': gate,
        'm': mathTrust,
        'n': newsTrust,
        'pt': patternTrust,
        'gen': generation,
        'l': lineage,
      };

  static AnalystGenome? fromJson(Map<String, dynamic> json) {
    try {
      final familyIndex = (json['f'] as num).toInt();
      if (familyIndex < 0 || familyIndex >= AnalystFamily.values.length) {
        return null;
      }
      final weights = (json['w'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
      final affinity = (json['a'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
      final desks = (json['d'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
      final lenses = (json['ls'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
      if (weights.length != featureCount ||
          affinity.length != MathBranch.values.length ||
          desks.length != NewsDesk.values.length ||
          lenses.length != PatternLens.values.length) {
        return null;
      }
      return AnalystGenome(
        id: (json['id'] as num).toInt(),
        family: AnalystFamily.values[familyIndex],
        featureWeights: List<double>.unmodifiable(weights),
        branchAffinity: List<double>.unmodifiable(affinity),
        deskAffinity: List<double>.unmodifiable(desks),
        lensAffinity: List<double>.unmodifiable(lenses),
        temperature: (json['t'] as num).toDouble().clamp(.06, .40).toDouble(),
        bias: (json['b'] as num).toDouble().clamp(-.25, .25).toDouble(),
        gate: (json['g'] as num).toDouble().clamp(.005, .30).toDouble(),
        mathTrust: (json['m'] as num).toDouble().clamp(.0, .90).toDouble(),
        newsTrust:
            ((json['n'] as num?)?.toDouble() ?? .12).clamp(.0, .45).toDouble(),
        patternTrust:
            ((json['pt'] as num?)?.toDouble() ?? .18).clamp(.0, .55).toDouble(),
        generation: (json['gen'] as num?)?.toInt() ?? 0,
        lineage: '${json['l'] ?? 'seed'}',
      );
    } catch (_) {
      return null;
    }
  }

  static List<double> _normalize(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v.abs();
    }
    if (sum <= 1e-12) {
      return List<double>.filled(values.length, 1 / values.length);
    }
    return [for (final v in values) v / sum];
  }
}
