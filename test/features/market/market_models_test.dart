import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/market/domain/market_asset.dart';

void main() {
  test('parses Binance 24h ticker', () {
    final asset = MarketAsset.fromTicker({
      'symbol': 'BTCUSDT',
      'lastPrice': '65000.50',
      'priceChangePercent': '2.35',
      'quoteVolume': '1200000000',
    });
    expect(asset.baseAsset, 'BTC');
    expect(asset.quoteAsset, 'USDT');
    expect(asset.price, 65000.50);
    expect(asset.changePercent24h, 2.35);
  });

  test('parses Binance kline row', () {
    final candle = Candle.fromBinance([
      1700000000000,
      '100.0',
      '110.0',
      '95.0',
      '105.0',
      '1234.5',
    ]);
    expect(candle.open, 100);
    expect(candle.high, 110);
    expect(candle.low, 95);
    expect(candle.close, 105);
    expect(candle.volume, 1234.5);
  });
}
