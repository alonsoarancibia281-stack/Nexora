import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/candle.dart';
import '../domain/market_asset.dart';

class OrderBookLevel {
  const OrderBookLevel({required this.price, required this.quantity});

  final double price;
  final double quantity;
}

class OrderBookSnapshot {
  const OrderBookSnapshot({required this.bids, required this.asks});

  final List<OrderBookLevel> bids;
  final List<OrderBookLevel> asks;

  double get bidVolume =>
      bids.fold<double>(0, (sum, level) => sum + level.quantity);
  double get askVolume =>
      asks.fold<double>(0, (sum, level) => sum + level.quantity);
  double get bestBid => bids.isEmpty ? 0 : bids.first.price;
  double get bestAsk => asks.isEmpty ? 0 : asks.first.price;
  double get midPrice =>
      bestBid > 0 && bestAsk > 0 ? (bestBid + bestAsk) / 2 : 0;
  double get spreadBps =>
      midPrice <= 0 ? 0 : (bestAsk - bestBid) / midPrice * 10000;
  double get micropriceEdge {
    if (bids.isEmpty || asks.isEmpty || midPrice <= 0) return 0;
    final bidQuantity = bids.first.quantity;
    final askQuantity = asks.first.quantity;
    final total = bidQuantity + askQuantity;
    final microprice = total <= 0
        ? midPrice
        : (bestAsk * bidQuantity + bestBid * askQuantity) / total;
    return ((microprice - midPrice) / midPrice * 10000)
        .clamp(-5.0, 5.0)
        .toDouble();
  }
}

class AggTradeSnapshot {
  const AggTradeSnapshot({
    required this.aggressorImbalance,
    required this.signedVolume,
    required this.tradeAcceleration,
    required this.priceImpulseBps,
    required this.trades,
    required this.buyQuantity,
    required this.sellQuantity,
    required this.tradesPerSecond,
  });

  final double aggressorImbalance;
  final double signedVolume;
  final double tradeAcceleration;
  final double priceImpulseBps;
  final int trades;
  final double buyQuantity;
  final double sellQuantity;
  final double tradesPerSecond;
}

class BinanceMarketService {
  BinanceMarketService({
    http.Client? client,
    List<Uri>? restBases,
    List<Uri>? webSocketBases,
    Duration requestTimeout = const Duration(seconds: 3),
    Duration socketConnectTimeout = const Duration(seconds: 4),
  })  : _client = client ?? http.Client(),
        _restBases = List.unmodifiable(restBases ?? _defaultRestBases),
        _webSocketBases =
            List.unmodifiable(webSocketBases ?? _defaultWebSocketBases),
        _requestTimeout = requestTimeout,
        _socketConnectTimeout = socketConnectTimeout {
    if (_restBases.isEmpty) {
      throw ArgumentError.value(restBases, 'restBases', 'No puede estar vacío');
    }
    if (_webSocketBases.isEmpty) {
      throw ArgumentError.value(
        webSocketBases,
        'webSocketBases',
        'No puede estar vacío',
      );
    }
  }

  final http.Client _client;
  final List<Uri> _restBases;
  final List<Uri> _webSocketBases;
  final Duration _requestTimeout;
  final Duration _socketConnectTimeout;
  int _preferredRestIndex = 0;
  int _preferredWebSocketIndex = 0;

  static const _rest = 'https://data-api.binance.vision';
  static final _defaultRestBases = <Uri>[
    Uri.parse('https://data-api.binance.vision'),
    Uri.parse('https://api.binance.com'),
    Uri.parse('https://api-gcp.binance.com'),
    Uri.parse('https://api1.binance.com'),
  ];
  static final _defaultWebSocketBases = <Uri>[
    Uri.parse('wss://data-stream.binance.vision'),
    Uri.parse('wss://stream.binance.com:443'),
    Uri.parse('wss://stream.binance.com:9443'),
  ];
  static const _marketCacheKey = 'nexora_market_cache_v1';

  List<int> _endpointOrder(int preferred, int length) => [
        preferred.clamp(0, length - 1),
        for (var index = 0; index < length; index++)
          if (index != preferred) index,
      ];

  Uri _moveToBase(Uri request, Uri base) => request.replace(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      );

