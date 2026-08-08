import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRepository {
  AdminRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> loadMetrics() async {
    final data = await client.rpc('admin_dashboard_metrics');
    if (data is! Map<String, dynamic>) throw StateError('Invalid admin metrics');
    return data;
  }

  Future<List<Map<String, dynamic>>> listUsers({String query = ''}) async {
    final data = await client.rpc('admin_list_users', params: {'p_query': query, 'p_limit': 50});
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> setSuspension(String userId, bool suspended) => client.rpc(
        'admin_set_user_suspension',
        params: {'p_user_id': userId, 'p_suspended': suspended},
      );

  Future<void> setPlan(String userId, String plan) => client.rpc(
        'admin_set_user_plan',
        params: {'p_user_id': userId, 'p_plan': plan},
      );

  Future<List<Map<String, dynamic>>> listFeatureFlags() async {
    final data = await client.rpc('admin_list_feature_flags');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> setFeatureFlag(String key, bool enabled) => client.rpc(
        'admin_set_feature_flag',
        params: {'p_key': key, 'p_enabled': enabled},
      );
}
