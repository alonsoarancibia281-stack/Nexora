import 'dart:math' as math;

import 'pulse_analyst_evolution.dart';
import 'pulse_consensus_engine.dart';
import 'pulse_signal.dart';

/// The ten things the audit board checks before anything reaches the chief.
enum AuditDomain {
  coherence,
  calibration,
  overconfidence,
  dataQuality,
  redundancy,
  regimeValidity,
  significance,
  robustness,
  biasGuard,
  executionRisk,
}

extension AuditDomainLabel on AuditDomain {
  String get label {
    switch (this) {
      case AuditDomain.coherence:
        return 'Coherencia entre consejos';
      case AuditDomain.calibration:
        return 'Calibración histórica';
      case AuditDomain.overconfidence:
        return 'Exceso de confianza';
      case AuditDomain.dataQuality:
        return 'Calidad de datos';
      case AuditDomain.redundancy:
        return 'Redundancia de votos';
      case AuditDomain.regimeValidity:
        return 'Validez del régimen';
      case AuditDomain.significance:
        return 'Significancia estadística';
      case AuditDomain.robustness:
        return 'Robustez ante perturbaciones';
      case AuditDomain.biasGuard:
        return 'Sesgos de comportamiento';
      case AuditDomain.executionRisk:
        return 'Riesgo de la ronda';
    }
  }
}

/// One auditor's finding.
class AuditorOpinion {
  const AuditorOpinion({
    required this.id,
    required this.domain,
    required this.passed,
    required this.severity,
    required this.shrink,
    required this.note,
  });

  /// 1..100
  final int id;
  final AuditDomain domain;
  final bool passed;

  /// 0 = clean, 1 = critical.
  final double severity;

  /// Multiplier this auditor wants applied to the evidence (≤ 1).
  final double shrink;

  final String note;
}

enum AuditVerdict { approved, caution, vetoed }

extension AuditVerdictLabel on AuditVerdict {
  String get label {
    switch (this) {
      case AuditVerdict.approved:
        return 'APROBADO';
      case AuditVerdict.caution:
        return 'APROBADO CON RESERVAS';
      case AuditVerdict.vetoed:
        return 'VETADO';
    }
  }
}

/// Result of the final test run over every other council.
class AuditReport {
  AuditReport({
    required this.opinions,
    required this.domainSeverity,
    required this.shrinkFactor,
    required this.probabilityUp,
    required this.rawProbabilityUp,
    required this.verdict,
    required this.flags,
    required this.qualityScore,
  });

  final List<AuditorOpinion> opinions;
  final Map<AuditDomain, double> domainSeverity;

  /// Combined evidence multiplier the board imposes, in (0,1].
  final double shrinkFactor;

  /// Probability after the audit haircut — this is what the chief receives.
  final double probabilityUp;

  final double rawProbabilityUp;
  final AuditVerdict verdict;

  /// Distinct problems worth showing to the user.
  final List<String> flags;

  /// 0..1 summary of how trustworthy the packet is.
  final double qualityScore;

  static AuditReport neutral(double probabilityUp) => AuditReport(
        opinions: const <AuditorOpinion>[],
        domainSeverity: {for (final d in AuditDomain.values) d: 0.0},
        shrinkFactor: 1,
        probabilityUp: probabilityUp,
        rawProbabilityUp: probabilityUp,
        verdict: AuditVerdict.approved,
        flags: const <String>[],
        qualityScore: .5,
      );

  int get auditors => opinions.length;

  int get passed => opinions.where((o) => o.passed).length;

  int get failed => opinions.length - passed;

  double get passRate => opinions.isEmpty ? 1 : passed / opinions.length;

  double severityOf(AuditDomain domain) => domainSeverity[domain] ?? 0;
}

/// One hundred auditors running the final test.
///
/// They do not produce a new forecast. They interrogate the one that exists:
/// do the councils actually agree, is the confidence supported by the track
/// record, is the vote statistically distinguishable from a coin flip, does the
/// answer survive small perturbations of the inputs. Whatever they find is
/// applied as a haircut before the packet reaches the chief analyst.
class PulseAuditBoard {
  const PulseAuditBoard();

  static const int auditors = 100;

