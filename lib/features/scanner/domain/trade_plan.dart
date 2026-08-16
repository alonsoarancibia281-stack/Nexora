import '../../risk/domain/risk_calculator.dart';
import 'scan_candidate.dart';
import 'setup_strategy.dart';

/// The plan for one idea: where you get in, where you get out if it goes
/// wrong, where it can reach, and how much to put in.
///
/// Nexora never sends this to an exchange. You place the order yourself.
class TradePlan {
  const TradePlan({
    required this.symbol,
    required this.pair,
    required this.strategyId,
    required this.strategyName,
    required this.levels,
    required this.capital,
    required this.riskPercent,
    required this.units,
    required this.positionValue,
    required this.maxLoss,
    required this.possibleGain,
    required this.hitRate,
    required this.trades,
  });

  final String symbol;
  final String pair;
  final String strategyId;
  final String strategyName;
  final TradeLevels levels;

  /// Money you trade with.
  final double capital;

  /// Share of the capital you accept losing on this idea.
  final double riskPercent;

  /// How much of the coin to buy.
  final double units;

  /// What the position costs.
  final double positionValue;

  /// What you lose if the stop hits.
  final double maxLoss;

  /// What you make if the target hits.
  final double possibleGain;

  /// How often this rule worked on this asset's history, from 0 to 1.
  final double hitRate;

  /// How many past trades that number comes from.
  final int trades;

  double get riskReward => levels.riskReward;

  /// The plan as plain text, ready to paste into the exchange.
  String toClipboardText() => [
        'Nexora · $pair · $strategyName',
        'Entrada ${levels.entry}',
        'Stop ${levels.stop}',
        'Objetivo ${levels.target}',
        'Cantidad $units',
        'Riesgo máximo $maxLoss USDT',
        'Nexora no ejecuta órdenes. Revisa el mercado antes de entrar.',
      ].join('\n');
}

/// Turns a rule's levels into a position you can actually place.
class TradePlanner {
  const TradePlanner({this.calculator = const RiskCalculator()});

  final RiskCalculator calculator;

  /// Returns null when the numbers do not make a valid position.
  TradePlan? build({
    required ScanCandidate candidate,
    required StrategyReport report,
    required double capital,
    required double riskPercent,
  }) {
    final levels = report.live;
    if (levels == null) return null;
    if (capital <= 0 || riskPercent <= 0 || riskPercent > 100) return null;
    if (levels.riskPerUnit <= 0) return null;

    final RiskPlan plan;
    try {
      plan = calculator.calculate(
        capital: capital,
        riskPercent: riskPercent,
        entryPrice: levels.entry,
        stopLossPrice: levels.stop,
        takeProfitPrice: levels.target,
      );
    } on ArgumentError {
      return null;
    }

    return TradePlan(
      symbol: candidate.symbol,
      pair: candidate.pair,
      strategyId: report.strategy.id,
      strategyName: report.strategy.name,
      levels: levels,
      capital: capital,
      riskPercent: riskPercent,
      units: plan.positionUnits,
      positionValue: plan.positionValue,
      maxLoss: plan.maxLoss,
      possibleGain: plan.rewardPerUnit * plan.positionUnits,
      hitRate: report.record.hitRate,
      trades: report.record.trades,
    );
  }
}
