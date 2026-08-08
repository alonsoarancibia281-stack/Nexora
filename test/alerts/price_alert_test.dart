import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/alerts/domain/price_alert.dart';

void main(){
  final now=DateTime(2026,8,8);
  test('above alert triggers at or above target',(){
    final a=PriceAlert(id:'1',symbol:'BTCUSDT',targetPrice:100,direction:'above',createdAt:now);
    expect(a.shouldTrigger(99),isFalse);expect(a.shouldTrigger(100),isTrue);expect(a.shouldTrigger(101),isTrue);
  });
  test('below alert triggers at or below target',(){
    final a=PriceAlert(id:'2',symbol:'BTCUSDT',targetPrice:100,direction:'below',createdAt:now);
    expect(a.shouldTrigger(101),isFalse);expect(a.shouldTrigger(100),isTrue);expect(a.shouldTrigger(99),isTrue);
  });
  test('already triggered alert does not trigger again',(){
    final a=PriceAlert(id:'3',symbol:'BTCUSDT',targetPrice:100,direction:'above',createdAt:now,triggeredAt:now);
    expect(a.shouldTrigger(120),isFalse);
  });
}
