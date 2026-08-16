import 'package:go_router/go_router.dart';
import '../features/alerts/presentation/alerts_screen.dart';
import '../features/analysis/presentation/analyze_placeholder_screen.dart';
import '../features/journal/presentation/journal_screen.dart';
import '../features/market/presentation/asset_detail_screen.dart';
import '../features/market/presentation/favorites_screen.dart';
import '../features/market/presentation/market_screen.dart';
import '../features/onboarding/presentation/home_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/order_book/presentation/order_book_screen.dart';
import '../features/pulse/presentation/prediction_screen.dart';
import '../features/risk/presentation/risk_calculator_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/simulator/presentation/simulator_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/market', builder: (_, __) => const MarketScreen()),
    GoRoute(path: '/order-book', builder: (_, __) => const OrderBookScreen()),
    GoRoute(path: '/analyze', builder: (_, __) => const AnalyzePlaceholderScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/risk', builder: (_, __) => const RiskCalculatorScreen()),
    GoRoute(path: '/simulator', builder: (_, __) => const SimulatorScreen()),
    GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
    GoRoute(path: '/journal', builder: (_, __) => const JournalScreen()),
    GoRoute(path: '/pulse', builder: (_, __) => const PredictionScreen()),
    GoRoute(path: '/market/:symbol', builder: (_, state) => AssetDetailScreen(symbol: state.pathParameters['symbol'] ?? 'BTCUSDT')),
  ],
);
