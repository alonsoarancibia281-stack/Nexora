import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexora_markets_ai/features/alerts/data/local_alerts_repository.dart';
import 'package:nexora_markets_ai/features/alerts/domain/price_alert.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));

  test('persists and evaluates alerts',() async {
    final repo=LocalAlertsRepository();
    final alert=PriceAlert(id:'a',symbol:'BTCUSDT',targetPrice:100,direction:'above',createdAt:DateTime(2026,8,8));
    await repo.add(alert);
    expect((await repo.load()).length,1);
    final evaluated=await repo.evaluate({'BTCUSDT':101});
    expect(evaluated.single.triggeredAt,isNotNull);
    expect((await repo.load()).single.triggeredAt,isNotNull);
  });
}
