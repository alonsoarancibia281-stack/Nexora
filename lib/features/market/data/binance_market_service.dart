import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/candle.dart';
import '../domain/market_asset.dart';

/// One live 5-minute kline update as published by Binance.
class BinanceKlineTick {
  const BinanceKlineTick({
    required this.eventTime,
    required this.openTime,
    required this.closeTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.isClosed,
  });

  /// Exchange clock at the moment the message was produced.
  final DateTime eventTime;
  final DateTime openTime;

  /// Inclusive close timestamp reported by Binance (end of candle − 1 ms).
  final DateTime closeTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final bool isClosed;

  /// Exclusive end of the round, i.e. the instant the next candle opens.
  DateTime get roundEnd => closeTime.add(const Duration(milliseconds: 1));
}

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
    if (millis is! num) throw const FormatException('Binance no devolvió serverTime válido.');
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }

  List<MarketAsset> _parseMarket(String body) {
    final rows = jsonDecode(body) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>().where((e) => (e['symbol'] as String).endsWith('USDT')).map(MarketAsset.fromTicker).where((a) => a.price > 0 && a.volume24h > 0).toList()
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
    final uri = Uri.parse('$_rest/api/v3/klines').replace(queryParameters: {'symbol': symbol.toUpperCase(), 'interval': interval, 'limit': '$limit'});
    final response = await _getWithRetry(uri);
    return (jsonDecode(response.body) as List<dynamic>).map((e) => Candle.fromBinance(e as List<dynamic>)).toList();
  }

  Future<({double bidVolume, double askVolume})> loadDepthVolume(String symbol, {int limit = 100}) async {
    final m = await loadDepthMetrics(symbol, limit: limit);
    return (bidVolume: m.bidVolume, askVolume: m.askVolume);
  }

  Future<({double bidVolume, double askVolume, double bestBid, double bestAsk, double spreadBps, double micropriceEdge, double nearImbalance, double queueImbalance})> loadDepthMetrics(String symbol, {int limit = 100}) async {
    final uri = Uri.parse('$_rest/api/v3/depth').replace(queryParameters: {'symbol': symbol.toUpperCase(), 'limit': '$limit'});
    final response = await _getWithRetry(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final bids = (data['bids'] as List<dynamic>).cast<List<dynamic>>();
    final asks = (data['asks'] as List<dynamic>).cast<List<dynamic>>();
    double sumSide(List<List<dynamic>> rows) => rows.fold<double>(0, (sum, row) => sum + (double.tryParse('${row[1]}') ?? 0));
    final bidVolume = sumSide(bids);
    final askVolume = sumSide(asks);
    final bestBid = bids.isEmpty ? 0.0 : double.tryParse('${bids.first[0]}') ?? 0.0;
    final bestAsk = asks.isEmpty ? 0.0 : double.tryParse('${asks.first[0]}') ?? 0.0;
    final bidQty = bids.isEmpty ? 0.0 : double.tryParse('${bids.first[1]}') ?? 0.0;
    final askQty = asks.isEmpty ? 0.0 : double.tryParse('${asks.first[1]}') ?? 0.0;
    final mid = bestBid > 0 && bestAsk > 0 ? (bestBid + bestAsk) / 2 : 0.0;
    final spreadBps = mid <= 0 ? 0.0 : (bestAsk - bestBid) / mid * 10000;
    final topTotal = bidQty + askQty;
    final microprice = topTotal <= 0 ? mid : (bestAsk * bidQty + bestBid * askQty) / topTotal;
    final micropriceEdge = mid <= 0 ? 0.0 : ((microprice - mid) / mid * 10000).clamp(-5.0, 5.0).toDouble();
    final nearDepth = (bids.length < 10 || asks.length < 10) ? 10 : 10;
    final nearBid = sumSide(bids.take(nearDepth).toList());
    final nearAsk = sumSide(asks.take(nearDepth).toList());
    final nearTotal = nearBid + nearAsk;
    final nearImbalance = nearTotal <= 0 ? 0.0 : ((nearBid - nearAsk) / nearTotal).clamp(-1.0, 1.0).toDouble();
    final queueImbalance = topTotal <= 0 ? 0.0 : ((bidQty - askQty) / topTotal).clamp(-1.0, 1.0).toDouble();
    return (bidVolume: bidVolume, askVolume: askVolume, bestBid: bestBid, bestAsk: bestAsk, spreadBps: spreadBps, micropriceEdge: micropriceEdge, nearImbalance: nearImbalance, queueImbalance: queueImbalance);
  }

  Future<({double aggressorImbalance, double signedVolume, double tradeAcceleration, double priceImpulseBps, double flowPersistence, double largeTradeBias, int trades})> loadAggTradeMetrics(String symbol, {int limit = 500}) async {
    final safeLimit = limit.clamp(50, 1000);
    final uri = Uri.parse('$_rest/api/v3/aggTrades').replace(queryParameters: {'symbol': symbol.toUpperCase(), 'limit': '$safeLimit'});
    final response = await _getWithRetry(uri);
    final rows = (jsonDecode(response.body) as List<dynamic>).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return (aggressorImbalance: 0.0, signedVolume: 0.0, tradeAcceleration: 0.0, priceImpulseBps: 0.0, flowPersistence: 0.0, largeTradeBias: 0.0, trades: 0);
    }
    var buyQty = 0.0, sellQty = 0.0, signed = 0.0;
    final half = rows.length ~/ 2;
    var firstHalfQty = 0.0, secondHalfQty = 0.0;
    var sameSide = 0, transitions = 0;
    int? previousSide;
    final quantities = <double>[];
    final sides = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final qty = double.tryParse('${r['q']}') ?? 0.0;
      final buyerMaker = r['m'] == true;
      final side = buyerMaker ? -1 : 1;
      quantities.add(qty);
      sides.add(side);
      if (buyerMaker) { sellQty += qty; signed -= qty; } else { buyQty += qty; signed += qty; }
      if (i < half) { firstHalfQty += qty; } else { secondHalfQty += qty; }
      if (previousSide != null) {
        transitions++;
        if (previousSide == side) sameSide++;
      }
      previousSide = side;
    }
    final total = buyQty + sellQty;
    final aggressorImbalance = total <= 0 ? 0.0 : ((buyQty - sellQty) / total).clamp(-1.0, 1.0).toDouble();
    final signedVolume = total <= 0 ? 0.0 : (signed / total).clamp(-1.0, 1.0).toDouble();
    final tradeAcceleration = firstHalfQty <= 0 ? 0.0 : ((secondHalfQty / firstHalfQty) - 1).clamp(-1.0, 1.0).toDouble();
    final firstPrice = double.tryParse('${rows.first['p']}') ?? 0.0;
    final lastPrice = double.tryParse('${rows.last['p']}') ?? 0.0;
    final priceImpulseBps = firstPrice <= 0 ? 0.0 : ((lastPrice - firstPrice) / firstPrice * 10000).clamp(-20.0, 20.0).toDouble();
    final persistenceRatio = transitions == 0 ? 0.0 : (sameSide / transitions) * 2 - 1;
    final flowPersistence = (persistenceRatio * (aggressorImbalance == 0 ? 0.0 : aggressorImbalance.sign)).clamp(-1.0, 1.0).toDouble();
    final sorted = [...quantities]..sort();
    final cutoff = sorted.isEmpty ? 0.0 : sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    var largeSigned = 0.0, largeTotal = 0.0;
    for (var i = 0; i < quantities.length; i++) {
      if (quantities[i] >= cutoff && cutoff > 0) {
        largeSigned += quantities[i] * sides[i];
        largeTotal += quantities[i];
      }
    }
    final largeTradeBias = largeTotal <= 0 ? 0.0 : (largeSigned / largeTotal).clamp(-1.0, 1.0).toDouble();
    return (aggressorImbalance: aggressorImbalance, signedVolume: signedVolume, tradeAcceleration: tradeAcceleration, priceImpulseBps: priceImpulseBps, flowPersistence: flowPersistence, largeTradeBias: largeTradeBias, trades: rows.length);
  }

  /// Live 5-minute kline stream straight from Binance.
  ///
  /// Every message carries the exchange event time plus the exact open/close
  /// timestamps of the running candle, which is what keeps the round countdown
  /// aligned with Binance instead of with the device clock.
  Stream<BinanceKlineTick> liveKline(String symbol, String interval) async* {
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
          final k = data['k'];
          if (k is! Map<String, dynamic>) continue;
          final tick = BinanceKlineTick(
            eventTime: DateTime.fromMillisecondsSinceEpoch(
              (data['E'] as num?)?.toInt() ?? 0,
              isUtc: true,
            ),
            openTime: DateTime.fromMillisecondsSinceEpoch(
              (k['t'] as num?)?.toInt() ?? 0,
              isUtc: true,
            ),
            closeTime: DateTime.fromMillisecondsSinceEpoch(
              (k['T'] as num?)?.toInt() ?? 0,
              isUtc: true,
            ),
            open: double.tryParse('${k['o']}') ?? 0,
            high: double.tryParse('${k['h']}') ?? 0,
            low: double.tryParse('${k['l']}') ?? 0,
            close: double.tryParse('${k['c']}') ?? 0,
            volume: double.tryParse('${k['v']}') ?? 0,
            isClosed: k['x'] == true,
          );
          if (tick.openTime.millisecondsSinceEpoch > 0) yield tick;
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
