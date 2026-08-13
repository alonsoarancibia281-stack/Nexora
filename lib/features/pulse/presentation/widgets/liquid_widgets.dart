import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Design tokens taken from the Nexora UI styleguide.
///
/// Warm paper background, white surfaces, hairline borders, one orange
/// primary — with the liquid motion layered on top instead of a dark glass
/// theme.
class LiquidPalette {
  const LiquidPalette._();

  // Colour tokens
  static const Color primary = Color(0xFFDF5830);
  static const Color primaryHover = Color(0xFFFF6A2C);
  static const Color primarySoft = Color(0xFFFDEDE7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color paper = Color(0xFFF4F2EE);
  static const Color paperDeep = Color(0xFFEDE9E3);
  static const Color border = Color(0xFFDFE2E4);
  static const Color disabled = Color(0xFFBDBDBD);

  // Ink
  static const Color ink = Color(0xFF1E1B19);
  static const Color inkSoft = Color(0xFF6B6560);
  static const Color inkFaint = Color(0xFF9A938C);

  // Semantics
  static const Color rise = Color(0xFF12876A);
  static const Color riseSoft = Color(0xFFE6F4F0);
  static const Color fall = Color(0xFFC93B3B);
  static const Color fallSoft = Color(0xFFFBEAEA);
  static const Color info = Color(0xFF3B6FC9);

  static Color directional(bool up) => up ? rise : fall;

  static Color directionalSoft(bool up) => up ? riseSoft : fallSoft;

  /// Soft elevation used by every card in the styleguide.
  static List<BoxShadow> elevation({double strength = 1}) => <BoxShadow>[
        BoxShadow(
          color: const Color(0xFF2A2320).withValues(alpha: .07 * strength),
          blurRadius: 18 * strength,
          offset: Offset(0, 8 * strength),
        ),
        BoxShadow(
          color: const Color(0xFF2A2320).withValues(alpha: .04 * strength),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
}

/// Typography scale from the styleguide.
class LiquidType {
  const LiquidType._();

  static const TextStyle display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.08,
    letterSpacing: -.8,
    color: LiquidPalette.ink,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -.3,
    color: LiquidPalette.ink,
  );
  static const TextStyle subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: LiquidPalette.ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: LiquidPalette.inkSoft,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    height: 1.4,
    color: LiquidPalette.inkSoft,
  );
  static const TextStyle micro = TextStyle(
    fontSize: 9.5,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w700,
    color: LiquidPalette.inkFaint,
  );
}

/// Paper backdrop with the drafting grid and slow liquid blooms behind it.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({
    super.key,
    required this.child,
    this.accent = LiquidPalette.primary,
    this.intensity = 1.0,
  });

  final Widget child;
  final Color accent;

  /// 0 keeps the background nearly still, 1 is the full flow.
  final double intensity;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFAF8F5),
                  LiquidPalette.paper,
                  LiquidPalette.paperDeep,
                ],
              ),
            ),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                painter: _LiquidPaperPainter(
                  progress: _controller.value,
                  accent: widget.accent,
                  intensity: widget.intensity,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      );
}

class _LiquidPaperPainter extends CustomPainter {
  _LiquidPaperPainter({
    required this.progress,
    required this.accent,
    required this.intensity,
  });

  final double progress;
  final Color accent;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    // Drafting grid.
    final grid = Paint()
      ..color = const Color(0xFF2A2320).withValues(alpha: .035)
      ..strokeWidth = .7;
    const step = 34.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final t = progress * 2 * math.pi;
    final blooms = <_Bloom>[
      _Bloom(
        center: Offset(
          size.width * (.18 + .10 * math.sin(t)),
          size.height * (.14 + .05 * math.cos(t * .8)),
        ),
        radius: size.shortestSide * .70,
        color: accent.withValues(alpha: .13 * intensity),
      ),
      _Bloom(
        center: Offset(
          size.width * (.88 + .07 * math.cos(t * .7)),
          size.height * (.34 + .07 * math.sin(t * 1.1)),
        ),
        radius: size.shortestSide * .60,
        color: const Color(0xFFFFB48A).withValues(alpha: .16 * intensity),
      ),
      _Bloom(
        center: Offset(
          size.width * (.52 + .13 * math.sin(t * .55 + 1.2)),
          size.height * (.86 + .05 * math.cos(t * .9)),
        ),
        radius: size.shortestSide * .72,
        color: const Color(0xFFCBD7E6).withValues(alpha: .22 * intensity),
      ),
    ];

