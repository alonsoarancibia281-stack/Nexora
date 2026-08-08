import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionRepository {
  SessionRepository(this.client);
  final SupabaseClient client;

  Future<void> registerDevice({required String installationId, required String platform}) async {
    final session = client.auth.currentSession;
    if (session == null) return;
    final deviceHash = sha256.convert(utf8.encode(installationId)).toString();
    await client.from('user_devices').upsert({
      'user_id': session.user.id,
      'device_hash': deviceHash,
      'platform': platform,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'revoked_at': null,
    }, onConflict: 'user_id,device_hash');
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await client.from('user_devices').select('id,platform,last_seen_at,revoked_at').eq('user_id', userId).order('last_seen_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> signOutCurrent() => client.auth.signOut();

  Future<void> signOutAllDevices() async {
    try {
      await client.auth.signOut(scope: SignOutScope.global);
    } catch (e, st) {
      debugPrint('Global sign out failed: $e\n$st');
      rethrow;
    }
  }
}
