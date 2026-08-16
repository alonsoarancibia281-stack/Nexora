import 'market_agent.dart';
import 'prediction_horizon.dart';
import 'round_clock.dart';

/// What the desk decides for a round.
enum PredictionCall { up, down, wait }

extension PredictionCallInfo on PredictionCall {
  String get label => switch (this) {
        PredictionCall.up => 'SUBE',
        PredictionCall.down => 'BAJA',
        PredictionCall.wait => 'ESPERA',
      };

  String get sentence => switch (this) {
        PredictionCall.up => 'El mercado sube',
        PredictionCall.down => 'El mercado baja',
        PredictionCall.wait => 'El mercado no decide',
      };

  bool get isDirectional => this != PredictionCall.wait;

  PredictionCall get opposite => switch (this) {
        PredictionCall.up => PredictionCall.down,
        PredictionCall.down => PredictionCall.up,
        PredictionCall.wait => PredictionCall.wait,
      };
}

/// The final reading for one round.
class PredictionOutlook {
  const PredictionOutlook({
    required this.horizon,
    required this.window,
    required this.call,
    required this.probabilityUp,
    required this.agreement,
    required this.views,
    required this.price,
    required this.startPrice,
    required this.distancePercent,
    required this.expectedMovePercent,
    required this.instability,
    required this.secondsLeft,
    required this.updatedAt,
    required this.reasons,
    this.lockedAt,
    this.secondOpinion,
  });

  final PredictionHorizon horizon;
  final RoundWindow window;
  final PredictionCall call;

  /// Chance the round closes above its open, from 0 to 1.
  final double probabilityUp;

  /// Share of the desk that backs the call, from 0 to 1.
  final double agreement;

  final List<AgentView> views;
  final double price;
  final double startPrice;
  final double distancePercent;
  final double expectedMovePercent;
  final double instability;
  final int secondsLeft;
  final DateTime updatedAt;
  final List<String> reasons;

  /// Exact time the call became firm.
  final DateTime? lockedAt;

  /// Short note from the outside model, when it answers.
  final String? secondOpinion;

  /// Chance of the side the desk picks, from 0 to 1.
  double get probability => switch (call) {
        PredictionCall.up => probabilityUp,
        PredictionCall.down => 1 - probabilityUp,
        PredictionCall.wait =>
          probabilityUp >= .5 ? probabilityUp : 1 - probabilityUp,
      };

  /// Same number as a percent, ready to print.
  double get confidence => probability * 100;

  bool get isCalm => instability < 40;

  /// Agents that back the call right now.
  List<AgentView> get supporters => views
      .where((view) =>
          view.relevance > .05 &&
          ((call == PredictionCall.up && view.saysUp) ||
              (call == PredictionCall.down && !view.saysUp)))
      .toList(growable: false);

  /// Agents that read the opposite side.
  List<AgentView> get objectors => views
      .where((view) =>
          view.relevance > .05 &&
          ((call == PredictionCall.up && !view.saysUp) ||
              (call == PredictionCall.down && view.saysUp)))
      .toList(growable: false);

  List<String> get warnings => views
      .map((view) => view.warning)
      .whereType<String>()
      .toSet()
      .toList(growable: false);

  PredictionOutlook copyWith({
    DateTime? lockedAt,
    String? secondOpinion,
  }) =>
      PredictionOutlook(
        horizon: horizon,
        window: window,
        call: call,
        probabilityUp: probabilityUp,
        agreement: agreement,
        views: views,
        price: price,
        startPrice: startPrice,
        distancePercent: distancePercent,
        expectedMovePercent: expectedMovePercent,
        instability: instability,
        secondsLeft: secondsLeft,
        updatedAt: updatedAt,
        reasons: reasons,
        lockedAt: lockedAt ?? this.lockedAt,
        secondOpinion: secondOpinion ?? this.secondOpinion,
      );
}
