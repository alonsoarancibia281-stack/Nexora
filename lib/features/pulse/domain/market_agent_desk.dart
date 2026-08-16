import 'dart:math' as math;

import 'agent_scoreboard.dart';
import 'market_agent.dart';
import 'market_knowledge_framework.dart';
import 'market_reading.dart';
import 'prediction_horizon.dart';
import 'prediction_outlook.dart';
import 'round_clock.dart';

/// Runs the six agents and turns their views into one decision.
///
/// The desk never averages blindly: every view weighs by how much the agent
/// knows about this horizon, how sure it is, how deep the market is and how
/// well that agent has been reading this horizon so far.
class MarketAgentDesk {
  const MarketAgentDesk({
    this.agents = coreAgents,
    this.knowledge = const MarketKnowledgeFramework(),
  });

  final List<MarketAgent> agents;
  final MarketKnowledgeFramework knowledge;

  /// A call needs this much of an edge before the desk names a side.
  static const callThreshold = .055;

  PredictionOutlook review({
    required MarketReading reading,
    required RoundWindow window,
    required DateTime now,
    AgentScoreboard scoreboard = const AgentScoreboard(),
  }) {
    final views = agents
        .map((agent) => agent.review(reading))
        .toList(growable: false);

    var weighted = 0.0;
    var weightTotal = 0.0;
    for (final view in views) {
      final weight =
          view.weight * scoreboard.reliabilityOf(reading.horizon, view.id);
      weighted += view.probabilityUp * weight;
      weightTotal += weight;
    }
    var probabilityUp = weightTotal <= 0 ? .5 : weighted / weightTotal;

    // How far apart the desk is.
    var spread = 0.0;
    if (weightTotal > 0) {
      for (final view in views) {
        final weight =
            view.weight * scoreboard.reliabilityOf(reading.horizon, view.id);
        spread += weight * math.pow(view.probabilityUp - probabilityUp, 2);
      }
      spread = math.sqrt(spread / weightTotal);
    }
    final disagreement = (spread * 2.4).clamp(0.0, 1.0).toDouble();

    // Weighted share of the desk on the leading side.
    final leaningUp = probabilityUp >= .5;
    var backing = 0.0;
    for (final view in views) {
      if (view.saysUp == leaningUp) backing += view.weight;
    }
    final totalWeight =
        views.fold<double>(0, (sum, view) => sum + view.weight);
    final agreement =
        totalWeight <= 0 ? 0.0 : (backing / totalWeight).clamp(0.0, 1.0);

    final coverage =
        (totalWeight / views.length).clamp(0.0, 1.0).toDouble();
    final knowledgeFactor = knowledge.confidenceMultiplier(
      instability: reading.instability / 100,
      analystAgreement: agreement.toDouble(),
      statisticalEdge: ((probabilityUp - .5).abs() * 2).clamp(0.0, 1.0),
      baselineAdvantage: coverage,
      robustness: 1 - disagreement,
    );

    final stabilityShrink =
        (1 - reading.instability / 100 * .55).clamp(.35, 1.0).toDouble();
    final shrink = stabilityShrink * (.55 + .45 * knowledgeFactor);
    probabilityUp = .5 + (probabilityUp - .5) * shrink;

    final ceiling = switch (reading.horizon) {
      PredictionHorizon.m5 => .90,
      PredictionHorizon.m15 => .88,
      PredictionHorizon.h1 => .85,
    };
    probabilityUp = probabilityUp.clamp(1 - ceiling, ceiling).toDouble();

    final edge = probabilityUp - .5;
    final enoughAgreement = agreement >= .55;
    final enoughCoverage = coverage >= .06;
    final call = !enoughAgreement || !enoughCoverage || edge.abs() < callThreshold
        ? PredictionCall.wait
        : edge > 0
            ? PredictionCall.up
            : PredictionCall.down;

    return PredictionOutlook(
      horizon: reading.horizon,
      window: window,
      call: call,
      probabilityUp: probabilityUp,
      agreement: agreement.toDouble(),
      views: views,
      price: reading.price,
      startPrice: reading.startPrice,
      distancePercent: reading.roundDistancePercent,
      expectedMovePercent: reading.expectedMovePercent,
      instability: reading.instability,
      secondsLeft: reading.secondsLeft,
      updatedAt: now,
      reasons: _reasons(reading, views, call, agreement.toDouble()),
    );
  }

  List<String> _reasons(
    MarketReading reading,
    List<AgentView> views,
    PredictionCall call,
    double agreement,
  ) {
    final leaders = [...views]
      ..sort((a, b) => b.weight.compareTo(a.weight));
    final reasons = <String>[];
    for (final view in leaders.take(3)) {
      if (view.weight < .04) continue;
      reasons.add('${view.name}: ${view.note}');
    }
    reasons.add(
      'De acuerdo ${(agreement * 100).round()}% del equipo.',
    );
    if (call == PredictionCall.wait) {
      reasons.add('El equipo no ve ventaja clara. Mejor espera.');
    }
    return reasons;
  }
}
