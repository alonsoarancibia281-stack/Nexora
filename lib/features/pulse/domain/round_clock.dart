import 'prediction_horizon.dart';

/// One round: it opens and closes on an exact clock time, always in UTC so it
/// matches the Binance candle that settles it.
class RoundWindow {
  const RoundWindow({
    required this.horizon,
    required this.start,
    required this.end,
  });

  /// Round that contains [now].
  factory RoundWindow.at(PredictionHorizon horizon, DateTime now) {
    final utc = now.toUtc();
    final bucket = horizon.bucketMinutes;
    final start = bucket >= 60
        ? DateTime.utc(utc.year, utc.month, utc.day, utc.hour)
        : DateTime.utc(
            utc.year,
            utc.month,
            utc.day,
            utc.hour,
            (utc.minute ~/ bucket) * bucket,
          );
    return RoundWindow(
      horizon: horizon,
      start: start,
      end: start.add(horizon.duration),
    );
  }

  final PredictionHorizon horizon;
  final DateTime start;
  final DateTime end;

  RoundWindow get next => RoundWindow(
        horizon: horizon,
        start: end,
        end: end.add(horizon.duration),
      );

  /// The next [count] closing times after this round.
  List<DateTime> nextCloses(int count) {
    final closes = <DateTime>[];
    var window = this;
    for (var i = 0; i < count; i++) {
      closes.add(window.end);
      window = window.next;
    }
    return closes;
  }

  Duration remaining(DateTime now) {
    final left = end.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Whole seconds left, rounded up, so the counter never shows 0 too early.
  int secondsLeft(DateTime now) {
    final ms = remaining(now).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  double progress(DateTime now) {
    final left = remaining(now).inMilliseconds / 1000;
    return ((horizon.totalSeconds - left) / horizon.totalSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// How much of the round is gone, from 0 to 1.
  double elapsedRatio(DateTime now) => progress(now);

  bool isClosed(DateTime now) => !now.toUtc().isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is RoundWindow &&
      other.horizon == horizon &&
      other.start.isAtSameMomentAs(start);

  @override
  int get hashCode => Object.hash(horizon, start.millisecondsSinceEpoch);
}

/// Keeps the app clock aligned with the Binance server clock.
///
/// The offset is smoothed so a single slow answer never makes the counter
/// jump, but a real jump (device sleeps, network changes) is applied at once.
class ExchangeClock {
  Duration _offset = Duration.zero;
  bool _synced = false;

  Duration get offset => _offset;
  bool get isSynced => _synced;

  DateTime get now => DateTime.now().toUtc().add(_offset);

  /// Feeds one measurement taken between [before] and [after].
  void apply({
    required DateTime before,
    required DateTime serverTime,
    required DateTime after,
  }) {
    final midpoint = before.toUtc().add(
          Duration(
            microseconds:
                after.toUtc().difference(before.toUtc()).inMicroseconds ~/ 2,
          ),
        );
    final measured = serverTime.toUtc().difference(midpoint);
    if (!_synced || (measured - _offset).inMilliseconds.abs() > 1500) {
      _offset = measured;
    } else {
      _offset = Duration(
        microseconds:
            (_offset.inMicroseconds * .65 + measured.inMicroseconds * .35)
                .round(),
      );
    }
    _synced = true;
  }
}
