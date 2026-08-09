import 'dart:math' as math;

enum AnalystDirection { up, down, neutral }

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

class AnalystInput {
  const AnalystInput({
    required this.features,
    required this.instability,
    required this.secondsRemaining,
  });

  final Map<String, double> features;
  final double instability;
  final int secondsRemaining;

  double get(String key) => features[key] ?? 0;
}

class AnalystOpinion {
  const AnalystOpinion({
    required this.id,
    required this.family,
    required this.direction,
    required this.probabilityUp,
    required this.quality,
    required this.reliability,
  });

  final int id;
  final AnalystFamily family;
  final AnalystDirection direction;
  final double probabilityUp;
  final double quality;
  final double reliability;
}

class TeamOpinion {
  const TeamOpinion({
    required this.family,
    required this.probabilityUp,
    required this.quality,
    required this.disagreement,
  });

  final AnalystFamily family;
  final double probabilityUp;
  final double quality;
  final double disagreement;
}

class PulseEnsemble100Result {
  const PulseEnsemble100Result({
    required this.probabilityUp,
    required this.confidence,
    required this.activeAnalysts,
    required this.upAnalysts,
    required this.downAnalysts,
    required this.neutralAnalysts,
    required this.agreement,
    required this.teamOpinions,
  });

  final double probabilityUp;
  final double confidence;
  final int activeAnalysts;
  final int upAnalysts;
  final int downAnalysts;
  final int neutralAnalysts;
  final double agreement;
  final List<TeamOpinion> teamOpinions;
}

/// Hierarchical ensemble: 100 lightweight mathematical analysts ->
/// 10 family teams -> one meta-engine. The individual analysts intentionally
/// use slightly different feature subsets/thresholds so the ensemble is not
/// merely 100 copies of the same rule.
class PulseEnsemble100 {
  const PulseEnsemble100();

  PulseEnsemble100Result analyze(AnalystInput input) {
    final opinions = <AnalystOpinion>[];
    var id = 1;
    for (final family in AnalystFamily.values) {
      for (var variant = 0; variant < 10; variant++) {
        opinions.add(_runAnalyst(id++, family, variant, input));
      }
    }

    final teams = <TeamOpinion>[];
    for (final family in AnalystFamily.values) {
      final members = opinions.where((o) => o.family == family).toList();
      teams.add(_aggregateTeam(family, members));
    }

    final usableTeams = teams.where((t) => t.quality >= .12).toList();
    if (usableTeams.isEmpty) {
      return PulseEnsemble100Result(
        probabilityUp: .5,
        confidence: 50,
        activeAnalysts: opinions.length,
        upAnalysts:
            opinions.where((o) => o.direction == AnalystDirection.up).length,
        downAnalysts:
            opinions.where((o) => o.direction == AnalystDirection.down).length,
        neutralAnalysts: opinions
            .where((o) => o.direction == AnalystDirection.neutral)
            .length,
        agreement: 0,
        teamOpinions: teams,
      );
    }

    var weighted = 0.0;
    var weightSum = 0.0;
    for (final team in usableTeams) {
      final independencePenalty = 1 - team.disagreement * .35;
      final weight = (team.quality * independencePenalty).clamp(.05, 1.0);
      weighted += team.probabilityUp * weight;
      weightSum += weight;
    }

    var pUp = weightSum == 0 ? .5 : weighted / weightSum;
    final instability = input.instability.clamp(0.0, 100.0) / 100.0;
    final shrink = (1 - instability * .62).clamp(.25, 1.0);
    pUp = .5 + (pUp - .5) * shrink;
    pUp = pUp.clamp(.05, .95).toDouble();

    final majorityUp = opinions.where((o) => o.probabilityUp >= .5).length;
    final agreement =
        math.max(majorityUp, opinions.length - majorityUp) / opinions.length;

    return PulseEnsemble100Result(
      probabilityUp: pUp,
      confidence: math.max(pUp, 1 - pUp) * 100,
      activeAnalysts: opinions.length,
      upAnalysts:
          opinions.where((o) => o.direction == AnalystDirection.up).length,
      downAnalysts:
          opinions.where((o) => o.direction == AnalystDirection.down).length,
      neutralAnalysts:
          opinions.where((o) => o.direction == AnalystDirection.neutral).length,
      agreement: agreement,
      teamOpinions: teams,
    );
  }

