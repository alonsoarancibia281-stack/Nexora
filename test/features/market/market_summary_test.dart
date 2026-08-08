import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/market_asset.dart';
import 'package:nexora_markets_ai/features/market/domain/market_summary.dart';

void main() {
  test('builds gainers, losers and breadth correctly', () {
    const assets = [
      MarketAsset(symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', price: 100, changePercent24h: 4, volume24h: 1000),
      MarketAsset(symbol: 'ETHUSDT', baseAsset: 'ETH', quoteAsset: 'USDT', price: 50, changePercent24h: -2, volume24h: 500),
      MarketAsset(symbol: 'SOLUSDT', baseAsset: 'SOL', quoteAsset: 'USDT', price: 20, changePercent24h: 1, volume24h: 250),
    ];

    final summary = MarketSummary.fromAssets(assets);
    expect(summary.totalAssets, 3);
    expect(summary.advancing, 2);
    expect(summary.declining, 1);
    expect(summary.gainers.first.symbol, 'BTCUSDT');
    expect(summary.losers.first.symbol, 'ETHUSDT');
    expect(summary.totalQuoteVolume, 1750);
  });
}
