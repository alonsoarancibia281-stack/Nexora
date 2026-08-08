import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/authentication/presentation/forgot_password_screen.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/authentication/presentation/register_screen.dart';
import '../features/authentication/presentation/update_password_screen.dart';
import '../features/email_verification/presentation/verify_email_screen.dart';
import '../features/onboarding/presentation/home_screen.dart';
import '../features/profile/presentation/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    final location = state.matchedLocation;
    final publicRoutes = {
      '/login',
      '/register',
      '/forgot-password',
      '/verify',
      '/update-password',
    };

    if (!hasSession && !publicRoutes.contains(location)) {
      return '/login';
    }

    if (hasSession && (location == '/login' || location == '/register')) {
      return '/home';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/update-password',
      builder: (_, __) => const UpdatePasswordScreen(),
    ),
    GoRoute(
      path: '/verify',
      builder: (_, state) => VerifyEmailScreen(
        email: state.uri.queryParameters['email'] ?? '',
      ),
    ),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
  ],
);
