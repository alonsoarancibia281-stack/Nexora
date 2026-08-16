import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/pulse/domain/exit_watch.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_alert.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_horizon.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_outlook.dart';
import 'package:nexora_markets_ai/features/pulse/domain/round_clock.dart';
import 'package:nexora_markets_ai/features/pulse/domain/round_journal.dart';

final window = RoundWindow.at(
  PredictionHorizon.m5,
  DateTime.utc(2026, 8, 16, 14, 31),
);

PredictionOutlook outlook({
  required double probabilityUp,
  PredictionCall? call,
  double distancePercent = .05,
  int secondsLeft = 200,
  double instability = 20,
  double agreement = .8,
  int secondsIntoRound = 0,
  RoundWindow? round,
}) {
  final resolved = round ?? window;
  final edge = probabilityUp - .5;
  return PredictionOutlook(
    horizon: PredictionHorizon.m5,
    window: resolved,
    call: call ??
        (edge.abs() < .055
            ? PredictionCall.wait
            : edge > 0
                ? PredictionCall.up
                : PredictionCall.down),
    probabilityUp: probabilityUp,
    agreement: agreement,
    views: const [],
    price: 100 * (1 + distancePercent / 100),
    startPrice: 100,
    distancePercent: distancePercent,
    expectedMovePercent: .10,
    instability: instability,
    secondsLeft: secondsLeft,
    updatedAt: resolved.start.add(Duration(seconds: secondsIntoRound)),
    reasons: const [],
  );
}

void main() {
  group('exit watch', () {
    test('stays idle until the desk takes a side', () {
      final watcher = ExitWatcher();
      final advice = watcher.update(outlook(probabilityUp: .52));
      expect(advice.level, ExitLevel.calm);
      expect(advice.isOpen, isFalse);
      expect(watcher.lockedAt, isNull);
    });

    test('opens a call and remembers the exact time', () {
      final watcher = ExitWatcher();
      final advice = watcher.update(
        outlook(probabilityUp: .72, secondsIntoRound: 40),
      );
      expect(advice.isOpen, isTrue);
      expect(advice.call, PredictionCall.up);
      expect(advice.level, ExitLevel.calm);
      expect(watcher.lockedAt, window.start.add(const Duration(seconds: 40)));
    });

    test('warns before the edge is gone', () {
      final watcher = ExitWatcher();
      watcher.update(outlook(probabilityUp: .74, secondsIntoRound: 30));
      final advice = watcher.update(
        outlook(probabilityUp: .60, secondsIntoRound: 60, call: PredictionCall.up),
      );
      expect(advice.level, ExitLevel.watch);
      expect(advice.drop, closeTo(.14, .001));
    });

    test('calls the exit when the edge falls under a coin flip', () {
      final watcher = ExitWatcher();
      watcher.update(outlook(probabilityUp: .70, secondsIntoRound: 30));
      final advice = watcher.update(
        outlook(
          probabilityUp: .46,
          secondsIntoRound: 90,
          call: PredictionCall.up,
        ),
      );
      expect(advice.level, ExitLevel.exit);
      expect(advice.title, 'Sal ahora');
    });

    test('calls the exit when the desk changes side', () {
      final watcher = ExitWatcher();
      watcher.update(outlook(probabilityUp: .70, secondsIntoRound: 20));
      final advice = watcher.update(
        outlook(
          probabilityUp: .58,
          call: PredictionCall.down,
          secondsIntoRound: 70,
        ),
      );
      expect(advice.level, ExitLevel.exit);
    });

    test('calls the exit when price runs the other way near the close', () {
      final watcher = ExitWatcher();
      watcher.update(outlook(probabilityUp: .70, secondsIntoRound: 20));
      final advice = watcher.update(
        outlook(
          probabilityUp: .62,
          call: PredictionCall.up,
          distancePercent: -.08,
          secondsLeft: 60,
          secondsIntoRound: 240,
        ),
      );
      expect(advice.level, ExitLevel.exit);
    });

    test('forgets the old call when a new round opens', () {
      final watcher = ExitWatcher();
      watcher.update(outlook(probabilityUp: .74));
      expect(watcher.call, PredictionCall.up);
      final advice = watcher.update(
        outlook(probabilityUp: .52, round: window.next),
      );
      expect(watcher.call, PredictionCall.wait);
      expect(advice.isOpen, isFalse);
    });
  });

  group('alerts', () {
    test('announces one signal, one change and one exit per round', () {
      final center = PredictionAlertCenter();
      final watcher = ExitWatcher();

      final first = outlook(probabilityUp: .72, secondsIntoRound: 30);
      var born = center.ingest(
        outlook: first,
        advice: watcher.update(first),
        closeClock: '14:35',
      );
      expect(born.length, 1);
      expect(born.first.kind, PredictionAlertKind.open);
      expect(born.first.title, contains('5 min'));

      // The same reading twice does not repeat the alert.
      final again = outlook(probabilityUp: .73, secondsIntoRound: 35);
      born = center.ingest(
        outlook: again,
        advice: watcher.update(again),
        closeClock: '14:35',
      );
      expect(born, isEmpty);

      final turn = outlook(
        probabilityUp: .30,
        call: PredictionCall.down,
        secondsIntoRound: 60,
      );
      born = center.ingest(
        outlook: turn,
        advice: watcher.update(turn),
        closeClock: '14:35',
      );
      expect(born.any((alert) => alert.kind == PredictionAlertKind.exit), isTrue);
      expect(center.alerts.first.isUrgent, isTrue);
    });

    test('announces the result once', () {
      final center = PredictionAlertCenter();
      final alert = center.announceResult(
        horizon: PredictionHorizon.m5,
        window: window,
        call: PredictionCall.up,
        closedUp: true,
        changePercent: .12,
        at: window.end,
        closeClock: '14:35',
      );
      expect(alert, isNotNull);
      expect(alert!.message, contains('acierta'));
      expect(
        center.announceResult(
          horizon: PredictionHorizon.m5,
          window: window,
          call: PredictionCall.up,
          closedUp: true,
          changePercent: .12,
          at: window.end,
          closeClock: '14:35',
        ),
        isNull,
      );
    });
  });

  group('journal', () {
    test('counts hits only on rounds with a call', () {
      final journal = RoundJournal();
      journal.add(
        RoundResult(
          horizon: PredictionHorizon.m5,
          window: window,
          call: PredictionCall.up,
          probability: .7,
          startPrice: 100,
          endPrice: 101,
        ),
      );
      journal.add(
        RoundResult(
          horizon: PredictionHorizon.m5,
          window: window.next,
          call: PredictionCall.down,
          probability: .66,
          startPrice: 100,
          endPrice: 101,
        ),
      );
      journal.add(
        RoundResult(
          horizon: PredictionHorizon.m5,
          window: window.next.next,
          call: PredictionCall.wait,
          probability: .52,
          startPrice: 100,
          endPrice: 101,
        ),
      );

      final score = journal.scoreFor(PredictionHorizon.m5);
      expect(score.calls, 2);
      expect(score.hits, 1);
      expect(journal.accuracyFor(PredictionHorizon.m5), .5);
      expect(journal.accuracyFor(PredictionHorizon.h1), isNull);
    });
  });
}