    for (final bloom in blooms) {
      canvas.drawCircle(
        bloom.center,
        bloom.radius,
        Paint()
          ..shader = ui.Gradient.radial(
            bloom.center,
            bloom.radius,
            <Color>[bloom.color, bloom.color.withValues(alpha: 0)],
            <double>[0, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidPaperPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _Bloom {
  const _Bloom({
    required this.center,
    required this.radius,
    required this.color,
  });
  final Offset center;
  final double radius;
  final Color color;
}

/// White card with a hairline border and the styleguide's soft elevation.
class LiquidCard extends StatelessWidget {
  const LiquidCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.radius = 22,
    this.accent,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;

  /// When set, the card gets a tinted left edge and a matching border.
  final Color? accent;
  final bool elevated;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: LiquidPalette.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: accent == null
                ? LiquidPalette.border
                : accent!.withValues(alpha: .42),
          ),
          boxShadow: elevated ? LiquidPalette.elevation() : null,
        ),
        child: child,
      );
}

/// Big circular gauge whose liquid level is the probability.
class LiquidOrb extends StatefulWidget {
  const LiquidOrb({
    super.key,
    required this.probability,
    required this.up,
    required this.title,
    required this.subtitle,
    this.size = 220,
    this.pulsing = true,
    this.idle = false,
  });

  /// Winning probability in [0,1] — this is the fill level.
  final double probability;
  final bool up;
  final String title;
  final String subtitle;
  final double size;
  final bool pulsing;

  /// Renders in neutral primary tone while the chief analyst deliberates.
  final bool idle;

  @override
  State<LiquidOrb> createState() => _LiquidOrbState();
}

class _LiquidOrbState extends State<LiquidOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.idle
        ? LiquidPalette.primary
        : LiquidPalette.directional(widget.up);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => CustomPaint(
            painter: _LiquidOrbPainter(
              phase: _controller.value,
              level: widget.probability.clamp(0.0, 1.0).toDouble(),
              color: color,
              pulsing: widget.pulsing,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: widget.size * .155,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                      height: 1.05,
                      color: LiquidPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: widget.size * .058,
                        color: LiquidPalette.inkSoft,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidOrbPainter extends CustomPainter {
  _LiquidOrbPainter({
    required this.phase,
    required this.level,
    required this.color,
    required this.pulsing,
  });

  final double phase;
  final double level;
  final Color color;
  final bool pulsing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;

    // Soft outer glow (the styleguide's focus ring, liquefied).
    canvas.drawCircle(
      center,
      radius + 7,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius + 7,
          <Color>[
            color.withValues(
              alpha: pulsing
                  ? .13 + .06 * math.sin(phase * 2 * math.pi)
                  : .13,
            ),
            color.withValues(alpha: 0),
          ],
          <double>[.74, 1],
        ),
    );

    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(circle);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = LiquidPalette.surface,
    );

    final surfaceY = size.height * (1 - level);
    for (var layer = 0; layer < 2; layer++) {
      final amplitude = radius * (layer == 0 ? .05 : .033);
      final speed = layer == 0 ? 1.0 : -1.4;
      final offset = layer == 0 ? 0.0 : math.pi / 2;
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, surfaceY);
      for (var x = 0.0; x <= size.width; x += 4) {
        final normalized = x / size.width;
        final y = surfaceY +
            math.sin(normalized * 2 * math.pi * 1.6 +
                    phase * 2 * math.pi * speed +
                    offset) *
                amplitude;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, surfaceY),
            Offset(0, size.height),
            <Color>[
              color.withValues(alpha: layer == 0 ? .30 : .18),
              color.withValues(alpha: layer == 0 ? .13 : .07),
            ],
          ),
      );
    }

    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .45),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidOrbPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.level != level ||
      oldDelegate.color != color;
}

