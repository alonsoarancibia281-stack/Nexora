import 'market_agent.dart';
import 'prediction_horizon.dart';

/// Track record of one agent on one horizon.
class AgentRecord {
  const AgentRecord({this.calls = 0, this.hits = 0});

  final int calls;
  final int hits;

  double get hitRate => calls == 0 ? .5 : hits / calls;

  /// Hit rate pulled toward 50% while the sample is small, so ten lucky
  /// rounds never turn an agent into an oracle.
  double get shrunkHitRate => (hits + 6 * .5) / (calls + 6);

  /// Multiplier applied to the agent vote.
  double get reliability => (.5 + shrunkHitRate).clamp(.65, 1.35).toDouble();

  AgentRecord settle(bool hit) =>
      AgentRecord(calls: calls + 1, hits: hits + (hit ? 1 : 0));
}

/// Keeps score of every agent, per horizon.
///
/// The agents keep working while the app is open: each closed round tells them
/// whether they read the market right, and the next vote weighs them by that.
class AgentScoreboard {
  const AgentScoreboard([this.records = const {}]);

  /// Key is `horizon.name/agentId`.
  final Map<String, AgentRecord> records;

  static String keyOf(PredictionHorizon horizon, String agentId) =>
      '${horizon.name}/$agentId';

  AgentRecord recordOf(PredictionHorizon horizon, String agentId) =>
      records[keyOf(horizon, agentId)] ?? const AgentRecord();

  double reliabilityOf(PredictionHorizon horizon, String agentId) =>
      recordOf(horizon, agentId).reliability;

  int samplesOf(PredictionHorizon horizon) => records.entries
      .where((entry) => entry.key.startsWith('${horizon.name}/'))
      .fold<int>(0, (total, entry) => total + entry.value.calls);

  /// Returns a new scoreboard with the closed round applied.
  ///
  /// Only agents that actually took a side are graded.
  AgentScoreboard settle({
    required PredictionHorizon horizon,
    required List<AgentView> views,
    required bool closedUp,
  }) {
    final next = Map<String, AgentRecord>.of(records);
    for (final view in views) {
      if (view.conviction < .04 || view.relevance < .05) continue;
      final key = keyOf(horizon, view.id);
      final current = next[key] ?? const AgentRecord();
      next[key] = current.settle(view.saysUp == closedUp);
    }
    return AgentScoreboard(Map.unmodifiable(next));
  }
}
