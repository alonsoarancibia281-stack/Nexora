import 'dart:math' as math;

import 'btc_5m_logistic_model.dart';
import 'pulse_ai_consensus.dart';
import 'pulse_analyst_evolution.dart';
import 'pulse_ensemble_100.dart';
import 'pulse_math_council.dart';
import 'pulse_news_desk.dart';
import 'pulse_pattern_archive.dart';
import 'pulse_probability_calibrator.dart';
import 'pulse_signal.dart';
import 'pulse_statistical_engine.dart';

/// Weight actually granted to one sub-model in the final fusion.
class ModelContribution {
  const ModelContribution({
    required this.name,
    required this.probabilityUp,
    required this.weight,
  });

  final String name;
  final double probabilityUp;
  final double weight;
}

/// Final verdict of the whole prediction stack.
class PulseConsensus {
  const PulseConsensus({
    required this.probabilityUp,
    required this.rawProbabilityUp,
    required this.direction,
    required this.confidence,
    required this.agreement,
    required this.dispersion,
    required this.contributions,
    required this.ensemble,
    required this.briefing,
    required this.news,
    required this.patterns,
    required this.evidence,
  });

  final double probabilityUp;

  /// Probability before the learned Platt calibration.
  final double rawProbabilityUp;

  final PulseDirection direction;
  final double confidence;

  /// Share of the 100 analysts on the winning side.
  final double agreement;

  /// Normalized Jensen-Shannon dispersion of the analyst pool.
  final double dispersion;

  final List<ModelContribution> contributions;
  final PulseEnsemble100Result ensemble;
  final MathBriefing briefing;
  final NewsBriefing news;
  final PatternBriefing patterns;

  /// Aggregate strength of the evidence in [0,1].
  final double evidence;

  String get directionLabel =>
      direction == PulseDirection.up ? 'SUBE' : 'BAJA';

  double get probabilityDown => 1 - probabilityUp;

  double get winningProbability => math.max(probabilityUp, probabilityDown);
}

/// Fuses every model into one probability.
///
/// The fusion is a weighted logarithmic opinion pool. Averaging probabilities
/// is not the same as averaging evidence: pooling in log-odds space keeps a
/// confident-but-correlated minority from being diluted into noise, and it
/// lets a single strongly informed model move the verdict when the rest
/// abstain around 50%.
class PulseConsensusEngine {
  const PulseConsensusEngine();

