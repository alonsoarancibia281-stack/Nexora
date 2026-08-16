import 'prediction_horizon.dart';
import 'prediction_outlook.dart';
import 'round_clock.dart';

/// How one closed round ended.
class RoundResult {
  const RoundResult({
    required this.horizon,
    required this.window,
    required this.call,
    required this.probability,
    required this.startPrice,
    required this.endPrice,
  });

  final PredictionHorizon horizon;
  final RoundWindow window;
  final PredictionCall call;

  /// Chance the desk gave to its own call.
  final double probability;

  final double startPrice;
  final double endPrice;

  bool get closedUp => endPrice > startPrice;

  double get changePercent =>
      startPrice <= 0 ? 0 : (endPrice - startPrice) / startPrice * 100;

  bool get isCall => call.isDirectional;

  bool get isHit => isCall && (call == PredictionCall.up) == closedUp;
}

/// Keeps the closed rounds so the app can show an honest hit count.
class RoundJournal {
  RoundJournal({this.maxResults = 200});

  final int maxResults;
  final List<RoundResult> _results = <RoundResult>[];

  /// Newest first.
  List<RoundResult> get results => List.unmodifiable(_results);

  List<RoundResult> forHorizon(PredictionHorizon horizon) => _results
      .where((result) => result.horizon == horizon)
      .toList(growable: false);

  void add(RoundResult result) {
    _results.insert(0, result);
    if (_results.length > maxResults) {
      _results.removeRange(maxResults, _results.length);
    }
  }

  /// Hits and calls made on a horizon. Rounds without a call are ignored.
  ({int hits, int calls}) scoreFor(PredictionHorizon horizon) {
    var hits = 0;
    var calls = 0;
    for (final result in forHorizon(horizon)) {
      if (!result.isCall) continue;
      calls++;
      if (result.isHit) hits++;
    }
    return (hits: hits, calls: calls);
  }

  /// Null while the horizon has no closed call yet.
  double? accuracyFor(PredictionHorizon horizon) {
    final score = scoreFor(horizon);
    return score.calls == 0 ? null : score.hits / score.calls;
  }
}
