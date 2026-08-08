import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  // The MVP currently runs in guest mode. Supabase remains available for the
  // future authenticated release, but is intentionally optional here.
  if (url.isNotEmpty && publishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
    );
  }

  runApp(const ProviderScope(child: NexoraApp()));
}
