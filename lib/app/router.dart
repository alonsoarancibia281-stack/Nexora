import 'package:go_router/go_router.dart';
import '../features/alerts/presentation/alerts_screen.dart';
import '../features/analysis/presentation/analyze_placeholder_screen.dart';
import '../features/journal/presentation/journal_screen.dart';
import '../features/market/presentation/asset_detail_screen.dart';
import '../features/market/presentation/favorites_screen.dart';
import '../features/market/presentation/market_screen.dart';
import '../features/onboarding/presentation/home_screen.dart';
import '../features/risk/presentation/risk_calculator_screen.dart';
import '../features/simulator/presentation/simulator_screen.dart';

/// MVP v0.1 runs in guest mode: no account, verification or payment gate.
/// Authentication and subscriptions remain in the codebase for a later release.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/market', builder: (_, __) => const MarketScreen()),
    GoRoute(path: '/analyze', builder: (_, __) => const AnalyzePlaceholderScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
    GoRoute(path: '/risk', builder: (_, __) => const RiskCalculatorScreen()),
    GoRoute(path: '/simulator', builder: (_, __) => const SimulatorScreen()),
    GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
    GoRoute(path: '/journal', builder: (_, __) => const JournalScreen()),
    GoRoute(
      path: '/market/:symbol',
      builder: (_, state) => AssetDetailScreen(
        symbol: state.pathParameters['symbol'] ?? 'BTCUSDT',
      ),
    ),
  ],
);
