import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/subscriptions/domain/entitlements.dart';

void main() {
  test('owner entitlements expose unlimited access', () {
    final e = Entitlements.fromJson({
      'plan': 'owner',
      'role': 'owner',
      'daily_analyses': -1,
      'active_alerts': -1,
      'ai': true,
      'backtesting': true,
      'reports': true,
      'admin': true,
    });
    expect(e.unlimitedAnalyses, isTrue);
    expect(e.unlimitedAlerts, isTrue);
    expect(e.admin, isTrue);
  });

  test('free entitlements stay limited', () {
    final e = Entitlements.fromJson({
      'plan': 'free',
      'role': 'user',
      'daily_analyses': 3,
      'active_alerts': 1,
      'ai': false,
      'backtesting': false,
      'reports': false,
      'admin': false,
    });
    expect(e.unlimitedAnalyses, isFalse);
    expect(e.dailyAnalyses, 3);
    expect(e.admin, isFalse);
  });
}
