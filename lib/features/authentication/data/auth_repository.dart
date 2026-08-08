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

    if (response.user == null) {
      throw const AuthException('No se pudo crear la cuenta');
    }

    // Nexora uses its own server-side 6-digit verification flow. In hosted
    // Supabase, native email confirmation must be disabled so signUp returns
    // the short-lived session required to persist consent securely.
    if (response.session == null) {
      throw const AuthException(
        'El registro requiere desactivar la confirmación nativa de correo en Supabase para usar la verificación de Nexora.',
      );
    }

    try {
      final consentResponse = await client.functions.invoke(
        'register-consent',
        body: {
          'terms_version': '2026-08-01',
          'privacy_version': '2026-08-01',
          'marketing': marketing,
          'country': country.trim(),
        },
      );
      if (consentResponse.status >= 400) {
        throw const AuthException('No se pudo registrar el consentimiento.');
      }

      await resendVerificationCode(normalizedEmail);
    } finally {
      // Prevent access with the provisional Supabase session. The user must
      // verify Nexora's OTP and then sign in normally.
      await client.auth.signOut();
    }
  }

  Future<void> login(String email, String password) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('Credenciales inválidas');
    }

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

  Future<void> resendVerificationCode(String email) async {
    final response = await client.functions.invoke(
      'request-verification-code',
      body: {'email': email.trim().toLowerCase()},
    );
    if (response.status >= 400) {
      throw const AuthException('No se pudo reenviar el código.');
    }
  }

  Future<void> resetPassword(String email) {
    const recoveryRedirect = String.fromEnvironment(
      'PASSWORD_RECOVERY_REDIRECT',
      defaultValue: 'nexora://update-password',
    );
    return client.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      redirectTo: recoveryRedirect,
    );
  }

  Future<void> signOut() => client.auth.signOut();
}
