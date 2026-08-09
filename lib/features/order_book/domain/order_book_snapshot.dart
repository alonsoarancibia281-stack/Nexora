class OrderBookLevel {
  const OrderBookLevel({required this.price, required this.quantity});

  final double price;
  final double quantity;
}

class OrderBookSnapshot {
  const OrderBookSnapshot({
    required this.symbol,
    required this.bids,
    required this.asks,
    required this.capturedAt,
  });

  final String symbol;
  final List<OrderBookLevel> bids;
  final List<OrderBookLevel> asks;
  final DateTime capturedAt;

  double get bestBid => bids.isEmpty ? 0 : bids.first.price;
  double get bestAsk => asks.isEmpty ? 0 : asks.first.price;
  double get midpoint =>
      bestBid > 0 && bestAsk > 0 ? (bestBid + bestAsk) / 2 : 0;

  String toClipboardText({int levels = 10}) {
    final buffer = StringBuffer()
      ..writeln('NEXORA_ORDER_BOOK_V1')
      ..writeln('PAR $symbol')
      ..writeln('VENTAS');
    for (final level in asks.take(levels)) {
      buffer.writeln('${level.price} ${level.quantity}');
    }
    buffer.writeln('COMPRAS');
    for (final level in bids.take(levels)) {
      buffer.writeln('${level.price} ${level.quantity}');
    }
    return buffer.toString().trimRight();
  }
}
