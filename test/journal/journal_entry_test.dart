import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/journal/domain/journal_entry.dart';

void main(){
  test('journal entry round trips through json',(){
    final entry=JournalEntry(id:'1',symbol:'ETHUSDT',thesis:'Esperar confirmación',createdAt:DateTime.utc(2026,8,8),outcome:'Ganancia',pnlPercent:2.5);
    final restored=JournalEntry.fromJson(entry.toJson());
    expect(restored.id,'1');expect(restored.symbol,'ETHUSDT');expect(restored.thesis,'Esperar confirmación');expect(restored.outcome,'Ganancia');expect(restored.pnlPercent,2.5);
  });
}
