import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_decision_gate.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

void main() {
  const bullish = PulseDecisionCandidate(
    probabilityUp: .63,
    analystAgreement: .68,
    statisticalQuality: .35,
    instability: 28,
    directionalVotes: 3,
  );

  test('does not emit a signal during calibration', () {
    final gate = PulseDecisionGate();
    final decision = gate.consider(
      candidate: bullish,
      elapsedSeconds: 44,
      observedAt: DateTime.utc(2026, 8, 8),
    );

    expect(decision, isNull);
  });

  test('locks a qualified signal', () {
    final gate = PulseDecisionGate();
    final decision = gate.consider(
      candidate: bullish,
      elapsedSeconds: 45,
      observedAt: DateTime.utc(2026, 8, 8),
    );

    expect(decision?.direction, PulseDirection.up);
    expect(decision?.probabilityUp, .63);
  });

  test('never flips a locked signal during the same round', () {
    final gate = PulseDecisionGate();
    final first = gate.consider(
      candidate: bullish,
      elapsedSeconds: 45,
      observedAt: DateTime.utc(2026, 8, 8),
    );
    final second = gate.consider(
      candidate: const PulseDecisionCandidate(
        probabilityUp: .31,
        analystAgreement: .74,
        statisticalQuality: .42,
        instability: 20,
        directionalVotes: 3,
      ),
      elapsedSeconds: 180,
      observedAt: DateTime.utc(2026, 8, 8, 0, 3),
    );

    expect(second, same(first));
    expect(second?.direction, PulseDirection.up);
  });

  test('abstains when evidence is weak', () {
    final gate = PulseDecisionGate();
    final decision = gate.consider(
      candidate: const PulseDecisionCandidate(
        probabilityUp: .52,
        analystAgreement: .51,
        statisticalQuality: .05,
        instability: 80,
        directionalVotes: 1,
      ),
      elapsedSeconds: 180,
      observedAt: DateTime.utc(2026, 8, 8),
    );

    expect(decision, isNull);
  });
}
