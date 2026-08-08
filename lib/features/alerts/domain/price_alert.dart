class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.targetPrice,
    required this.direction,
    required this.createdAt,
    this.triggeredAt,
    this.enabled = true,
  });

  final String id;
  final String symbol;
  final double targetPrice;
  final String direction; // above | below
  final DateTime createdAt;
  final DateTime? triggeredAt;
  final bool enabled;

  bool shouldTrigger(double price) {
    if (!enabled || triggeredAt != null) return false;
    return direction == 'above' ? price >= targetPrice : price <= targetPrice;
  }

  PriceAlert copyWith({DateTime? triggeredAt, bool? enabled}) => PriceAlert(
        id: id,
        symbol: symbol,
        targetPrice: targetPrice,
        direction: direction,
        createdAt: createdAt,
        triggeredAt: triggeredAt ?? this.triggeredAt,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'targetPrice': targetPrice,
        'direction': direction,
        'createdAt': createdAt.toIso8601String(),
        'triggeredAt': triggeredAt?.toIso8601String(),
        'enabled': enabled,
      };

  factory PriceAlert.fromJson(Map<String, dynamic> json) => PriceAlert(
        id: json['id'] as String,
        symbol: json['symbol'] as String,
        targetPrice: (json['targetPrice'] as num).toDouble(),
        direction: json['direction'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        triggeredAt: json['triggeredAt'] == null ? null : DateTime.parse(json['triggeredAt'] as String),
        enabled: json['enabled'] as bool? ?? true,
      );
}
