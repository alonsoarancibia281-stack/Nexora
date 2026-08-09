import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/candle.dart';
import '../domain/market_asset.dart';
import '../domain/symbol_trading_rules.dart';
import 'binance_market_service.dart';

class FuturesPremiumSnapshot {
  const FuturesPremiumSnapshot({
    required this.markPrice,
    required this.indexPrice,
    required this.fundingRate,
    required this.nextFundingTime,
  });

  final double markPrice;
  final double indexPrice;
  final double fundingRate;
  final DateTime nextFundingTime;

  double get basisBps =>
      indexPrice <= 0 ? 0 : (markPrice - indexPrice) / indexPrice * 10000;
}

/// Read-only USD(S)-M Futures market data.
///
/// Nexora never stores API credentials or sends orders. Trade endpoints require
/// a separate, explicitly authenticated integration and are intentionally not
/// part of this service.
class BinanceFuturesMarketService {
  BinanceFuturesMarketService({
    http.Client? client,
    Uri? restBase,
    Duration requestTimeout = const Duration(seconds: 3),
  })  : _client = client ?? http.Client(),
        _restBase = restBase ?? Uri.parse('https://fapi.binance.com'),
        _requestTimeout = requestTimeout;

  final http.Client _client;
  final Uri _restBase;
  final Duration _requestTimeout;
  final Map<String, SymbolTradingRules> _rulesCache = {};

  Uri _uri(String path, [Map<String, String>? query]) => _restBase.replace(
        path: path,
        queryParameters: query,
      );

  Future<http.Response> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response =
        await _client.get(_uri(path, query)).timeout(_requestTimeout);
    if (response.statusCode == 200) return response;
    if (response.statusCode == 429 || response.statusCode == 418) {
      throw Exception('Binance limitó temporalmente las consultas públicas.');
    }
    throw Exception('Binance Futures respondió HTTP ${response.statusCode}.');
  }

  Future<DateTime> loadServerTime() async {
    final response = await _get('/fapi/v1/time');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final millis = data['serverTime'];
    if (millis is! num) {
      throw const FormatException('Binance no devolvió serverTime válido.');
    }
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }

  Future<List<Candle>> loadCandles(
    String symbol,
    String interval, {
    int limit = 120,
  }) async {
    final response = await _get('/fapi/v1/klines', {
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '${limit.clamp(1, 1500)}',
    });
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) => Candle.fromBinance(row as List<dynamic>))
        .toList(growable: false);
  }

  Future<MarketAsset> loadTicker24h(String symbol) async {
    final response = await _get('/fapi/v1/ticker/24hr', {
      'symbol': symbol.toUpperCase(),
    });
    return MarketAsset.fromTicker(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<OrderBookSnapshot> loadOrderBookSnapshot(
    String symbol, {
    int limit = 100,
  }) async {
    final response = await _get('/fapi/v1/depth', {
      'symbol': symbol.toUpperCase(),
      'limit': '$limit',
    });
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

  Future<AggTradeSnapshot> loadAggTradeSnapshot(
    String symbol, {
    int limit = 500,
  }) async {
    final response = await _get('/fapi/v1/aggTrades', {
      'symbol': symbol.toUpperCase(),
      'limit': '${limit.clamp(50, 1000)}',
    });
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
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final quantity = double.tryParse('${row['q']}') ?? 0;
      final buyerIsMaker = row['m'] == true;
      if (buyerIsMaker) {
        sellQuantity += quantity;
        signed -= quantity;
      } else {
        buyQuantity += quantity;
        signed += quantity;
      }
      if (index < half) {
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

  Future<FuturesPremiumSnapshot> loadPremiumSnapshot(String symbol) async {
    final response = await _get('/fapi/v1/premiumIndex', {
      'symbol': symbol.toUpperCase(),
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FuturesPremiumSnapshot(
      markPrice: double.tryParse('${data['markPrice']}') ?? 0,
      indexPrice: double.tryParse('${data['indexPrice']}') ?? 0,
      fundingRate: double.tryParse('${data['lastFundingRate']}') ?? 0,
      nextFundingTime: DateTime.fromMillisecondsSinceEpoch(
        (data['nextFundingTime'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
    );
  }

  Future<SymbolTradingRules> loadTradingRules(String symbol) async {
    final normalized = symbol.toUpperCase();
    final cached = _rulesCache[normalized];
    if (cached != null) return cached;

    final response = await _get('/fapi/v1/exchangeInfo');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final symbols = (data['symbols'] as List<dynamic>?) ?? const [];
    final raw = symbols.cast<Map<String, dynamic>>().where(
          (row) =>
              row['symbol'] == normalized && row['contractType'] == 'PERPETUAL',
        );
    if (raw.isEmpty) {
      throw FormatException(
          '$normalized no es un contrato perpetuo disponible.');
    }
    final filters =
        (raw.first['filters'] as List<dynamic>).cast<Map<String, dynamic>>();
    Map<String, dynamic> filter(String type) => filters.firstWhere(
          (item) => item['filterType'] == type,
          orElse: () => const {},
        );
    final priceFilter = filter('PRICE_FILTER');
    final lotFilter = filter('LOT_SIZE');
    final notionalFilter = filter('MIN_NOTIONAL');
    final rules = SymbolTradingRules(
      symbol: normalized,
      tickSize: double.tryParse('${priceFilter['tickSize']}') ?? 0,
      quantityStep: double.tryParse('${lotFilter['stepSize']}') ?? 0,
      minimumQuantity: double.tryParse('${lotFilter['minQty']}') ?? 0,
      minimumNotional: double.tryParse(
            '${notionalFilter['notional'] ?? notionalFilter['minNotional']}',
          ) ??
          0,
    );
    if (rules.tickSize <= 0 ||
        rules.quantityStep <= 0 ||
        rules.minimumQuantity <= 0 ||
        rules.minimumNotional <= 0) {
      throw FormatException('Filtros de $normalized incompletos.');
    }
    _rulesCache[normalized] = rules;
    return rules;
  }
}