/// Horizontal wave-filled progress bar.
class LiquidWaveBar extends StatefulWidget {
  const LiquidWaveBar({
    super.key,
    required this.value,
    this.color = LiquidPalette.primary,
    this.height = 12,
  });

  final double value;
  final Color color;
  final double height;

  @override
  State<LiquidWaveBar> createState() => _LiquidWaveBarState();
}

class _LiquidWaveBarState extends State<LiquidWaveBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => CustomPaint(
              size: Size.infinite,
              painter: _WaveBarPainter(
                phase: _controller.value,
                value: widget.value.clamp(0.0, 1.0).toDouble(),
                color: widget.color,
              ),
            ),
          ),
        ),
      );
}

class _WaveBarPainter extends CustomPainter {
  _WaveBarPainter({
    required this.phase,
    required this.value,
    required this.color,
  });

  final double phase;
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = LiquidPalette.paperDeep);
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = LiquidPalette.border,
    );
    if (value <= 0) return;

    canvas.save();
    canvas.clipRRect(track);
    final width = size.width * value;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= width; x += 3) {
      final y = size.height * .40 +
          math.sin(x / size.width * 12 + phase * 2 * math.pi) *
              size.height *
              .24;
      path.lineTo(x, y);
    }
    path.lineTo(width, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(math.max(width, 1), 0),
          <Color>[color.withValues(alpha: .70), color],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaveBarPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.value != value ||
      oldDelegate.color != color;
}

/// Labelled bipolar meter (−1 … +1) or unipolar bar (0 … 1).
class LiquidMeter extends StatelessWidget {
  const LiquidMeter({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.bipolar = true,
    this.color,
  });

  final String label;
  final double value;
  final String? trailing;
  final bool bipolar;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value : 0.0;
    final tone = color ??
        (bipolar ? LiquidPalette.directional(v >= 0) : LiquidPalette.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: LiquidType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing ??
                    (bipolar
                        ? (v * 100).toStringAsFixed(0)
                        : '${(v * 100).toStringAsFixed(0)}%'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 6,
            child: CustomPaint(
              size: Size.infinite,
              painter: _MeterPainter(
                value: bipolar ? v.clamp(-1.0, 1.0) : v.clamp(0.0, 1.0),
                bipolar: bipolar,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.value,
    required this.bipolar,
    required this.color,
  });

  final double value;
  final bool bipolar;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = LiquidPalette.paperDeep,
    );
    final paint = Paint()..color = color;
    if (bipolar) {
      final centerX = size.width / 2;
      final extent = (size.width / 2) * value.abs();
      final rect = value >= 0
          ? Rect.fromLTWH(centerX, 0, extent, size.height)
          : Rect.fromLTWH(centerX - extent, 0, extent, size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      canvas.drawRect(
        Rect.fromLTWH(centerX - .5, 0, 1, size.height),
        Paint()..color = LiquidPalette.inkFaint.withValues(alpha: .45),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * value, size.height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

/// Pill tag, primary or neutral, per the styleguide's chip row.
class LiquidChip extends StatelessWidget {
  const LiquidChip({
    super.key,
    required this.label,
    this.color = LiquidPalette.primary,
    this.icon,
    this.dense = false,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 9 : 12,
        vertical: dense ? 4 : 6.5,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: .28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: foreground,
              letterSpacing: .1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary action of the styleguide: filled pill, white label, soft elevation.
class LiquidButton extends StatelessWidget {
  const LiquidButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = LiquidPalette.primary,
    this.outlined = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  /// Secondary treatment: hairline border on paper instead of a filled pill.
  final bool outlined;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tone = enabled ? color : LiquidPalette.disabled;
    final foreground = outlined ? tone : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : tone,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: outlined ? tone.withValues(alpha: .45) : tone,
            ),
            boxShadow: outlined || !enabled
                ? null
                : LiquidPalette.elevation(strength: .55),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                    color: foreground,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 17, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alert row with a leading icon, matching the styleguide's alert block.
class LiquidAlert extends StatelessWidget {
  const LiquidAlert({
    super.key,
    required this.message,
    this.tone = LiquidPalette.primary,
    this.icon = Icons.info_outline,
  });

  final String message;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.withValues(alpha: .30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: LiquidType.caption.copyWith(color: LiquidPalette.ink),
              ),
            ),
          ],
        ),
      );
}

/// Underlined tab row.
class LiquidTabs extends StatelessWidget {
  const LiquidTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                i == index ? FontWeight.w800 : FontWeight.w500,
                            color: i == index
                                ? LiquidPalette.ink
                                : LiquidPalette.inkFaint,
                          ),
                        ),
                      ),
                      Container(
                        height: 2,
                        width: tabs[i].length * 7.0 + 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i == index
                              ? LiquidPalette.primary
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Section title with the styleguide's rule above it.
class LiquidSectionTitle extends StatelessWidget {
  const LiquidSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 1, color: LiquidPalette.ink.withValues(alpha: .18)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: LiquidType.subtitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: LiquidType.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ],
        ),
      );
}

