import 'package:go_router/go_router.dart';
import '../features/onboarding/presentation/home_screen.dart';

/// MVP v0.1 runs in guest mode: no account, verification or payment gate.
/// Authentication and subscriptions remain in the codebase for a later release.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
  ],
);
