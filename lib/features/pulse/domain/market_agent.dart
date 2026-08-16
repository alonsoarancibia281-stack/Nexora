import 'dart:math' as math;

import 'market_reading.dart';
import 'prediction_horizon.dart';

/// What an agent thinks right now.
class AgentView {
  const AgentView({
    required this.id,
    required this.name,
    required this.focus,
    required this.probabilityUp,
    required this.relevance,
    required this.note,
    this.warning,
  });

  final String id;
  final String name;
  final String focus;

  /// Chance the round closes up, from 0 to 1.
  final double probabilityUp;

  /// How much this agent matters right now, from 0 to 1.
  final double relevance;

  /// One short line, always in present tense.
  final String note;

  /// Set when the agent sees a reason to be careful.
  final String? warning;

  bool get saysUp => probabilityUp >= .5;

  /// Distance from a coin flip, from 0 to 1.
  double get conviction => ((probabilityUp - .5).abs() * 2).clamp(0.0, 1.0);

  /// Weight this view carries in the desk vote.
  double get weight => relevance * (.35 + conviction * .65);
}

/// Raw output of an agent before it becomes a probability.
class AgentSignal {
  const AgentSignal({
    required this.edge,
    required this.relevance,
    required this.note,
    this.warning,
  });

  /// -1 fully down, +1 fully up.
  final double edge;
  final double relevance;
  final String note;
  final String? warning;
}

/// A small always-on analyst.
///
/// Each agent owns one job, carries its own market knowledge and reviews the
/// market on every refresh. Six agents cover the work that a hundred copies of
/// the same rule used to do, and every one of them can be read in a line.
abstract class MarketAgent {
  const MarketAgent();

  String get id;
  String get name;
  String get focus;

  /// How much this agent knows about each horizon.
  double horizonWeight(PredictionHorizon horizon);

  AgentSignal read(MarketReading reading);

  AgentView review(MarketReading reading) {
    final signal = read(reading);
    final edge = signal.edge.clamp(-1.0, 1.0).toDouble();
    final temperature = _temperature(reading);
    final probability = 1 / (1 + math.exp(-edge / temperature));
    final relevance =
        (signal.relevance * horizonWeight(reading.horizon)).clamp(0.0, 1.0);
    return AgentView(
      id: id,
      name: name,
      focus: focus,
      probabilityUp: probability.clamp(.02, .98).toDouble(),
      relevance: relevance.toDouble(),
      note: signal.note,
      warning: signal.warning,
    );
  }

  /// A wild market flattens every opinion.
  double _temperature(MarketReading reading) {
    final base = switch (reading.horizon) {
      PredictionHorizon.m5 => .30,
      PredictionHorizon.m15 => .34,
      PredictionHorizon.h1 => .40,
    };
    return base + reading.instability / 100 * .22;
  }

  static String direction(double edge, String up, String down, String flat) {
    if (edge > .12) return up;
    if (edge < -.12) return down;
    return flat;
  }
}

/// Reads where the market walks.
///
/// Knowledge: a trend only counts when the wider picture points the same way,
/// and a squeezed range is not a trend.
class TrendAgent extends MarketAgent {
  const TrendAgent();

  @override
  String get id => 'trend';

  @override
  String get name => 'Tendencia';

  @override
  String get focus => 'sigue el camino del precio';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => .75,
        PredictionHorizon.m15 => .95,
        PredictionHorizon.h1 => 1.0,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final edge = reading.trend * .42 +
        reading.contextTrend * .33 +
        reading.slope * .25;
    final aligned = reading.trend.sign == reading.contextTrend.sign ||
        reading.contextTrend.abs() < .12;
    final squeezed = reading.atrPercent < .05;
    var relevance = edge.abs() * (aligned ? 1.0 : .55);
    if (squeezed) relevance *= .6;
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'El precio sube y el marco largo acompaña.',
        'El precio baja y el marco largo acompaña.',
        'El precio anda de lado.',
      ),
      warning: aligned
          ? (squeezed ? 'El rango se cierra y la señal pierde fuerza.' : null)
          : 'La tendencia corta pelea con la larga.',
    );
  }
}

/// Reads how fast the market moves.
///
/// Knowledge: a push with no volume behind it tends to stall halfway.
class MomentumAgent extends MarketAgent {
  const MomentumAgent();

  @override
  String get id => 'momentum';

  @override
  String get name => 'Impulso';

  @override
  String get focus => 'mide la fuerza del movimiento';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => 1.0,
        PredictionHorizon.m15 => .9,
        PredictionHorizon.h1 => .65,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final edge = reading.momentum * .48 +
        reading.acceleration * .27 +
        reading.bodyPressure * .25;
    final thinVolume = reading.volumeRatio < .8;
    var relevance = edge.abs();
    if (thinVolume) relevance *= .6;
    if (reading.persistence.sign == edge.sign) relevance *= 1.15;
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'La fuerza empuja hacia arriba.',
        'La fuerza empuja hacia abajo.',
        'La fuerza está repartida.',
      ),
      warning: thinVolume ? 'El empuje llega con poco volumen.' : null,
    );
  }
}