  Future<http.Response> _getWithFailover(Uri request) async {
    Object? lastError;
    final order = _endpointOrder(_preferredRestIndex, _restBases.length);
    for (final index in order) {
      final uri = _moveToBase(request, _restBases[index]);
      try {
        final response = await _client.get(uri).timeout(_requestTimeout);
        if (response.statusCode == 200) {
          _preferredRestIndex = index;
          return response;
        }
        lastError = Exception('HTTP ${response.statusCode}');
        final clientError = response.statusCode >= 400 &&
            response.statusCode < 500 &&
            response.statusCode != 403 &&
            response.statusCode != 408;
        if (clientError) break;
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(
        'No se pudo conectar con Binance. ${lastError ?? ''}'.trim());
  }

  Future<DateTime> loadServerTime() async {
    final response = await _getWithFailover(Uri.parse('$_rest/api/v3/time'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final millis = data['serverTime'];
    if (millis is! num)
      throw const FormatException('Binance no devolvió serverTime válido.');
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
      final response =
          await _getWithFailover(Uri.parse('$_rest/api/v3/ticker/24hr'));
      await prefs.setString(_marketCacheKey, response.body);
      await prefs.setInt(
          '${_marketCacheKey}_at', DateTime.now().millisecondsSinceEpoch);
      return _parseMarket(response.body);
    } catch (_) {
      final cached = prefs.getString(_marketCacheKey);
      if (cached != null && cached.isNotEmpty) return _parseMarket(cached);
      rethrow;
    }
  }

  Future<MarketAsset> loadTicker24h(String symbol) async {
    final uri = Uri.parse('$_rest/api/v3/ticker/24hr').replace(
      queryParameters: {'symbol': symbol.toUpperCase()},
    );
    final response = await _getWithFailover(uri);
    return MarketAsset.fromTicker(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<DateTime?> cachedMarketTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('${_marketCacheKey}_at');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<List<Candle>> loadCandles(String symbol, String interval,
      {int limit = 120}) async {
    final uri = Uri.parse('$_rest/api/v3/klines').replace(queryParameters: {
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '$limit'
    });
    final response = await _getWithFailover(uri);
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Candle.fromBinance(e as List<dynamic>))
        .toList();
  }

  Future<({double bidVolume, double askVolume})> loadDepthVolume(String symbol,
      {int limit = 100}) async {
    final m = await loadDepthMetrics(symbol, limit: limit);
    return (bidVolume: m.bidVolume, askVolume: m.askVolume);
  }

  Future<OrderBookSnapshot> loadOrderBookSnapshot(
    String symbol, {
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_rest/api/v3/depth').replace(
      queryParameters: {
        'symbol': symbol.toUpperCase(),
        'limit': '$limit',
      },
    );
    final response = await _getWithFailover(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    List<OrderBookLevel> parseSide(Object? raw) =>
        ((raw as List<dynamic>?) ?? const [])
            .cast<List<dynamic>>()
            .map(
              (row) => OrderBookLevel(
                price: double.tryParse('${row[0]}') ?? 0,
                quantity: double.tryParse('${row[1]}') ?? 0,
              ),
            )
            .where((level) => level.price > 0 && level.quantity > 0)
            .toList(growable: false);
    return OrderBookSnapshot(
      bids: parseSide(data['bids']),
      asks: parseSide(data['asks']),
    );
  }

  Future<
      ({
        double bidVolume,
        double askVolume,
        double bestBid,
        double bestAsk,
        double spreadBps,
        double micropriceEdge
      })> loadDepthMetrics(String symbol, {int limit = 100}) async {
    final snapshot = await loadOrderBookSnapshot(symbol, limit: limit);
    return (
      bidVolume: snapshot.bidVolume,
      askVolume: snapshot.askVolume,
      bestBid: snapshot.bestBid,
      bestAsk: snapshot.bestAsk,
      spreadBps: snapshot.spreadBps,
      micropriceEdge: snapshot.micropriceEdge,
    );
  }

  Future<AggTradeSnapshot> loadAggTradeSnapshot(
    String symbol, {
    int limit = 500,
  }) async {
    final safeLimit = limit.clamp(50, 1000);
    final uri = Uri.parse('$_rest/api/v3/aggTrades').replace(
      queryParameters: {
        'symbol': symbol.toUpperCase(),
        'limit': '$safeLimit',
      },
    );
    final response = await _getWithFailover(uri);
    final rows = (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return const AggTradeSnapshot(
        aggressorImbalance: 0,
        signedVolume: 0,
        tradeAcceleration: 0,
        priceImpulseBps: 0,
        trades: 0,
        buyQuantity: 0,
        sellQuantity: 0,
        tradesPerSecond: 0,
      );
    }
    var buyQuantity = 0.0;
    var sellQuantity = 0.0;
    var signed = 0.0;
    final half = rows.length ~/ 2;
    var firstHalfQuantity = 0.0;
    var secondHalfQuantity = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final quantity = double.tryParse('${row['q']}') ?? 0;
      final buyerMaker = row['m'] == true;
      if (buyerMaker) {
        sellQuantity += quantity;
        signed -= quantity;
      } else {
        buyQuantity += quantity;
        signed += quantity;
      }
      if (i < half) {
        firstHalfQuantity += quantity;
      } else {
        secondHalfQuantity += quantity;
      }
    }
    final total = buyQuantity + sellQuantity;
    final firstPrice = double.tryParse('${rows.first['p']}') ?? 0;
    final lastPrice = double.tryParse('${rows.last['p']}') ?? 0;
    final firstTime = (rows.first['T'] as num?)?.toInt() ?? 0;
    final lastTime = (rows.last['T'] as num?)?.toInt() ?? firstTime;
    final spanSeconds = ((lastTime - firstTime) / 1000).clamp(1.0, 3600.0);
    return AggTradeSnapshot(
      aggressorImbalance: total <= 0
          ? 0
          : ((buyQuantity - sellQuantity) / total).clamp(-1.0, 1.0).toDouble(),
      signedVolume:
          total <= 0 ? 0 : (signed / total).clamp(-1.0, 1.0).toDouble(),
      tradeAcceleration: firstHalfQuantity <= 0
          ? 0
          : ((secondHalfQuantity / firstHalfQuantity) - 1)
              .clamp(-1.0, 1.0)
              .toDouble(),
      priceImpulseBps: firstPrice <= 0
          ? 0
          : ((lastPrice - firstPrice) / firstPrice * 10000)
              .clamp(-20.0, 20.0)
              .toDouble(),
      trades: rows.length,
      buyQuantity: buyQuantity,
      sellQuantity: sellQuantity,
      tradesPerSecond: rows.length / spanSeconds,
    );
  }

  Future<
      ({
        double aggressorImbalance,
        double signedVolume,
        double tradeAcceleration,
        double priceImpulseBps,
        int trades
      })> loadAggTradeMetrics(String symbol, {int limit = 500}) async {
    final snapshot = await loadAggTradeSnapshot(symbol, limit: limit);
    return (
      aggressorImbalance: snapshot.aggressorImbalance,
      signedVolume: snapshot.signedVolume,
      tradeAcceleration: snapshot.tradeAcceleration,
      priceImpulseBps: snapshot.priceImpulseBps,
      trades: snapshot.trades,
    );
  }

  Stream<double> livePrice(String symbol) async* {
    var failures = 0;
    while (true) {
      final order = _endpointOrder(
        _preferredWebSocketIndex,
        _webSocketBases.length,
      );
      for (final index in order) {
        WebSocketChannel? channel;
        try {
          final stream = '${symbol.toLowerCase()}@trade';
          final uri = _webSocketBases[index].replace(path: '/ws/$stream');
          channel = WebSocketChannel.connect(uri);
          await channel.ready.timeout(_socketConnectTimeout);
          _preferredWebSocketIndex = index;
          failures = 0;
          await for (final event in channel.stream) {
            final data = jsonDecode(event as String) as Map<String, dynamic>;
            final price = double.tryParse('${data['p']}');
            if (price != null) yield price;
          }
        } catch (_) {
          failures++;
        } finally {
          await channel?.sink.close();
        }
      }
      final milliseconds =
          (250 * (1 << failures.clamp(0, 4))).clamp(250, 3000).toInt();
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
    }
  }
}