  PulseConsensus fuse({
    required PulseSignal signal,
    required PulseEnsemble100Result ensemble,
    required MathBriefing briefing,
    required NewsBriefing news,
    required PatternBriefing patterns,
    required PulseEvolutionState evolution,
    PulseStatisticalResult? statistical,
    PulseProbabilityResult? calibrated,
    Btc5mLogisticResult? logistic,
    PulseAiConsensus? ai,
  }) {
    final instability = signal.instabilityScore.clamp(0.0, 100.0) / 100.0;
    final contributions = <ModelContribution>[];

    // 1) The 100 analysts. Their weight grows with internal agreement and with
    // the historical skill the population has actually demonstrated.
    final populationSkill =
        evolution.hasUsefulSample ? evolution.consensusSkill.clamp(-.5, 1.0) : 0.0;
    final ensembleWeight =
        (.46 + ensemble.agreement * .20 + populationSkill * .12)
            .clamp(.15, .85)
            .toDouble();
    contributions.add(ModelContribution(
      name: '100 analistas',
      probabilityUp: ensemble.probabilityUp,
      weight: ensembleWeight,
    ));

    // 2) The 50 mathematicians speak both through the analysts and directly,
    // because a theorem nobody on the floor likes is still evidence.
    if (briefing.isReady) {
      final councilWeight = (.16 + briefing.internalAgreement * .12) *
          (1 - briefing.dispersion * .45);
      contributions.add(ModelContribution(
        name: '50 matemáticos',
        probabilityUp: briefing.probabilityUp,
        weight: councilWeight.clamp(.04, .40).toDouble(),
      ));
    }

    // 3) The historical archive: what happened the other times the chart
    // looked like this.
    if (patterns.isReady) {
      final archiveWeight = (.18 + patterns.internalAgreement * .14) *
          (1 - patterns.dispersion * .40);
      contributions.add(ModelContribution(
        name: '100 patrones históricos',
        probabilityUp: patterns.probabilityUp,
        weight: archiveWeight.clamp(.05, .42).toDouble(),
      ));
    }

    // 4) The news floor. Headlines rarely decide a five-minute candle, so the
    // weight stays small unless the coverage is both fresh and one-sided.
    if (news.isReady) {
      final freshness = news.freshestMinutes.isFinite
          ? (1 - (news.freshestMinutes / 180).clamp(0.0, 1.0))
          : 0.0;
      final breaking = (news.breakingCount / 5).clamp(0.0, 1.0);
      final newsWeight = (.05 + freshness * .06 + breaking * .05) *
          (1 - news.dispersion * .35) *
          (.4 + news.internalAgreement * .6);
      contributions.add(ModelContribution(
        name: '50 analistas de noticias',
        probabilityUp: news.probabilityUp,
        weight: newsWeight.clamp(.01, .18).toDouble(),
      ));
    }

    if (statistical != null) {
      contributions.add(ModelContribution(
        name: 'Motor estadístico',
        probabilityUp: statistical.probabilityUp,
        weight: (.20 + statistical.signalQuality * .14).clamp(.06, .40).toDouble(),
      ));
    }

    if (calibrated != null) {
      contributions.add(ModelContribution(
        name: 'Calibrador',
        probabilityUp: calibrated.probabilityUp,
        weight: .12,
      ));
    }

    if (logistic != null && logistic.isReady) {
      final evidence =
          ((logistic.probabilityUp - .5).abs() * 2).clamp(0.0, 1.0).toDouble();
      contributions.add(ModelContribution(
        name: 'Logística BTC 5m',
        probabilityUp: logistic.probabilityUp,
        weight: (.04 + evidence * .03).clamp(.02, .09).toDouble(),
      ));
    }

    if (ai != null && ai.direction != PulseDirection.noTrade) {
      contributions.add(ModelContribution(
        name: 'Revisión IA',
        probabilityUp: ai.direction == PulseDirection.up
            ? ai.confidence / 100
            : 1 - ai.confidence / 100,
        weight: (.05 * (1 - instability)).clamp(.01, .05).toDouble(),
      ));
    }

    var pooled = 0.0;
    var weightSum = 0.0;
    for (final c in contributions) {
      pooled += _logit(c.probabilityUp) * c.weight;
      weightSum += c.weight;
    }
    if (weightSum <= 0) {
      return PulseConsensus(
        probabilityUp: .5,
        rawProbabilityUp: .5,
        direction: PulseDirection.noTrade,
        confidence: 50,
        agreement: 0,
        dispersion: 0,
        contributions: const <ModelContribution>[],
        ensemble: ensemble,
        briefing: briefing,
        news: news,
        patterns: patterns,
        evidence: 0,
      );
    }

    var logit = pooled / weightSum;

    // Cross-model coherence: if the sub-models point in opposite directions the
    // pooled evidence is worth less than its magnitude suggests.
    final directions = contributions
        .where((c) => (c.probabilityUp - .5).abs() > .01)
        .map((c) => c.probabilityUp > .5 ? 1.0 : -1.0)
        .toList();
    final coherence = directions.isEmpty
        ? 0.0
        : (directions.reduce((a, b) => a + b) / directions.length).abs();
    logit *= (.45 + coherence * .55);

    // Volatility and disagreement shrinkage.
    logit *= (1 - instability * .45).clamp(.35, 1.0);
    logit *= (1 - ensemble.dispersion * .35).clamp(.45, 1.0);

    final raw = _sigmoid(logit).clamp(.04, .96).toDouble();
    final calibratedProbability =
        evolution.scored >= 12 ? evolution.calibrate(raw) : raw;
    final probability = calibratedProbability.clamp(.05, .95).toDouble();

    final evidence = ((probability - .5).abs() * 2).clamp(0.0, 1.0).toDouble();

    return PulseConsensus(
      probabilityUp: probability,
      rawProbabilityUp: raw,
      direction: probability >= .5 ? PulseDirection.up : PulseDirection.down,
      confidence: math.max(probability, 1 - probability) * 100,
      agreement: ensemble.agreement,
      dispersion: ensemble.dispersion,
      contributions: List<ModelContribution>.unmodifiable(contributions),
      ensemble: ensemble,
      briefing: briefing,
      news: news,
      patterns: patterns,
      evidence: evidence,
    );
  }
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

double _logit(double p) {
  final q = p.clamp(1e-5, 1 - 1e-5);
  return math.log(q / (1 - q));
}