/// Reads who hits first: buyers or sellers.
///
/// Knowledge: aggressive flow rules the short term and fades fast, and it
/// stops being reliable once the spread widens.
class FlowAgent extends MarketAgent {
  const FlowAgent();

  @override
  String get id => 'flow';

  @override
  String get name => 'Flujo';

  @override
  String get focus => 'mira quién ataca el precio';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => 1.0,
        PredictionHorizon.m15 => .7,
        PredictionHorizon.h1 => .4,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final edge = reading.flowImbalance * .44 +
        reading.signedVolume * .24 +
        reading.flowAcceleration * reading.flowImbalance.sign * .14 +
        reading.priceImpulse * .18;
    final wideSpread = reading.spreadBps > 4;
    var relevance = edge.abs() * (wideSpread ? .5 : 1.0);
    relevance *= (.5 + reading.liquidityQuality * .5);
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'Los compradores golpean más.',
        'Los vendedores golpean más.',
        'Compras y ventas van parejas.',
      ),
      warning: wideSpread ? 'El spread se abre y el flujo miente.' : null,
    );
  }
}

/// Reads where the resting money sits.
///
/// Knowledge: a lopsided book pushes price, but only when there is real depth
/// behind it.
class LiquidityAgent extends MarketAgent {
  const LiquidityAgent();

  @override
  String get id => 'liquidity';

  @override
  String get name => 'Liquidez';

  @override
  String get focus => 'pesa el libro de órdenes';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => 1.0,
        PredictionHorizon.m15 => .6,
        PredictionHorizon.h1 => .3,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final edge = reading.bookImbalance * .58 + reading.micropriceEdge * .42;
    final relevance = edge.abs() * reading.liquidityQuality;
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'Hay más dinero esperando en compras.',
        'Hay más dinero esperando en ventas.',
        'El libro está equilibrado.',
      ),
      warning: reading.liquidityQuality < .35
          ? 'El libro está fino y se mueve solo.'
          : null,
    );
  }
}

/// Reads whether the move already made survives until the close.
///
/// Knowledge: early in the round almost anything still fits; near the end the
/// distance already travelled matters more than any indicator.
class VolatilityAgent extends MarketAgent {
  const VolatilityAgent();

  @override
  String get id => 'volatility';

  @override
  String get name => 'Volatilidad';

  @override
  String get focus => 'calcula lo que falta por recorrer';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => 1.0,
        PredictionHorizon.m15 => .95,
        PredictionHorizon.h1 => .9,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final edge = (reading.roundEdge.clamp(-1.0, 1.0) * .58 +
            reading.rangeExpansion * reading.roundEdge.sign * .18 +
            reading.priceImpulse * .24)
        .toDouble();
    // Al final de la ronda, la ventaja ya lograda es casi todo.
    final relevance =
        (edge.abs() * (.35 + reading.elapsed * .85)).clamp(0.0, 1.0).toDouble();
    final wideOpen = reading.roundEdge.abs() < .5 && reading.elapsed < .6;
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'La ronda ya gana terreno arriba.',
        'La ronda ya pierde terreno abajo.',
        'La ronda sigue pegada a su apertura.',
      ),
      warning: wideOpen ? 'Todavía cabe un giro completo.' : null,
    );
  }
}

/// Reads when the move stretches too far.
///
/// Knowledge: never fight a strong move backed by volume; only speak up when
/// price stretches while the push fades.
class ReversionAgent extends MarketAgent {
  const ReversionAgent();

  @override
  String get id => 'reversion';

  @override
  String get name => 'Reversión';

  @override
  String get focus => 'avisa cuando el precio se estira';

  @override
  double horizonWeight(PredictionHorizon horizon) => switch (horizon) {
        PredictionHorizon.m5 => .8,
        PredictionHorizon.m15 => .85,
        PredictionHorizon.h1 => .9,
      };

  @override
  AgentSignal read(MarketReading reading) {
    final rsiEdge = ((reading.rsi - 50) / 50).clamp(-1.0, 1.0).toDouble();
    final stretch = reading.zPrice * .38 +
        reading.rangePosition * .22 +
        rsiEdge * .22 +
        reading.vwapDistance * .18;
    final edge = -stretch;
    final strongTrend = reading.trend.abs() > .45 &&
        reading.momentum.sign == reading.trend.sign &&
        reading.volumeRatio > 1.15;
    var relevance = edge.abs() * (.45 + reading.wickNoise * .55);
    // No pelea contra un impulso sano.
    if (strongTrend) relevance *= .3;
    return AgentSignal(
      edge: edge,
      relevance: relevance,
      note: MarketAgent.direction(
        edge,
        'El precio se estira abajo y busca aire.',
        'El precio se estira arriba y busca aire.',
        'El precio está en su sitio.',
      ),
      warning: strongTrend ? 'El impulso manda; no toca girar todavía.' : null,
    );
  }
}

/// The staff Nexora keeps: six agents, one job each.
const List<MarketAgent> coreAgents = <MarketAgent>[
  TrendAgent(),
  MomentumAgent(),
  FlowAgent(),
  LiquidityAgent(),
  VolatilityAgent(),
  ReversionAgent(),
];
