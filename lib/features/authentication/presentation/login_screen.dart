import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/validators.dart';
import '../data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool resending = false;
  String? error;
  String? info;

  bool get needsVerification => error == 'Debes verificar tu correo antes de continuar.';

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() { loading = true; error = null; info = null; });
    try {
      await AuthRepository(Supabase.instance.client).login(email.text, password.text);
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'No pudimos iniciar sesión. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resendVerification() async {
    final emailError = Validators.email(email.text);
    if (emailError != null) {
      setState(() => error = emailError);
      return;
    }
    setState(() { resending = true; info = null; });
    try {
      await AuthRepository(Supabase.instance.client).resendVerificationCode(email.text);
      if (!mounted) return;
      setState(() => info = 'Si la cuenta existe y requiere verificación, enviamos un nuevo código.');
      context.go('/verify?email=${Uri.encodeComponent(email.text.trim())}');
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(padding: const EdgeInsets.all(24), child: Form(
        key: form,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Nexora Markets AI', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Entiende el mercado. Decide con contexto.'),
          const SizedBox(height: 32),
          TextFormField(controller: email, validator: Validators.email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo electrónico')),
          const SizedBox(height: 12),
          TextFormField(controller: password, validator: Validators.password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña')),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => context.go('/forgot-password'), child: const Text('¿Olvidaste tu contraseña?'))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!)),
          if (info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(info!)),
          if (needsVerification)
            TextButton(
              onPressed: resending ? null : resendVerification,
              child: Text(resending ? 'Reenviando…' : 'Reenviar código de verificación'),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: loading ? null : submit, child: Text(loading ? 'Ingresando…' : 'Iniciar sesión')),
          TextButton(onPressed: () => context.go('/register'), child: const Text('Crear cuenta')),
        ]),
      )),
    ))),
  );
}
