/// One asset that survived the scan.
///
/// Every number here comes from public Binance data: the 24h ticker for the
/// universe and daily candles for the week and the month.
class ScanCandidate {
  const ScanCandidate({
    required this.symbol,
    required this.baseAsset,
    required this.price,
    required this.changePercent24h,
    required this.quoteVolume24h,
    required this.weekChangePercent,
    required this.monthChangePercent,
    required this.distanceFromMonthHighPercent,
    required this.volumeSurge,
    required this.upDayRatio,
    required this.atrPercent,
    required this.strength,
  });

  final String symbol;
  final String baseAsset;
  final double price;
  final double changePercent24h;

  /// Money traded in the last 24h, in USDT.
  final double quoteVolume24h;

  /// Change over the last 7 days, in percent.
  final double weekChangePercent;

  /// Change over the last 30 days, in percent.
  final double monthChangePercent;

  /// How far the price sits below the 30 day high, in percent. 0 means it is
  /// making new highs.
  final double distanceFromMonthHighPercent;

  /// Recent volume against its own month average. 1 means normal.
  final double volumeSurge;

  /// Share of the last 20 days that closed up, from 0 to 1.
  final double upDayRatio;

  /// Daily range as a percent of price. The market's own unit of movement.
  final double atrPercent;

  /// How strong this asset looks right now, from 0 to 100.
  final double strength;

  bool get isNearHigh => distanceFromMonthHighPercent <= 4;

  String get pair => '$baseAsset/USDT';
}
