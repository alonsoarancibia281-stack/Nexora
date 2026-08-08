import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_probability_calibrator.dart';

void main() {
  const calibrator = PulseProbabilityCalibrator();

  test('strong positive evidence produces probability above 50%', () {
    final r = calibrator.calibrate(
      score: 70,
      instability: 10,
      agreement: .9,
      roundDistancePct: .18,
      expectedRemainingMovePct: .15,
      secondsRemaining: 120,
    );
    expect(r.probabilityUp, greaterThan(.5));
    expect(r.confidence, greaterThan(50));
  });

  test('instability shrinks confidence toward 50%', () {
    final stable = calibrator.calibrate(
      score: 55,
      instability: 5,
      agreement: .85,
      roundDistancePct: .08,
      expectedRemainingMovePct: .18,
      secondsRemaining: 240,
    );
    final unstable = calibrator.calibrate(
      score: 55,
      instability: 90,
      agreement: .85,
      roundDistancePct: .08,
      expectedRemainingMovePct: .18,
      secondsRemaining: 240,
    );
    expect(unstable.confidence, lessThan(stable.confidence));
  });

  test('negative evidence favors down', () {
    final r = calibrator.calibrate(
      score: -65,
      instability: 15,
      agreement: .8,
      roundDistancePct: -.15,
      expectedRemainingMovePct: .16,
      secondsRemaining: 90,
    );
    expect(r.probabilityDown, greaterThan(.5));
  });
}