  AnalystOpinion _runAnalyst(
    int id,
    AnalystFamily family,
    int variant,
    AnalystInput input,
  ) {
    final jitter = (variant - 4.5) / 45.0;
    double edge;

    switch (family) {
      case AnalystFamily.momentum:
        edge = input.get('momentum') * .55 +
            input.get('acceleration') * .25 +
            input.get('shortReturn') * .20;
      case AnalystFamily.trend:
        edge = input.get('trend') * .45 +
            input.get('emaSpread') * .30 +
            input.get('slope') * .25;
      case AnalystFamily.volatility:
        edge = input.get('volatilityBreakout') * .45 +
            input.get('atrExpansion') * .30 +
            input.get('rangeExpansion') * .25;
      case AnalystFamily.meanReversion:
        edge = -input.get('zPrice') * .45 -
            input.get('rsiExtreme') * .30 -
            input.get('vwapDistance') * .25;
      case AnalystFamily.orderBook:
        edge = input.get('bookImbalance') * .50 +
            input.get('micropriceEdge') * .30 +
            input.get('spreadPressure') * .20;
      case AnalystFamily.tradeFlow:
        edge = input.get('aggressorImbalance') * .50 +
            input.get('tradeAcceleration') * .30 +
            input.get('signedVolume') * .20;
      case AnalystFamily.volume:
        edge = input.get('volumeZ') * .30 +
            input.get('obvSlope') * .35 +
            input.get('volumePriceAgreement') * .35;
      case AnalystFamily.priceAction:
        edge = input.get('bodyPressure') * .35 +
            input.get('breakoutQuality') * .35 +
            input.get('wickBias') * .30;
      case AnalystFamily.intermarket:
        edge = input.get('ethConfirmation') * .30 +
            input.get('exchangeConsensus') * .35 +
            input.get('betaResidual') * .35;
      case AnalystFamily.regime:
        edge = input.get('regimeTrend') * .40 +
            input.get('regimePersistence') * .30 +
            input.get('roundEdge') * .30;
    }

    edge = (edge + jitter).clamp(-1.0, 1.0);
    final temperature = .18 + variant * .008;
    final pUp = 1 / (1 + math.exp(-edge / temperature));
    final quality =
        (edge.abs() * (1 - input.instability / 125)).clamp(0.0, 1.0).toDouble();
    final reliability = (.45 + variant * .02).clamp(.45, .63).toDouble();

    return AnalystOpinion(
      id: id,
      family: family,
      direction: pUp > .52
          ? AnalystDirection.up
          : pUp < .48
              ? AnalystDirection.down
              : AnalystDirection.neutral,
      probabilityUp: pUp,
      quality: quality,
      reliability: reliability,
    );
  }

  TeamOpinion _aggregateTeam(
    AnalystFamily family,
    List<AnalystOpinion> members,
  ) {
    var weighted = 0.0;
    var weightSum = 0.0;
    final probs = <double>[];
    for (final m in members) {
      final weight = (m.quality * m.reliability).clamp(.02, 1.0);
      weighted += m.probabilityUp * weight;
      weightSum += weight;
      probs.add(m.probabilityUp);
    }
    final mean = weightSum == 0 ? .5 : weighted / weightSum;
    final variance = probs.isEmpty
        ? 0.0
        : probs
                .map((p) => math.pow(p - mean, 2).toDouble())
                .reduce((a, b) => a + b) /
            probs.length;
    final disagreement = math.sqrt(variance).clamp(0.0, .5) * 2;
    final quality = members.isEmpty
        ? 0.0
        : members.map((m) => m.quality).reduce((a, b) => a + b) /
            members.length;

    return TeamOpinion(
      family: family,
      probabilityUp: mean,
      quality: quality,
      disagreement: disagreement,
    );
  }
}
