class MarketAsset {
  const MarketAsset({
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
    required this.price,
    required this.changePercent24h,
    required this.volume24h,
  });

  final String symbol;
  final String baseAsset;
  final String quoteAsset;
  final double price;
  final double changePercent24h;
  final double volume24h;

  factory MarketAsset.fromTicker(Map<String, dynamic> json) {
    final symbol = json['symbol'] as String;
    final quote = symbol.endsWith('USDT') ? 'USDT' : '';
    final base = quote.isEmpty ? symbol : symbol.substring(0, symbol.length - quote.length);
    return MarketAsset(
      symbol: symbol,
      baseAsset: base,
      quoteAsset: quote,
      price: double.tryParse('${json['lastPrice']}') ?? 0,
      changePercent24h: double.tryParse('${json['priceChangePercent']}') ?? 0,
      volume24h: double.tryParse('${json['quoteVolume']}') ?? 0,
    );
  }
}
