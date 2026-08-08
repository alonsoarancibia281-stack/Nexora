import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/candle.dart';
import '../domain/market_asset.dart';

class BinanceMarketService {
  BinanceMarketService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _rest = 'https://api.binance.com';
  static const _ws = 'wss://stream.binance.com:9443/ws';
  static const _marketCacheKey = 'nexora_market_cache_v1';

  Future<http.Response> _getWithRetry(Uri uri, {int attempts = 3}) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        final response = await _client.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) return response;
        lastError = Exception('HTTP ${response.statusCode}');
      } catch (error) {
        lastError = error;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    throw Exception('No se pudo conectar con Binance. ${lastError ?? ''}'.trim());
  }

  Future<DateTime> loadServerTime() async {
    final response = await _getWithRetry(Uri.parse('$_rest/api/v3/time'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final millis = data['serverTime'];
    if (millis is! num) {
      throw const FormatException('Binance no devolvió serverTime válido.');
    }
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }

  List<MarketAsset> _parseMarket(String body) {
    final rows = jsonDecode(body) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .where((e) => (e['symbol'] as String).endsWith('USDT'))
        .map(MarketAsset.fromTicker)
        .where((a) => a.price > 0 && a.volume24h > 0)
        .toList()
      ..sort((a, b) => b.volume24h.compareTo(a.volume24h));
  }

  Future<List<MarketAsset>> loadUsdtMarket() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await _getWithRetry(Uri.parse('$_rest/api/v3/ticker/24hr'));
      await prefs.setString(_marketCacheKey, response.body);
      await prefs.setInt('${_marketCacheKey}_at', DateTime.now().millisecondsSinceEpoch);
      return _parseMarket(response.body);
    } catch (_) {
      final cached = prefs.getString(_marketCacheKey);
      if (cached != null && cached.isNotEmpty) return _parseMarket(cached);
      rethrow;
    }
  }

  Future<DateTime?> cachedMarketTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('${_marketCacheKey}_at');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<List<Candle>> loadCandles(String symbol, String interval, {int limit = 120}) async {
    final uri = Uri.parse('$_rest/api/v3/klines').replace(queryParameters: {
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '$limit',
    });
    final response = await _getWithRetry(uri);
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Candle.fromBinance(e as List<dynamic>))
        .toList();
  }

  Future<({double bidVolume, double askVolume})> loadDepthVolume(
    String symbol, {
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_rest/api/v3/depth').replace(queryParameters: {
      'symbol': symbol.toUpperCase(),
      'limit': '$limit',
    });
    final response = await _getWithRetry(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    double sumSide(dynamic rows) => (rows as List<dynamic>).fold<double>(
          0,
          (sum, row) => sum + (double.tryParse('${(row as List<dynamic>)[1]}') ?? 0),
        );
    return (
      bidVolume: sumSide(data['bids']),
      askVolume: sumSide(data['asks']),
    );
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
