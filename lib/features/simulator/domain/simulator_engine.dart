import 'simulated_trade.dart';

class SimulatorEngine {
  const SimulatorEngine();

  SimulatedTradeResult calculate({
    required SimulatedTradeSide side,
    required double entryPrice,
    required double exitPrice,
    required double quantity,
    double feeRatePercent = 0.1,
  }) {
    if (entryPrice <= 0 || exitPrice <= 0) {
      throw ArgumentError('Los precios deben ser mayores que cero.');
    }
    if (quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero.');
    }
    if (feeRatePercent < 0) {
      throw ArgumentError('La comisión no puede ser negativa.');
    }

    final direction = side == SimulatedTradeSide.long ? 1.0 : -1.0;
    final grossPnl = (exitPrice - entryPrice) * quantity * direction;
    final entryNotional = entryPrice * quantity;
    final exitNotional = exitPrice * quantity;
    final feeRate = feeRatePercent / 100;
    final fees = (entryNotional + exitNotional) * feeRate;
    final netPnl = grossPnl - fees;
    final returnPercent = entryNotional == 0 ? 0.0 : (netPnl / entryNotional) * 100;

    return SimulatedTradeResult(
      side: side,
      entryPrice: entryPrice,
      exitPrice: exitPrice,
      quantity: quantity,
      grossPnl: grossPnl,
      fees: fees,
      netPnl: netPnl,
      returnPercent: returnPercent,
    );
  }
}
