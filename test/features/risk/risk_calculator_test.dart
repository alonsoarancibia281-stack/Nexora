import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/risk/domain/risk_calculator.dart';

void main() {
  const calculator = RiskCalculator();

  test('calculates position size from max risk', () {
    final plan = calculator.calculate(
      capital: 1000,
      riskPercent: 1,
      entryPrice: 100,
      stopLossPrice: 95,
      takeProfitPrice: 110,
    );

    expect(plan.maxLoss, 10);
    expect(plan.riskPerUnit, 5);
    expect(plan.positionUnits, 2);
    expect(plan.positionValue, 200);
    expect(plan.riskRewardRatio, 2);
  });

  test('rejects invalid risk parameters', () {
    expect(
      () => calculator.calculate(
        capital: 1000,
        riskPercent: 0,
        entryPrice: 100,
        stopLossPrice: 95,
        takeProfitPrice: 110,
      ),
      throwsArgumentError,
    );
  });
}
