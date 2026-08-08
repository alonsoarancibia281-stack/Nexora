import 'market_asset.dart';

class MarketSummary {
  const MarketSummary({
    required this.totalAssets,
    required this.advancing,
    required this.declining,
    required this.averageChange,
    required this.totalQuoteVolume,
    required this.gainers,
    required this.losers,
  });

  final int totalAssets;
  final int advancing;
  final int declining;
  final double averageChange;
  final double totalQuoteVolume;
  final List<MarketAsset> gainers;
  final List<MarketAsset> losers;

  factory MarketSummary.fromAssets(List<MarketAsset> assets) {
    final valid = assets.where((a) => a.price > 0).toList();
    final gainers = [...valid]..sort((a, b) => b.changePercent24h.compareTo(a.changePercent24h));
    final losers = [...valid]..sort((a, b) => a.changePercent24h.compareTo(b.changePercent24h));
    final average = valid.isEmpty
        ? 0.0
        : valid.fold<double>(0, (sum, a) => sum + a.changePercent24h) / valid.length;
    final volume = valid.fold<double>(0, (sum, a) => sum + a.volume24h);
    return MarketSummary(
      totalAssets: valid.length,
      advancing: valid.where((a) => a.changePercent24h > 0).length,
      declining: valid.where((a) => a.changePercent24h < 0).length,
      averageChange: average,
      totalQuoteVolume: volume,
      gainers: gainers.take(5).toList(),
      losers: losers.take(5).toList(),
    );
  }
}