/// Price path of the running round with the opening reference line.
class LiquidRoundChart extends StatelessWidget {
  const LiquidRoundChart({
    super.key,
    required this.path,
    required this.entryPrice,
    required this.up,
    this.height = 100,
  });

  /// Prices sampled since the round opened, oldest first.
  final List<double> path;
  final double entryPrice;
  final bool up;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _RoundChartPainter(
            path: path,
            entryPrice: entryPrice,
            color: LiquidPalette.directional(up),
          ),
        ),
      );
}

class _RoundChartPainter extends CustomPainter {
  _RoundChartPainter({
    required this.path,
    required this.entryPrice,
    required this.color,
  });

  final List<double> path;
  final double entryPrice;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2 || entryPrice <= 0) {
      final text = TextPainter(
        text: const TextSpan(
          text: 'Capturando la ronda…',
          style: TextStyle(color: LiquidPalette.inkFaint, fontSize: 11.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
      return;
    }

    var minPrice = entryPrice;
    var maxPrice = entryPrice;
    for (final p in path) {
      minPrice = math.min(minPrice, p);
      maxPrice = math.max(maxPrice, p);
    }
    final span = math.max(maxPrice - minPrice, entryPrice * 1e-6);
    final pad = span * .18;
    final lo = minPrice - pad;
    final hi = maxPrice + pad;
    double toY(double price) =>
        size.height - ((price - lo) / (hi - lo)) * size.height;
    double toX(int index) =>
        path.length == 1 ? 0 : (index / (path.length - 1)) * size.width;

    final entryY = toY(entryPrice);
    final dash = Paint()
      ..color = LiquidPalette.inkFaint.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, entryY), Offset(x + 4, entryY), dash);
    }

    final line = Path();
    for (var i = 0; i < path.length; i++) {
      final point = Offset(toX(i), toY(path[i]));
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }

    final fill = Path.from(line)
      ..lineTo(size.width, entryY)
      ..lineTo(0, entryY)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.height),
          <Color>[color.withValues(alpha: .22), color.withValues(alpha: .02)],
        ),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final last = Offset(toX(path.length - 1), toY(path.last));
    canvas.drawCircle(last, 5.5, Paint()..color = color.withValues(alpha: .22));
    canvas.drawCircle(last, 2.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RoundChartPainter oldDelegate) =>
      oldDelegate.path.length != path.length ||
      oldDelegate.entryPrice != entryPrice ||
      oldDelegate.color != color ||
      (oldDelegate.path.isNotEmpty &&
          path.isNotEmpty &&
          oldDelegate.path.last != path.last);
}

/// Compact stat block used inside cards.
class LiquidStat extends StatelessWidget {
  const LiquidStat({
    super.key,
    required this.label,
    required this.value,
    this.color = LiquidPalette.ink,
    this.caption,
  });

  final String label;
  final String value;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: LiquidType.micro),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -.2,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: const TextStyle(
                fontSize: 10.5,
                color: LiquidPalette.inkFaint,
              ),
            ),
          ],
        ],
      );
}
