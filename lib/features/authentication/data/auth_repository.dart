import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this.client);
  final SupabaseClient client;

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String country,
    required String experience,
    required bool marketing,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'country': country.trim(),
        'experience': experience,
      },
    );
    if (response.user == null) throw const AuthException('No se pudo crear la cuenta');
    await client.functions.invoke('register-consent', body: {
      'terms_version': '2026-08-01',
      'privacy_version': '2026-08-01',
      'marketing': marketing,
      'country': country.trim(),
    });
    await client.functions.invoke('request-verification-code', body: {'email': normalizedEmail});
  }

  Future<void> login(String email, String password) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    if (response.user == null) throw const AuthException('Credenciales inválidas');
    final profile = await client
        .from('profiles')
        .select('email_verified,suspended_at')
        .eq('id', response.user!.id)
        .single();
    if (profile['suspended_at'] != null) {
      await client.auth.signOut();
      throw const AuthException('Esta cuenta está suspendida. Contacta a soporte.');
    }
    if (profile['email_verified'] != true) {
      await client.auth.signOut();
      throw const AuthException('Debes verificar tu correo antes de continuar.');
    }
  }

  Future<void> resetPassword(String email) =>
      client.auth.resetPasswordForEmail(email.trim().toLowerCase());

  Future<void> signOut() => client.auth.signOut();
}
