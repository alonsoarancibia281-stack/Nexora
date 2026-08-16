import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/nexora_theme.dart';
import '../theme/theme_controller.dart';

class NexoraDestination {
  const NexoraDestination({
    required this.label,
    required this.route,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String route;
  final IconData icon;
  final IconData selectedIcon;
}

/// The map of the app. Order never changes, so muscle memory works.
const nexoraDestinations = <NexoraDestination>[
  NexoraDestination(
    label: 'Inicio',
    route: '/home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  NexoraDestination(
    label: 'Mercado',
    route: '/market',
    icon: Icons.show_chart_outlined,
    selectedIcon: Icons.show_chart,
  ),
  NexoraDestination(
    label: 'Flujo',
    route: '/order-book',
    icon: Icons.swap_vert,
    selectedIcon: Icons.swap_vert_circle,
  ),
  NexoraDestination(
    label: 'Analizar',
    route: '/analyze',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),
  NexoraDestination(
    label: 'Favoritos',
    route: '/favorites',
    icon: Icons.star_outline,
    selectedIcon: Icons.star,
  ),
  NexoraDestination(
    label: 'Predicción',
    route: '/pulse',
    icon: Icons.bolt_outlined,
    selectedIcon: Icons.bolt,
  ),
  NexoraDestination(
    label: 'Ajustes',
    route: '/settings',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
  ),
];

/// Frame around every main screen.
///
/// Wide window: a side bar that grows when the pointer sits on it.
/// Narrow window: a single row of pills at the bottom.
class NexoraShell extends StatelessWidget {
  const NexoraShell({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  final Widget child;
  final int currentIndex;

  static const railWidth = 80.0;
  static const railWidthOpen = 236.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (!wide) {
            return Column(
              children: [
                Expanded(child: child),
                _BottomPills(currentIndex: currentIndex),
              ],
            );
          }
          final pinned = constraints.maxWidth >= 1180;
          return Stack(
            children: [
              Padding(
                padding:
                    EdgeInsets.only(left: pinned ? railWidthOpen : railWidth),
                child: child,
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _HoverRail(currentIndex: currentIndex, pinned: pinned),
              ),
            ],
          );
        },
      );
}

/// Side bar that expands while the pointer hovers it.
class _HoverRail extends ConsumerStatefulWidget {
  const _HoverRail({required this.currentIndex, required this.pinned});

  final int currentIndex;
  final bool pinned;

  @override
  ConsumerState<_HoverRail> createState() => _HoverRailState();
}

class _HoverRailState extends ConsumerState<_HoverRail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = widget.pinned || _hovered;
    final mode = ref.watch(themeModeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: open ? NexoraShell.railWidthOpen : NexoraShell.railWidth,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: open ? .96 : .82),
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
          boxShadow: open && !widget.pinned
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .22),
                    blurRadius: 26,
                    offset: const Offset(6, 0),
                  ),
                ]
              : null,
        ),
        child: ClipRect(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RailBrand(open: open),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: nexoraDestinations.length,
                    itemBuilder: (context, index) => _RailItem(
                      destination: nexoraDestinations[index],
                      selected: index == widget.currentIndex,
                      open: open,
                    ),
                  ),
                ),
                const Divider(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: _ThemeButton(open: open, mode: mode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [NexoraTheme.brand, NexoraTheme.accent],
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.bolt, size: 20, color: Colors.white),
            ),
            if (open) ...[
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Nexora',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.open,
  });

  final NexoraDestination destination;
  final bool selected;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: open ? '' : destination.label,
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(NexoraTheme.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(NexoraTheme.radius),
            onTap: () => context.go(destination.route),
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: color,
                  ),
                  if (open) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeButton extends ConsumerWidget {
  const _ThemeButton({required this.open, required this.mode});

  final bool open;
  final ThemeMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(NexoraTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(NexoraTheme.radius),
        onTap: () =>
            ref.read(themeModeProvider.notifier).toggle(Theme.of(context).brightness),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              if (open) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    isDark ? 'Modo oscuro' : 'Modo claro',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom bar for phones: one line of pills, always readable.
class _BottomPills extends StatelessWidget {
  const _BottomPills({required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .94),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: nexoraDestinations.length,
            itemBuilder: (context, index) {
              final destination = nexoraDestinations[index];
              final selected = index == currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: selected
                      ? scheme.primary.withValues(alpha: .16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(NexoraTheme.radius),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(NexoraTheme.radius),
                    onTap: () => context.go(destination.route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            size: 20,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            Text(
                              destination.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
