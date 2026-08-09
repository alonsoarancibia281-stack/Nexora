import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora_markets_ai/features/market/data/binance_futures_market_service.dart';

void main() {
  test('lee filtros del perpetuo y los conserva en memoria', () async {
    var exchangeInfoCalls = 0;
    final client = MockClient((request) async {
      expect(request.url.host, 'futures.example');
      if (request.url.path == '/fapi/v1/exchangeInfo') {
        exchangeInfoCalls++;
        return http.Response(
          jsonEncode({
            'symbols': [
              {
                'symbol': 'BTCUSDT',
                'contractType': 'PERPETUAL',
                'filters': [
                  {
                    'filterType': 'PRICE_FILTER',
                    'tickSize': '0.10',
                  },
                  {
                    'filterType': 'LOT_SIZE',
                    'minQty': '0.001',
                    'stepSize': '0.001',
                  },
                  {
                    'filterType': 'MIN_NOTIONAL',
                    'notional': '50',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      throw StateError('Ruta inesperada: ${request.url.path}');
    });
    final service = BinanceFuturesMarketService(
      client: client,
      restBase: Uri.parse('https://futures.example'),
    );

    final first = await service.loadTradingRules('btcusdt');
    final second = await service.loadTradingRules('BTCUSDT');

    expect(first.tickSize, .1);
    expect(first.quantityStep, .001);
    expect(first.minimumQuantity, .001);
    expect(first.minimumNotional, 50);
    expect(identical(first, second), isTrue);
    expect(exchangeInfoCalls, 1);
  });

  test('lee mark price, índice y financiación reales', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/fapi/v1/premiumIndex');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      return http.Response(
        jsonEncode({
          'markPrice': '65187.30000000',
          'indexPrice': '65216.23434783',
          'lastFundingRate': '0.00008178',
          'nextFundingTime': 1786262400000,
        }),
        200,
      );
    });
    final service = BinanceFuturesMarketService(
      client: client,
      restBase: Uri.parse('https://futures.example'),
    );

    final premium = await service.loadPremiumSnapshot('BTCUSDT');

    expect(premium.markPrice, 65187.3);
    expect(premium.indexPrice, 65216.23434783);
    expect(premium.fundingRate, .00008178);
    expect(premium.basisBps, lessThan(0));
    expect(premium.nextFundingTime.isUtc, isTrue);
  });
}
