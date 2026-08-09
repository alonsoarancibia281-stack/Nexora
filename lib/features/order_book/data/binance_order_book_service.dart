import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../domain/order_book_parser.dart';
import '../domain/order_book_snapshot.dart';

class BinanceOrderBookService {
  const BinanceOrderBookService();

  static const _ws = 'wss://stream.binance.com:9443/ws';
  static const _parser = OrderBookParser();

  Future<List<Candle>> loadCandles(
    String symbol,
    String interval, {
    int limit = 60,
  }) =>
      BinanceMarketService().loadCandles(symbol, interval, limit: limit);

  Stream<OrderBookSnapshot> liveDepth(String symbol) async* {
    var retry = 0;
    while (true) {
      WebSocketChannel? channel;
      try {
        final stream = '${symbol.toLowerCase()}@depth20@100ms';
        channel = WebSocketChannel.connect(Uri.parse('$_ws/$stream'));
        await channel.ready.timeout(const Duration(seconds: 8));
        retry = 0;
        await for (final event in channel.stream) {
          yield _parser.parse(event as String, defaultSymbol: symbol);
        }
      } catch (_) {
        retry++;
        await Future<void>.delayed(Duration(seconds: retry.clamp(1, 8)));
      } finally {
        await channel?.sink.close();
      }
    }
  }

  Stream<Candle> liveCandles(String symbol, String interval) async* {
    var retry = 0;
    while (true) {
      WebSocketChannel? channel;
      try {
        final stream = '${symbol.toLowerCase()}@kline_$interval';
        channel = WebSocketChannel.connect(Uri.parse('$_ws/$stream'));
        await channel.ready.timeout(const Duration(seconds: 8));
        retry = 0;
        await for (final event in channel.stream) {
          final data = jsonDecode(event as String) as Map<String, dynamic>;
          final kline = data['k'] as Map<String, dynamic>;
          yield Candle(
            openTime: DateTime.fromMillisecondsSinceEpoch(kline['t'] as int),
            open: double.parse('${kline['o']}'),
            high: double.parse('${kline['h']}'),
            low: double.parse('${kline['l']}'),
            close: double.parse('${kline['c']}'),
            volume: double.parse('${kline['v']}'),
          );
        }
      } catch (_) {
        retry++;
        await Future<void>.delayed(Duration(seconds: retry.clamp(1, 8)));
      } finally {
        await channel?.sink.close();
      }
    }
  }
}
