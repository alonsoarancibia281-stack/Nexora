enum SimulatedTradeSide { long, short }

class SimulatedTradeResult {
  const SimulatedTradeResult({
    required this.side,
    required this.entryPrice,
    required this.exitPrice,
    required this.quantity,
    required this.grossPnl,
    required this.fees,
    required this.netPnl,
    required this.returnPercent,
  });

  final SimulatedTradeSide side;
  final double entryPrice;
  final double exitPrice;
  final double quantity;
  final double grossPnl;
  final double fees;
  final double netPnl;
  final double returnPercent;

  bool get isProfit => netPnl > 0;
  bool get isLoss => netPnl < 0;
}
