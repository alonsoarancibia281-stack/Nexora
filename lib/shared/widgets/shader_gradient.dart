import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/nexora_theme.dart';

/// Slow gradient that lives behind every screen.
///
/// It paints real shaders: one linear pass for the base and three radial
/// passes that drift with time. The movement is slow on purpose, so it never
/// competes with the numbers on top.
class ShaderGradientBackground extends StatefulWidget {
  const ShaderGradientBackground({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  State<ShaderGradientBackground> createState() =>
      _ShaderGradientBackgroundState();
}

class _ShaderGradientBackgroundState extends State<ShaderGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ShaderGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _ShaderGradientPainter(time: _controller.value, dark: isDark),
          isComplex: true,
          willChange: widget.animate,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ShaderGradientPainter extends CustomPainter {
  const _ShaderGradientPainter({required this.time, required this.dark});

  /// Loops from 0 to 1.
  final double time;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final angle = time * 2 * math.pi;

    final baseColors = dark
        ? const [Color(0xFF04080D), Color(0xFF08161B), Color(0xFF0A1020)]
        : const [Color(0xFFF3FBF8), Color(0xFFEAF4FF), Color(0xFFFDFDFB)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          baseColors,
          const [0, .55, 1],
        ),
    );

    final blobs = <_Blob>[
      _Blob(
        center: Offset(
          size.width * (.18 + .12 * math.cos(angle)),
          size.height * (.16 + .08 * math.sin(angle)),
        ),
        radius: size.longestSide * .55,
        color: NexoraTheme.brand,
        opacity: dark ? .22 : .16,
      ),
      _Blob(
        center: Offset(
          size.width * (.86 + .10 * math.sin(angle * .8)),
          size.height * (.30 + .12 * math.cos(angle * .8)),
        ),
        radius: size.longestSide * .48,
        color: NexoraTheme.accent,
        opacity: dark ? .18 : .14,
      ),
      _Blob(
        center: Offset(
          size.width * (.50 + .18 * math.cos(angle * .6 + 1.2)),
          size.height * (.92 + .06 * math.sin(angle * .6)),
        ),
        radius: size.longestSide * .60,
        color: dark ? NexoraTheme.brandDeep : NexoraTheme.brand,
        opacity: dark ? .20 : .12,
      ),
    ];

    for (final blob in blobs) {
      canvas.drawCircle(
        blob.center,
        blob.radius,
        Paint()
          ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
          ..shader = ui.Gradient.radial(
            blob.center,
            blob.radius,
            [
              blob.color.withValues(alpha: blob.opacity),
              blob.color.withValues(alpha: 0),
            ],
            const [0, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShaderGradientPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.dark != dark;
}

class _Blob {
  const _Blob({
    required this.center,
    required this.radius,
    required this.color,
    required this.opacity,
  });

  final Offset center;
  final double radius;
  final Color color;
  final double opacity;
}
