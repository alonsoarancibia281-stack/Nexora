import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/consensus_reversal_alert.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

void main() {
  final observedAt = DateTime.utc(2026, 8, 9, 20);

  test('activa alerta tras tres mayorías contrarias consecutivas', () {
    final tracker = ConsensusReversalAlertTracker();

    for (var reading = 0; reading < 2; reading++) {
      final alert = tracker.update(
        publishedDirection: PulseDirection.down,
        consensusDirection: PulseDirection.up,
        supportingAnalysts: 67,
        observedAt: observedAt.add(Duration(seconds: reading * 3)),
      );
      expect(alert, isNull);
    }
    final alert = tracker.update(
      publishedDirection: PulseDirection.down,
      consensusDirection: PulseDirection.up,
      supportingAnalysts: 67,
      observedAt: observedAt.add(const Duration(seconds: 6)),
    );

    expect(alert?.publishedDirection, PulseDirection.down);
    expect(alert?.consensusDirection, PulseDirection.up);
    expect(alert?.supportingAnalysts, 67);
  });

  test('no alerta con menos de sesenta analistas', () {
    final tracker = ConsensusReversalAlertTracker();

    for (var reading = 0; reading < 4; reading++) {
      expect(
        tracker.update(
          publishedDirection: PulseDirection.down,
          consensusDirection: PulseDirection.up,
          supportingAnalysts: 59,
          observedAt: observedAt,
        ),
        isNull,
      );
    }
  });

  test('limpia alerta después de tres lecturas recuperadas', () {
    final tracker = ConsensusReversalAlertTracker();
    for (var reading = 0; reading < 3; reading++) {
      tracker.update(
        publishedDirection: PulseDirection.down,
        consensusDirection: PulseDirection.up,
        supportingAnalysts: 65,
        observedAt: observedAt,
      );
    }

    for (var reading = 0; reading < 2; reading++) {
      expect(
        tracker.update(
          publishedDirection: PulseDirection.down,
          consensusDirection: PulseDirection.down,
          supportingAnalysts: 62,
          observedAt: observedAt,
        ),
        isNotNull,
      );
    }
    expect(
      tracker.update(
        publishedDirection: PulseDirection.down,
        consensusDirection: PulseDirection.down,
        supportingAnalysts: 62,
        observedAt: observedAt,
      ),
      isNull,
    );
  });
}