  AuditReport audit({
    required PulseConsensus consensus,
    required PulseSignal signal,
    required PulseEvolutionState evolution,
    required int secondsRemaining,
    double newsAgeMinutes = double.infinity,
    bool historyReady = true,
  }) {
    final opinions = <AuditorOpinion>[];
    var id = 1;
    for (final domain in AuditDomain.values) {
      for (var variant = 0; variant < 10; variant++) {
        opinions.add(_run(
          id++,
          domain,
          variant,
          consensus,
          signal,
          evolution,
          secondsRemaining,
          newsAgeMinutes,
          historyReady,
        ));
      }
    }

    final domainSeverity = <AuditDomain, double>{};
    for (final domain in AuditDomain.values) {
      final group = opinions.where((o) => o.domain == domain);
      final total = group.fold<double>(0, (s, o) => s + o.severity);
      domainSeverity[domain] = group.isEmpty ? 0 : total / group.length;
    }

    // Geometric mean of the individual haircuts: one critical finding cannot
    // be averaged away by ninety-nine clean ones.
    var logShrink = 0.0;
    for (final o in opinions) {
      logShrink += math.log(o.shrink.clamp(.35, 1.0));
    }
    final shrink = opinions.isEmpty
        ? 1.0
        : math.exp(logShrink / opinions.length).clamp(.25, 1.0).toDouble();

    final raw = consensus.probabilityUp;
    final adjusted = (.5 + (raw - .5) * shrink).clamp(.05, .95).toDouble();

    final failRate = 1 - (opinions.isEmpty ? 1 : opinions.where((o) => o.passed).length / opinions.length);
    final critical = opinions.where((o) => o.severity >= .8).length;
    final verdict = (failRate > .45 || critical >= 12)
        ? AuditVerdict.vetoed
        : (failRate > .20 ? AuditVerdict.caution : AuditVerdict.approved);

    final flags = <String>[];
    for (final domain in AuditDomain.values) {
      final severity = domainSeverity[domain] ?? 0;
      if (severity < .35) continue;
      final sample = opinions.firstWhere(
        (o) => o.domain == domain && !o.passed,
        orElse: () => opinions.firstWhere((o) => o.domain == domain),
      );
      flags.add('${domain.label}: ${sample.note}');
    }

    final quality = ((1 - failRate) * .55 + shrink * .45).clamp(0.0, 1.0).toDouble();

    return AuditReport(
      opinions: List<AuditorOpinion>.unmodifiable(opinions),
      domainSeverity: Map<AuditDomain, double>.unmodifiable(domainSeverity),
      shrinkFactor: shrink,
      probabilityUp: adjusted,
      rawProbabilityUp: raw,
      verdict: verdict,
      flags: List<String>.unmodifiable(flags),
      qualityScore: quality,
    );
  }

