import 'package:flutter/material.dart';

import '../theme/nexora_theme.dart';

/// Button hierarchy.
///
/// [primary] is the one action the screen wants, [secondary] supports it,
/// [tertiary] is optional and [quiet] is almost a link. Never place two
/// primaries side by side.
enum NexoraLevel { primary, secondary, tertiary, quiet }

/// A button with one job: show one line of text and never wrap it.
class NexoraButton extends StatelessWidget {
  const NexoraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.level = NexoraLevel.primary,
    this.expand = false,
    this.compact = false,
    this.tone,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NexoraLevel level;

  /// Fill the available width.
  final bool expand;

  /// Shorter height for dense rows.
  final bool compact;

  /// Override the accent colour, e.g. green for up and red for down.
  final Color? tone;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tone ?? scheme.primary;
    final height =
        compact ? NexoraTheme.compactButtonHeight : NexoraTheme.buttonHeight;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: compact ? 17 : 19),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final button = switch (level) {
      NexoraLevel.primary => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: _onColor(accent),
            minimumSize: Size(0, height),
          ),
          child: content,
        ),
      NexoraLevel.secondary => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accent.withValues(alpha: .16),
            foregroundColor: accent,
            minimumSize: Size(0, height),
          ),
          child: content,
        ),
      NexoraLevel.tertiary => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            minimumSize: Size(0, height),
          ),
          child: content,
        ),
      NexoraLevel.quiet => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            minimumSize: Size(0, height),
          ),
          child: content,
        ),
    };

    final sized = expand
        ? SizedBox(width: double.infinity, height: height, child: button)
        : SizedBox(height: height, child: button);
    return tooltip == null ? sized : Tooltip(message: tooltip!, child: sized);
  }

  static Color _onColor(Color background) =>
      background.computeLuminance() > .55 ? Colors.black87 : Colors.white;
}

/// A small label for one fact. Always one line, tinted by [tone].
class NexoraTag extends StatelessWidget {
  const NexoraTag(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// A row of options where only one is active. Labels stay on one line.
class NexoraSegmented<T> extends StatelessWidget {
  const NexoraSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.iconOf,
    this.tone,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final IconData? Function(T value)? iconOf;
  final ValueChanged<T> onSelected;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tone ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(NexoraTheme.radius + 4),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _SegmentButton(
                  label: labelOf(value),
                  icon: iconOf?.call(value),
                  selected: value == selected,
                  accent: accent,
                  onTap: () => onSelected(value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(NexoraTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(NexoraTheme.radius),
        onTap: onTap,
        child: SizedBox(
          height: NexoraTheme.buttonHeight - 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 17,
                  color: selected
                      ? NexoraButton._onColor(accent)
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: selected
                        ? NexoraButton._onColor(accent)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
