class SymbolTradingRules {
  const SymbolTradingRules({
    required this.symbol,
    required this.tickSize,
    required this.quantityStep,
    required this.minimumQuantity,
    required this.minimumNotional,
  });

  final String symbol;
  final double tickSize;
  final double quantityStep;
  final double minimumQuantity;
  final double minimumNotional;
}