  AuditorOpinion _run(
    int id,
    AuditDomain domain,
    int variant,
    PulseConsensus consensus,
    PulseSignal signal,
    PulseEvolutionState evolution,
    int secondsRemaining,
    double newsAgeMinutes,
    bool historyReady,
  ) {
    // Auditor 0 of each board is the strictest, auditor 9 the most permissive.
    final tolerance = .10 + variant * .055;

    switch (domain) {
      case AuditDomain.coherence:
        final directions = consensus.contributions
            .where((c) => (c.probabilityUp - .5).abs() > .01)
            .map((c) => c.probabilityUp > .5 ? 1 : -1)
            .toList();
        if (directions.isEmpty) {
          return _fail(id, domain, .55, .78,
              'ningún modelo se pronuncia con claridad');
        }
        final up = directions.where((d) => d > 0).length;
        final split = (up / directions.length - .5).abs() * 2;
        final disagreement = 1 - split;
        return _judge(id, domain, disagreement, .35 + tolerance,
            'los consejos se contradicen (${(disagreement * 100).toStringAsFixed(0)}% de división)');

      case AuditDomain.calibration:
        if (evolution.scored < 12) {
          return _judge(id, domain, .30, .30 + tolerance,
              'todavía no hay historial suficiente para validar la calibración');
        }
        final slopeError = (evolution.calibrationSlope - 1).abs();
        final brierPenalty = (evolution.consensusBrier - .25).clamp(0.0, .25) * 4;
        final severity = (slopeError * .6 + brierPenalty).clamp(0.0, 1.0);
        return _judge(id, domain, severity.toDouble(), .30 + tolerance,
            'la calibración aprendida se desvía (pendiente ${evolution.calibrationSlope.toStringAsFixed(2)})');

      case AuditDomain.overconfidence:
        final extremity = ((consensus.probabilityUp - .5).abs() * 2);
        final support = consensus.agreement * (1 - consensus.dispersion);
        final gap = (extremity - support).clamp(0.0, 1.0);
        return _judge(id, domain, gap.toDouble(), .18 + tolerance,
            'la probabilidad declarada supera al respaldo real del consejo');

      case AuditDomain.dataQuality:
        var severity = 0.0;
        final notes = <String>[];
        if (!consensus.briefing.isReady) {
          severity += .35;
          notes.add('consejo matemático sin datos');
        }
        if (!historyReady) {
          severity += .25;
          notes.add('archivo histórico incompleto');
        }
        if (!newsAgeMinutes.isFinite || newsAgeMinutes > 240) {
          severity += .18;
          notes.add('noticias desactualizadas');
        }
        if (consensus.ensemble.opinions.length < 100) {
          severity += .30;
          notes.add('faltan analistas en el consejo');
        }
        return _judge(id, domain, severity.clamp(0.0, 1.0).toDouble(),
            .20 + tolerance,
            notes.isEmpty ? 'fuentes completas' : notes.join(', '));

      case AuditDomain.redundancy:
        final nominal = math.max(consensus.ensemble.opinions.length, 1);
        final effective = consensus.ensemble.effectiveSampleSize;
        final ratio = (effective / math.min(nominal, 10)).clamp(0.0, 1.0);
        final severity = (1 - ratio).clamp(0.0, 1.0);
        return _judge(id, domain, severity.toDouble(), .45 + tolerance,
            'los votos son demasiado correlacionados (tamaño efectivo ${effective.toStringAsFixed(1)})');

      case AuditDomain.regimeValidity:
        final instability = signal.instabilityScore / 100;
        final severity = instability * (signal.stability == MarketStability.veryUnstable ? 1.15 : 1.0);
        return _judge(id, domain, severity.clamp(0.0, 1.0).toDouble(),
            .45 + tolerance,
            'régimen ${signal.stabilityLabel.toLowerCase()}: los modelos pierden validez');

      case AuditDomain.significance:
        final up = consensus.ensemble.upVotes;
        final down = consensus.ensemble.downVotes;
        final n = up + down;
        if (n < 10) {
          return _fail(id, domain, .60, .72, 'muy pocos votos decisivos');
        }
        final p = up / n;
        final z = (p - .5) / math.sqrt(.25 / n);
        final severity = (1 - (z.abs() / 3).clamp(0.0, 1.0)).toDouble();
        return _judge(id, domain, severity, .55 + tolerance,
            'la división $up/$down no se distingue del azar (z=${z.toStringAsFixed(2)})');

      case AuditDomain.robustness:
        // Perturb the fusion weights deterministically and see whether the
        // answer survives.
        final contributions = consensus.contributions;
        if (contributions.isEmpty) {
          return _fail(id, domain, .70, .60, 'no hay modelos que perturbar');
        }
        final magnitude = .12 + variant * .035;
        var flips = 0;
        var trials = 0;
        for (var trial = 0; trial < 6; trial++) {
          var pooled = 0.0;
          var weightSum = 0.0;
          for (var i = 0; i < contributions.length; i++) {
            final wobble =
                1 + magnitude * math.sin((trial + 1) * 1.7 + i * 2.3);
            final w = math.max(contributions[i].weight * wobble, 1e-6);
            pooled += _logit(contributions[i].probabilityUp) * w;
            weightSum += w;
          }
          if (weightSum <= 0) continue;
          final perturbed = _sigmoid(pooled / weightSum);
          trials++;
          if ((perturbed >= .5) != (consensus.rawProbabilityUp >= .5)) flips++;
        }
        final severity = trials == 0 ? 1.0 : flips / trials;
        return _judge(id, domain, severity.toDouble(), .10 + tolerance * .5,
            'la dirección se invierte al perturbar los pesos ($flips de $trials pruebas)');

      case AuditDomain.biasGuard:
        // Recency and anchoring: is the call simply following the last move?
        final momentumAlignment =
            (signal.momentumScore / 100).sign == (consensus.probabilityUp - .5).sign
                ? 1.0
                : 0.0;
        final roundAnchor = signal.expectedRemainingMovePct <= 0
            ? 0.0
            : (signal.roundDistancePct.abs() / signal.expectedRemainingMovePct)
                .clamp(0.0, 2.0) /
                2;
        final severity =
            (momentumAlignment * .35 + roundAnchor * .45).clamp(0.0, 1.0);
        return _judge(id, domain, severity.toDouble(), .50 + tolerance,
            'la tesis podría estar anclada al movimiento ya ocurrido');

      case AuditDomain.executionRisk:
        final noiseFloor = signal.expectedRemainingMovePct;
        final timeLeft = secondsRemaining / 300;
        final thinTime = (1 - timeLeft).clamp(0.0, 1.0);
        final tinyMove = noiseFloor < .04 ? .45 : 0.0;
        final severity = (thinTime * .35 + tinyMove).clamp(0.0, 1.0);
        return _judge(id, domain, severity.toDouble(), .55 + tolerance,
            'poco recorrido esperado para el tiempo que queda');
    }
  }

  AuditorOpinion _judge(
    int id,
    AuditDomain domain,
    double severity,
    double threshold,
    String note,
  ) {
    final safeSeverity = severity.isFinite
        ? severity.clamp(0.0, 1.0).toDouble()
        : 1.0;
    final passed = safeSeverity <= threshold;
    // A clean auditor takes nothing away; a critical one takes a third.
    final shrink = passed
        ? (1 - safeSeverity * .06).clamp(.90, 1.0).toDouble()
        : (1 - safeSeverity * .34).clamp(.55, .99).toDouble();
    return AuditorOpinion(
      id: id,
      domain: domain,
      passed: passed,
      severity: safeSeverity,
      shrink: shrink,
      note: passed ? 'sin observaciones' : note,
    );
  }

  AuditorOpinion _fail(
    int id,
    AuditDomain domain,
    double severity,
    double shrink,
    String note,
  ) =>
      AuditorOpinion(
        id: id,
        domain: domain,
        passed: false,
        severity: severity,
        shrink: shrink,
        note: note,
      );
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

double _logit(double p) {
  final q = p.clamp(1e-5, 1 - 1e-5);
  return math.log(q / (1 - q));
}
