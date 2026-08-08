import 'package:go_router/go_router.dart';
import '../features/onboarding/presentation/home_screen.dart';
import '../features/market/presentation/market_screen.dart';
import '../features/market/presentation/asset_detail_screen.dart';

/// MVP v0.1 runs in guest mode: no account, verification or payment gate.
/// Authentication and subscriptions remain in the codebase for a later release.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/market', builder: (_, __) => const MarketScreen()),
    GoRoute(path: '/market/:symbol', builder: (_, state) => AssetDetailScreen(symbol: state.pathParameters['symbol'] ?? 'BTCUSDT')),
  ],
);
