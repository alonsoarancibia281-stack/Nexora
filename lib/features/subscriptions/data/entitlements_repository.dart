import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entitlements.dart';

class EntitlementsRepository {
  EntitlementsRepository(this.client);
  final SupabaseClient client;

  Future<Entitlements> load() async {
    final data = await client.rpc('my_entitlements');
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid entitlements response');
    }
    return Entitlements.fromJson(data);
  }
}
