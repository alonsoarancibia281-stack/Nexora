import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/candle.dart';
import '../domain/market_asset.dart';

class BinanceMarketService {
  BinanceMarketService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _rest = 'https://api.binance.com';
  static const _ws = 'wss://stream.binance.com:9443/ws';

  Future<List<MarketAsset>> loadUsdtMarket() async {
    final response = await _client.get(Uri.parse('$_rest/api/v3/ticker/24hr'));
    if (response.statusCode != 200) {
      throw Exception('No se pudo cargar Binance (${response.statusCode}).');
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .where((e) => (e['symbol'] as String).endsWith('USDT'))
        .map(MarketAsset.fromTicker)
        .where((a) => a.price > 0 && a.volume24h > 0)
        .toList()
      ..sort((a, b) => b.volume24h.compareTo(a.volume24h));
  }

  Future<List<Candle>> loadCandles(String symbol, String interval, {int limit = 120}) async {
    final uri = Uri.parse('$_rest/api/v3/klines').replace(queryParameters: {
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '$limit',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) throw Exception('No se pudieron cargar las velas.');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Candle.fromBinance(e as List<dynamic>))
        .toList();
  }

  Stream<double> livePrice(String symbol) async* {
    var retry = 0;
    while (true) {
      WebSocketChannel? channel;
      try {
        final stream = '${symbol.toLowerCase()}@trade';
        channel = WebSocketChannel.connect(Uri.parse('$_ws/$stream'));
        await channel.ready.timeout(const Duration(seconds: 8));
        retry = 0;
        await for (final event in channel.stream) {
          final data = jsonDecode(event as String) as Map<String, dynamic>;
          final price = double.tryParse('${data['p']}');
          if (price != null) yield price;
        }
      } catch (_) {
        retry++;
        final seconds = retry.clamp(1, 8);
        await Future<void>.delayed(Duration(seconds: seconds));
      } finally {
        await channel?.sink.close();
      }
    }
  }
}
