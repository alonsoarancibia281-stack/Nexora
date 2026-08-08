class RiskPlan {
  const RiskPlan({
    required this.capital,
    required this.riskPercent,
    required this.entryPrice,
    required this.stopLossPrice,
    required this.takeProfitPrice,
    required this.maxLoss,
    required this.riskPerUnit,
    required this.positionUnits,
    required this.positionValue,
    required this.rewardPerUnit,
    required this.riskRewardRatio,
  });

  final double capital;
  final double riskPercent;
  final double entryPrice;
  final double stopLossPrice;
  final double takeProfitPrice;
  final double maxLoss;
  final double riskPerUnit;
  final double positionUnits;
  final double positionValue;
  final double rewardPerUnit;
  final double riskRewardRatio;
}

class RiskCalculator {
  const RiskCalculator();

  RiskPlan calculate({
    required double capital,
    required double riskPercent,
    required double entryPrice,
    required double stopLossPrice,
    required double takeProfitPrice,
  }) {
    if (capital <= 0) throw ArgumentError('El capital debe ser mayor que cero.');
    if (riskPercent <= 0 || riskPercent > 100) {
      throw ArgumentError('El riesgo debe estar entre 0 y 100%.');
    }
    if (entryPrice <= 0 || stopLossPrice <= 0 || takeProfitPrice <= 0) {
      throw ArgumentError('Los precios deben ser mayores que cero.');
    }
    if (entryPrice == stopLossPrice) {
      throw ArgumentError('La entrada y el stop loss no pueden ser iguales.');
    }

    final maxLoss = capital * (riskPercent / 100);
    final riskPerUnit = (entryPrice - stopLossPrice).abs();
    final positionUnits = maxLoss / riskPerUnit;
    final positionValue = positionUnits * entryPrice;
    final rewardPerUnit = (takeProfitPrice - entryPrice).abs();
    final riskRewardRatio = rewardPerUnit / riskPerUnit;

    return RiskPlan(
      capital: capital,
      riskPercent: riskPercent,
      entryPrice: entryPrice,
      stopLossPrice: stopLossPrice,
      takeProfitPrice: takeProfitPrice,
      maxLoss: maxLoss,
      riskPerUnit: riskPerUnit,
      positionUnits: positionUnits,
      positionValue: positionValue,
      rewardPerUnit: rewardPerUnit,
      riskRewardRatio: riskRewardRatio,
    );
  }
}
