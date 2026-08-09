import 'pulse_signal.dart';

class PulseDecisionCandidate {
  const PulseDecisionCandidate({
    required this.probabilityUp,
    required this.analystAgreement,
    required this.statisticalQuality,
    required this.instability,
    required this.directionalVotes,
  });

  final double probabilityUp;
  final double analystAgreement;
  final double statisticalQuality;
  final double instability;
  final int directionalVotes;

  double get confidence =>
      (probabilityUp >= .5 ? probabilityUp : 1 - probabilityUp) * 100;
}

class LockedPulseDecision {
  const LockedPulseDecision({
    required this.direction,
    required this.probabilityUp,
    required this.lockedAt,
  });

  final PulseDirection direction;
  final double probabilityUp;
  final DateTime lockedAt;

  double get confidence =>
      (probabilityUp >= .5 ? probabilityUp : 1 - probabilityUp) * 100;
}

/// Emits at most one directional decision per five-minute round.
///
/// The first seconds are deliberately reserved for calibration. Weak or
/// contradictory evidence produces no signal instead of a forced prediction.
class PulseDecisionGate {
  PulseDecisionGate({
    this.minimumCalibrationSeconds = 45,
    this.minimumConfidence = 55,
    this.minimumAgreement = .58,
    this.minimumStatisticalQuality = .12,
    this.maximumInstability = 72,
    this.minimumDirectionalVotes = 2,
  });

  final int minimumCalibrationSeconds;
  final double minimumConfidence;
  final double minimumAgreement;
  final double minimumStatisticalQuality;
  final double maximumInstability;
  final int minimumDirectionalVotes;

  LockedPulseDecision? _locked;

  LockedPulseDecision? get locked => _locked;

  LockedPulseDecision? consider({
    required PulseDecisionCandidate candidate,
    required int elapsedSeconds,
    required DateTime observedAt,
    bool historicalAuditPassed = true,
  }) {
    if (_locked != null) return _locked;
    if (!historicalAuditPassed ||
        elapsedSeconds < minimumCalibrationSeconds ||
        candidate.confidence < minimumConfidence ||
        candidate.analystAgreement < minimumAgreement ||
        candidate.statisticalQuality < minimumStatisticalQuality ||
        candidate.instability > maximumInstability ||
        candidate.directionalVotes < minimumDirectionalVotes) {
      return null;
    }

    _locked = LockedPulseDecision(
      direction: candidate.probabilityUp >= .5
          ? PulseDirection.up
          : PulseDirection.down,
      probabilityUp: candidate.probabilityUp.clamp(.08, .92).toDouble(),
      lockedAt: observedAt,
    );
    return _locked;
  }

  void reset() => _locked = null;
}
