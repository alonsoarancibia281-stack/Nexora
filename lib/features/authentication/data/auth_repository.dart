import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this.client);
  final SupabaseClient client;

  Future<void> register({required String email, required String password, required String firstName, required String lastName, required String country, required String experience}) async {
    final response = await client.auth.signUp(email: email.trim().toLowerCase(), password: password, data: {
      'first_name': firstName.trim(), 'last_name': lastName.trim(), 'country': country, 'experience': experience,
    });
    if (response.user == null) throw const AuthException('No se pudo crear la cuenta');
    await client.functions.invoke('request-verification-code', body: {'email': email.trim().toLowerCase()});
  }

  Future<void> login(String email, String password) async {
    final response = await client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    if (response.user == null) throw const AuthException('Credenciales inválidas');
    final profile = await client.from('profiles').select('email_verified').eq('id', response.user!.id).single();
    if (profile['email_verified'] != true) {
      await client.auth.signOut();
      throw const AuthException('Debes verificar tu correo antes de continuar.');
    }
  }

  Future<void> resetPassword(String email) => client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  Future<void> signOut() => client.auth.signOut();
}
