import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/simulator/domain/simulated_trade.dart';
import 'package:nexora_markets_ai/features/simulator/domain/simulator_engine.dart';

void main() {
  const engine = SimulatorEngine();

  test('long trade calculates gross and net pnl including fees', () {
    final result = engine.calculate(
      side: SimulatedTradeSide.long,
      entryPrice: 100,
      exitPrice: 110,
      quantity: 2,
      feeRatePercent: 0.1,
    );

    expect(result.grossPnl, 20);
    expect(result.fees, closeTo(0.42, 0.0001));
    expect(result.netPnl, closeTo(19.58, 0.0001));
    expect(result.returnPercent, closeTo(9.79, 0.0001));
    expect(result.isProfit, isTrue);
  });

  test('short trade profits when exit is below entry', () {
    final result = engine.calculate(
      side: SimulatedTradeSide.short,
      entryPrice: 100,
      exitPrice: 90,
      quantity: 1,
      feeRatePercent: 0,
    );

    expect(result.grossPnl, 10);
    expect(result.netPnl, 10);
    expect(result.returnPercent, 10);
  });

  test('rejects invalid prices and quantity', () {
    expect(
      () => engine.calculate(
        side: SimulatedTradeSide.long,
        entryPrice: 0,
        exitPrice: 100,
        quantity: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => engine.calculate(
        side: SimulatedTradeSide.long,
        entryPrice: 100,
        exitPrice: 110,
        quantity: 0,
      ),
      throwsArgumentError,
    );
  });
}
