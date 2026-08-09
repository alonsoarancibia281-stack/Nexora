import 'dart:convert';

import 'order_book_snapshot.dart';

class OrderBookParser {
  const OrderBookParser();

  OrderBookSnapshot parse(String input, {String defaultSymbol = 'BTCUSDT'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Pega un snapshot del libro de ordenes.');
    }

    if (trimmed.startsWith('{')) {
      return _parseJson(trimmed, defaultSymbol);
    }
    return _parseNexoraText(trimmed, defaultSymbol);
  }

  OrderBookSnapshot _parseJson(String input, String defaultSymbol) {
    final json = jsonDecode(input);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('El JSON debe contener bids y asks.');
    }
    final bids = _levels(json['bids'] ?? json['b']);
    final asks = _levels(json['asks'] ?? json['a']);
    return _snapshot(
      '${json['symbol'] ?? json['s'] ?? defaultSymbol}',
      bids,
      asks,
    );
  }

  OrderBookSnapshot _parseNexoraText(String input, String defaultSymbol) {
    final bids = <OrderBookLevel>[];
    final asks = <OrderBookLevel>[];
    var symbol = defaultSymbol;
    List<OrderBookLevel>? target;

    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line == 'NEXORA_ORDER_BOOK_V1') continue;
      final upper = line.toUpperCase();
      if (upper.startsWith('PAR ')) {
        symbol = line.substring(4).trim();
        continue;
      }
      if (upper == 'VENTAS' || upper == 'ASKS') {
        target = asks;
        continue;
      }
      if (upper == 'COMPRAS' || upper == 'BIDS') {
        target = bids;
        continue;
      }
      if (target == null) continue;

      final values = line.split(RegExp(r'[\s;|]+'));
      if (values.length < 2) continue;
      final price = _number(values[0]);
      final quantity = _number(values[1]);
      if (price != null && quantity != null && price > 0 && quantity > 0) {
        target.add(OrderBookLevel(price: price, quantity: quantity));
      }
    }
    return _snapshot(symbol, bids, asks);
  }

  List<OrderBookLevel> _levels(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<List>()
        .map((row) {
          if (row.length < 2) return null;
          final price = _number('${row[0]}');
          final quantity = _number('${row[1]}');
          if (price == null ||
              quantity == null ||
              price <= 0 ||
              quantity <= 0) {
            return null;
          }
          return OrderBookLevel(price: price, quantity: quantity);
        })
        .whereType<OrderBookLevel>()
        .toList();
  }

  double? _number(String value) {
    final normalized = value.contains('.')
        ? value.replaceAll(',', '')
        : value.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  OrderBookSnapshot _snapshot(
    String symbol,
    List<OrderBookLevel> bids,
    List<OrderBookLevel> asks,
  ) {
    if (bids.isEmpty || asks.isEmpty) {
      throw const FormatException(
        'El snapshot necesita secciones COMPRAS y VENTAS con precio y cantidad.',
      );
    }
    bids.sort((a, b) => b.price.compareTo(a.price));
    asks.sort((a, b) => a.price.compareTo(b.price));
    if (bids.first.price >= asks.first.price) {
      throw const FormatException(
        'El mejor precio de compra debe ser menor al mejor precio de venta.',
      );
    }
    return OrderBookSnapshot(
      symbol: symbol.trim().toUpperCase(),
      bids: List.unmodifiable(bids),
      asks: List.unmodifiable(asks),
      capturedAt: DateTime.now(),
    );
  }
}
