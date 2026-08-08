import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/validators.dart';
import '../data/auth_repository.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  bool loading = false;
  String? message;

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() { loading = true; message = null; });
    try {
      await AuthRepository(Supabase.instance.client).resetPassword(email.text);
      setState(() => message = 'Si el correo está registrado, recibirás instrucciones para restablecer tu contraseña.');
    } catch (_) {
      setState(() => message = 'Si el correo está registrado, recibirás instrucciones para restablecer tu contraseña.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recuperar contraseña')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: form,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Restablece tu contraseña', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Por seguridad, no confirmamos si una dirección existe en el sistema.'),
                  const SizedBox(height: 24),
                  TextFormField(controller: email, validator: Validators.email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo electrónico')),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: loading ? null : submit, child: Text(loading ? 'Enviando…' : 'Enviar instrucciones')),
                  if (message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(message!)),
                  TextButton(onPressed: () => context.go('/login'), child: const Text('Volver al inicio de sesión')),
                ]),
              ),
            ),
          ),
        ),
      );
}
