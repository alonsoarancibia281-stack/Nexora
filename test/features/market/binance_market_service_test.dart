import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora_markets_ai/features/market/data/binance_market_service.dart';

void main() {
  test('cambia de endpoint y recuerda el host saludable', () async {
    var slowCalls = 0;
    var healthyCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'slow.example') {
        slowCalls++;
        return Future<http.Response>.delayed(
          const Duration(milliseconds: 80),
          () => http.Response('{}', 504),
        );
      }
      healthyCalls++;
      expect(request.url.path, '/api/v3/time');
      return http.Response(
        jsonEncode({'serverTime': 1786233600000}),
        200,
      );
    });
    final service = BinanceMarketService(
      client: client,
      restBases: [
        Uri.parse('https://slow.example'),
        Uri.parse('https://healthy.example'),
      ],
      requestTimeout: const Duration(milliseconds: 10),
    );

    final first = await service.loadServerTime();
    final second = await service.loadServerTime();

    expect(
        first, DateTime.fromMillisecondsSinceEpoch(1786233600000, isUtc: true));
    expect(second, first);
    expect(slowCalls, 1);
    expect(healthyCalls, 2);
  });

  test('no multiplica solicitudes cuando Binance limita la IP', () async {
    var backupCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'limited.example') {
        return http.Response('rate limited', 429);
      }
      backupCalls++;
      return http.Response(jsonEncode({'serverTime': 1}), 200);
    });
    final service = BinanceMarketService(
      client: client,
      restBases: [
        Uri.parse('https://limited.example'),
        Uri.parse('https://backup.example'),
      ],
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(service.loadServerTime(), throwsException);
    expect(backupCalls, 0);
  });
}
