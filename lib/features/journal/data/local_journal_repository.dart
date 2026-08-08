import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/journal_entry.dart';

class LocalJournalRepository {
  static const _key='nexora_journal_v1';

  Future<List<JournalEntry>> load() async {
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString(_key);
    if(raw==null||raw.isEmpty)return [];
    try{return (jsonDecode(raw) as List<dynamic>).map((e)=>JournalEntry.fromJson(e as Map<String,dynamic>)).toList();}catch(_){return [];}
  }

  Future<void> save(List<JournalEntry> entries) async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(_key,jsonEncode(entries.map((e)=>e.toJson()).toList()));
  }

  Future<void> add(JournalEntry entry) async {final entries=await load();entries.insert(0,entry);await save(entries);}
  Future<void> remove(String id) async {final entries=await load()..removeWhere((e)=>e.id==id);await save(entries);}
}
