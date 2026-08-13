import 'dart:math' as math;

import 'pulse_audit_board.dart';
import 'pulse_consensus_engine.dart';
import 'pulse_signal.dart';

/// One reading taken during the chief analyst's decision window.
class ChiefSample {
  const ChiefSample({
    required this.takenAt,
    required this.secondsRemaining,
    required this.probabilityUp,
    required this.price,
    required this.instability,
    required this.ensembleProbability,
    required this.mathProbability,
    required this.patternProbability,
    required this.newsProbability,
  });

  final DateTime takenAt;
  final int secondsRemaining;
  final double probabilityUp;
  final double price;
  final double instability;
  final double ensembleProbability;
  final double mathProbability;
  final double patternProbability;
  final double newsProbability;
}

/// What one council contributed to the chief analyst's decision.
class CouncilVote {
  const CouncilVote({
    required this.council,
    required this.probabilityUp,
    required this.members,
    required this.agreement,
  });

  final String council;
  final double probabilityUp;
  final int members;
  final double agreement;

  bool get isUp => probabilityUp >= .5;

  String get directionLabel => isUp ? 'SUBE' : 'BAJA';
}

/// The single, final call for a 5-minute round.
class ChiefVerdict {
  const ChiefVerdict({
    required this.direction,
    required this.probabilityUp,
    required this.confidence,
    required this.decidedAt,
    required this.decidedAtSecondsRemaining,
    required this.entryPrice,
    required this.samplesUsed,
    required this.stability,
    required this.councilVotes,
    required this.dissent,
    required this.rationale,
    required this.headline,
    required this.auditVerdict,
    required this.auditQuality,
    required this.fullDeliberation,
  });

  final PulseDirection direction;
  final double probabilityUp;
  final double confidence;
  final DateTime decidedAt;

  /// Seconds left in the round at the moment the call was locked.
  final int decidedAtSecondsRemaining;

  /// Price the call was made against (the round open).
  final double entryPrice;

  final int samplesUsed;

  /// How steady the evidence was during the decision minute, in [0,1].
  final double stability;

  final List<CouncilVote> councilVotes;

  /// Share of councils that voted against the final call.
  final double dissent;

  final List<String> rationale;
  final String headline;

  /// Result of the 100-auditor final test on the packet that was handed over.
  final AuditVerdict auditVerdict;
  final double auditQuality;

  /// False when the call had to be made without a complete decision window —
  /// typically because the app joined the round after the first minute. The
  /// conviction is cut accordingly and the screen says so.
  final bool fullDeliberation;

  bool get isUp => direction == PulseDirection.up;

  int get councilsInFavour =>
      councilVotes.where((v) => v.isUp == isUp).length;

  int get totalAnalysts {
    var total = 0;
    for (final vote in councilVotes) {
      total += vote.members;
    }
    return total;
  }
}

/// The chief analyst.
///
/// Every council — the 100 market analysts, the 50 mathematicians, the 100
/// historical pattern analysts and the 50 news analysts — reports to this one
/// agent. It listens for the first minute of the round, watching whether the
/// evidence holds still or thrashes, and then locks a single call for the
/// remaining four minutes. It does not revise afterwards: a call that keeps
/// changing is not a call.
class PulseChiefAnalyst {
  const PulseChiefAnalyst();

  /// Length of the deliberation window, in seconds.
  static const int decisionWindowSeconds = 60;

  /// Round time left when the verdict must be on the table.
  static const int lockAtSecondsRemaining = 300 - decisionWindowSeconds;

  /// Recency half-life inside the decision window, in seconds.
  static const double recencyHalfLifeSeconds = 22;

  /// Readings required before the decision window counts as complete.
  static const int minimumSamples = 4;

  /// Tolerance, in seconds, for arriving late to the lock moment.
  static const int lockToleranceSeconds = 20;

