import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexora_markets_ai/features/journal/data/local_journal_repository.dart';
import 'package:nexora_markets_ai/features/journal/domain/journal_entry.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));

  test('persists and removes journal entries',() async {
    final repo=LocalJournalRepository();
    final entry=JournalEntry(id:'1',symbol:'BTCUSDT',thesis:'Esperar confirmación',createdAt:DateTime(2026,8,8));
    await repo.add(entry);
    expect((await repo.load()).single.symbol,'BTCUSDT');
    await repo.remove('1');
    expect(await repo.load(),isEmpty);
  });
}
