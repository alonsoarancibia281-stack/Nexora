import 'package:shared_preferences/shared_preferences.dart';

class FavoritesRepository {
  static const _key='market_favorites';
  Future<Set<String>> load() async => (await SharedPreferences.getInstance()).getStringList(_key)?.toSet() ?? {'BTCUSDT','ETHUSDT'};
  Future<void> toggle(String symbol) async {
    final prefs=await SharedPreferences.getInstance();
    final set=(prefs.getStringList(_key)??['BTCUSDT','ETHUSDT']).toSet();
    set.contains(symbol)?set.remove(symbol):set.add(symbol);
    await prefs.setStringList(_key,set.toList());
  }
}
