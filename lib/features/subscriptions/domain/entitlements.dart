class Entitlements {
  const Entitlements({
    required this.plan,
    required this.role,
    required this.dailyAnalyses,
    required this.activeAlerts,
    required this.ai,
    required this.backtesting,
    required this.reports,
    required this.admin,
  });

  final String plan;
  final String role;
  final int dailyAnalyses;
  final int activeAlerts;
  final bool ai;
  final bool backtesting;
  final bool reports;
  final bool admin;

  bool get unlimitedAnalyses => dailyAnalyses < 0;
  bool get unlimitedAlerts => activeAlerts < 0;

  factory Entitlements.fromJson(Map<String, dynamic> json) => Entitlements(
        plan: json['plan'] as String? ?? 'free',
        role: json['role'] as String? ?? 'user',
        dailyAnalyses: json['daily_analyses'] as int? ?? 0,
        activeAlerts: json['active_alerts'] as int? ?? 0,
        ai: json['ai'] as bool? ?? false,
        backtesting: json['backtesting'] as bool? ?? false,
        reports: json['reports'] as bool? ?? false,
        admin: json['admin'] as bool? ?? false,
      );
}
