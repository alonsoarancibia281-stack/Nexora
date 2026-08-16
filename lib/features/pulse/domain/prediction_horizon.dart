/// Time windows Nexora predicts on.
///
/// Every window closes on a fixed clock bucket, exactly like a Binance
/// candle: 5 minutes closes at :00, :05, :10 ... 15 minutes closes at :00,
/// :15, :30, :45 and one hour closes on the hour.
enum PredictionHorizon { m5, m15, h1 }

extension PredictionHorizonInfo on PredictionHorizon {
  Duration get duration => switch (this) {
        PredictionHorizon.m5 => const Duration(minutes: 5),
        PredictionHorizon.m15 => const Duration(minutes: 15),
        PredictionHorizon.h1 => const Duration(hours: 1),
      };

  int get totalSeconds => duration.inSeconds;

  /// Minutes of the clock bucket the round snaps to.
  int get bucketMinutes => switch (this) {
        PredictionHorizon.m5 => 5,
        PredictionHorizon.m15 => 15,
        PredictionHorizon.h1 => 60,
      };

  /// Short tag for buttons. Always one line.
  String get tag => switch (this) {
        PredictionHorizon.m5 => '5 min',
        PredictionHorizon.m15 => '15 min',
        PredictionHorizon.h1 => '1 hora',
      };

  String get title => switch (this) {
        PredictionHorizon.m5 => 'Ronda de 5 minutos',
        PredictionHorizon.m15 => 'Ronda de 15 minutos',
        PredictionHorizon.h1 => 'Ronda de 1 hora',
      };

  /// Candle interval the agents read to build the signal.
  String get baseInterval => switch (this) {
        PredictionHorizon.m5 => '1m',
        PredictionHorizon.m15 => '1m',
        PredictionHorizon.h1 => '5m',
      };

  /// Minutes covered by one base candle.
  double get baseMinutes => switch (this) {
        PredictionHorizon.m5 => 1,
        PredictionHorizon.m15 => 1,
        PredictionHorizon.h1 => 5,
      };

  /// Wider interval used to read the bigger picture.
  String get contextInterval => switch (this) {
        PredictionHorizon.m5 => '15m',
        PredictionHorizon.m15 => '1h',
        PredictionHorizon.h1 => '4h',
      };

  /// Interval whose closed candle settles the round.
  String get settlementInterval => switch (this) {
        PredictionHorizon.m5 => '5m',
        PredictionHorizon.m15 => '15m',
        PredictionHorizon.h1 => '1h',
      };

  /// Every interval the app needs to serve the three horizons.
  static const List<String> allIntervals = ['1m', '5m', '15m', '1h', '4h'];
}
