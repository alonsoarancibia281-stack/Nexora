import 'package:go_router/go_router.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/authentication/presentation/register_screen.dart';
import '../features/email_verification/presentation/verify_email_screen.dart';
import '../features/onboarding/presentation/home_screen.dart';

final appRouter = GoRouter(initialLocation: '/login', routes: [
  GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
  GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
  GoRoute(path: '/verify', builder: (_, state) => VerifyEmailScreen(email: state.uri.queryParameters['email'] ?? '')),
  GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
]);
