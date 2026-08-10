import 'pulse_signal.dart';

class ConsensusReversalAlert {
  const ConsensusReversalAlert({
    required this.publishedDirection,
    required this.consensusDirection,
    required this.supportingAnalysts,
    required this.detectedAt,
  });

  final PulseDirection publishedDirection;
  final PulseDirection consensusDirection;
  final int supportingAnalysts;
  final DateTime detectedAt;
}

class ConsensusReversalAlertTracker {
  ConsensusReversalAlertTracker({
    this.minimumAnalysts = 60,
    this.requiredConsecutiveReadings = 3,
  });

  final int minimumAnalysts;
  final int requiredConsecutiveReadings;

  int _oppositeReadings = 0;
  int _recoveryReadings = 0;
  ConsensusReversalAlert? _activeAlert;

  ConsensusReversalAlert? get activeAlert => _activeAlert;

  ConsensusReversalAlert? update({
    required PulseDirection? publishedDirection,
    required PulseDirection consensusDirection,
    required int supportingAnalysts,
    required DateTime observedAt,
  }) {
    if (publishedDirection == null) {
      reset();
      return null;
    }

    final strongOpposite = consensusDirection != PulseDirection.noTrade &&
        consensusDirection != publishedDirection &&
        supportingAnalysts >= minimumAnalysts;
    if (strongOpposite) {
      _oppositeReadings++;
      _recoveryReadings = 0;
      if (_oppositeReadings >= requiredConsecutiveReadings) {
        _activeAlert = ConsensusReversalAlert(
          publishedDirection: publishedDirection,
          consensusDirection: consensusDirection,
          supportingAnalysts: supportingAnalysts,
          detectedAt: _activeAlert?.detectedAt ?? observedAt,
        );
      }
      return _activeAlert;
    }

    _oppositeReadings = 0;
    if (_activeAlert != null) {
      _recoveryReadings++;
      if (_recoveryReadings >= requiredConsecutiveReadings) {
        _activeAlert = null;
        _recoveryReadings = 0;
      }
    }
    return _activeAlert;
  }

  void reset() {
    _oppositeReadings = 0;
    _recoveryReadings = 0;
    _activeAlert = null;
  }
}