  ChiefVerdict decide({
    required List<ChiefSample> samples,
    required PulseConsensus consensus,
    required AuditReport audit,
    required PulseSignal signal,
    required double entryPrice,
    required DateTime decidedAt,
    required int secondsRemaining,
  }) {
    final pool = samples.isEmpty
        ? <ChiefSample>[
            ChiefSample(
              takenAt: decidedAt,
              secondsRemaining: secondsRemaining,
              probabilityUp: audit.probabilityUp,
              price: entryPrice,
              instability: signal.instabilityScore,
              ensembleProbability: consensus.ensemble.probabilityUp,
              mathProbability: consensus.briefing.probabilityUp,
              patternProbability: consensus.patterns.probabilityUp,
              newsProbability: consensus.news.probabilityUp,
            ),
          ]
        : samples;

    // Recency-weighted log-odds pooling across the decision minute.
    final newest = pool.last.secondsRemaining;
    var weighted = 0.0;
    var weightSum = 0.0;
    final logits = <double>[];
    for (final sample in pool) {
      final age = (sample.secondsRemaining - newest).abs().toDouble();
      final weight = math.pow(.5, age / recencyHalfLifeSeconds).toDouble();
      final logit = _logit(sample.probabilityUp);
      logits.add(logit);
      weighted += logit * weight;
      weightSum += weight;
    }
    var logit = weightSum <= 0 ? 0.0 : weighted / weightSum;

    // Evidence that swung wildly during the minute is worth less than evidence
    // that stayed put.
    final spread = _std(logits);
    final stability = (1 - (spread / 1.1).clamp(0.0, 1.0)).toDouble();
    logit *= (.55 + stability * .45);

    final councils = <CouncilVote>[
      CouncilVote(
        council: 'Analistas de mercado',
        probabilityUp: consensus.ensemble.probabilityUp,
        members: consensus.ensemble.opinions.length,
        agreement: consensus.ensemble.agreement,
      ),
      CouncilVote(
        council: 'Matemáticos',
        probabilityUp: consensus.briefing.probabilityUp,
        members: consensus.briefing.mathematicians,
        agreement: consensus.briefing.internalAgreement,
      ),
      CouncilVote(
        council: 'Patrones históricos',
        probabilityUp: consensus.patterns.probabilityUp,
        members: consensus.patterns.analysts,
        agreement: consensus.patterns.internalAgreement,
      ),
      CouncilVote(
        council: 'Noticias en vivo',
        probabilityUp: consensus.news.probabilityUp,
        members: consensus.news.analysts,
        agreement: consensus.news.internalAgreement,
      ),
    ].where((v) => v.members > 0).toList();

    // The audit board's haircut is applied on top of everything else: it is
    // the last gate before the call is made.
    logit *= audit.shrinkFactor;
    if (audit.verdict == AuditVerdict.vetoed) logit *= .45;

    // A window that never happened cannot carry the conviction of one that
    // did: joining a round late means the call rests on a single glance.
    final fullDeliberation = pool.length >= minimumSamples &&
        secondsRemaining >= lockAtSecondsRemaining - lockToleranceSeconds;
    if (!fullDeliberation) {
      final coverage = (pool.length / minimumSamples).clamp(.25, 1.0);
      logit *= (.40 + coverage * .35);
    }

    final probability = _sigmoid(logit).clamp(.05, .95).toDouble();
    final up = probability >= .5;
    final against = councils.where((v) => v.isUp != up).length;
    final dissent = councils.isEmpty ? 0.0 : against / councils.length;

    // A divided house lowers the final conviction but never flips the call.
    final adjusted = .5 + (probability - .5) * (1 - dissent * .45);
    final finalProbability = adjusted.clamp(.05, .95).toDouble();
    final finalUp = finalProbability >= .5;

    final rationale = <String>[];
    for (final vote in councils) {
      rationale.add(
        '${vote.council} (${vote.members}): ${vote.directionLabel} '
        '${(math.max(vote.probabilityUp, 1 - vote.probabilityUp) * 100).toStringAsFixed(1)}% '
        '· acuerdo interno ${(vote.agreement * 100).toStringAsFixed(0)}%',
      );
    }
    rationale.add(
      'Estabilidad de la evidencia durante el minuto de decisión: '
      '${(stability * 100).toStringAsFixed(0)}% sobre ${pool.length} lecturas.',
    );
    if (!fullDeliberation) {
      rationale.add(
        'Ventana de decisión incompleta: la ronda ya estaba en curso al abrir '
        'la app, así que la convicción se recortó.',
      );
    }
    rationale.add(
      'Mercado ${signal.stabilityLabel.toLowerCase()} '
      '(inestabilidad ${signal.instabilityScore.toStringAsFixed(0)}/100).',
    );
    rationale.add(
      'Test final de auditoría: ${audit.verdict.label.toLowerCase()} · '
      '${audit.passed}/${audit.auditors} auditores conformes · '
      'recorte de evidencia ${((1 - audit.shrinkFactor) * 100).toStringAsFixed(0)}%.',
    );
    for (final flag in audit.flags.take(3)) {
      rationale.add('Observación de auditoría — $flag');
    }
    if (dissent > 0) {
      rationale.add(
        '$against de ${councils.length} consejos votaron en contra: la confianza se recortó en consecuencia.',
      );
    }

    final headline = finalUp
        ? 'El mercado cierra los 5 minutos EN SUBIDA'
        : 'El mercado cierra los 5 minutos EN BAJADA';

    return ChiefVerdict(
      direction: finalUp ? PulseDirection.up : PulseDirection.down,
      probabilityUp: finalProbability,
      confidence: math.max(finalProbability, 1 - finalProbability) * 100,
      decidedAt: decidedAt,
      decidedAtSecondsRemaining: secondsRemaining,
      entryPrice: entryPrice,
      samplesUsed: pool.length,
      stability: stability,
      councilVotes: List<CouncilVote>.unmodifiable(councils),
      dissent: dissent,
      rationale: List<String>.unmodifiable(rationale),
      headline: headline,
      auditVerdict: audit.verdict,
      auditQuality: audit.qualityScore,
      fullDeliberation: fullDeliberation,
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
