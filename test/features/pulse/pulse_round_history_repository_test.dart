import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/data/pulse_round_history_repository.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_round_tracker.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists a real round and replaces duplicates', () async {
    final repository = PulseRoundHistoryRepository();
    final start = DateTime.utc(2026, 8, 8, 12);
    PulseRoundOutcome outcome(double endPrice) => PulseRoundOutcome(
          roundStart: start,
          startPrice: 67000,
          endPrice: endPrice,
          observations: [
            PulseRoundObservation(
              roundStart: start,
              observedAt: start.add(const Duration(minutes: 1)),
              secondsRemaining: 240,
              startPrice: 67000,
              observedPrice: 67050,
              predictedDirection: PulseDirection.up,
              probabilityUp: .63,
              instability: 24,
            ),
          ],
        );

    await repository.add(outcome(67100));
    await repository.add(outcome(67200));
    final loaded = await repository.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.endPrice, 67200);
    expect(loaded.single.observations.single.probabilityUp, .63);
  });
}
