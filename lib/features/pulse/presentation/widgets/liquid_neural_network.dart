import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'liquid_widgets.dart';

/// One node of the live analyst network.
class NeuralNode {
  const NeuralNode({
    required this.label,
    required this.layer,
    required this.activation,
    required this.strength,
    this.members = 1,
  });

  final String label;

  /// 0 = data sources … 4 = chief analyst.
  final int layer;

  /// Directional reading in [-1,1]; drives the colour.
  final double activation;

  /// Confidence in [0,1]; drives size and glow.
  final double strength;

  /// How many agents this node represents.
  final int members;
}

/// A weighted connection between two nodes.
class NeuralLink {
  const NeuralLink({
    required this.from,
    required this.to,
    required this.weight,
  });

  final int from;
  final int to;

  /// 0..1, drives thickness and how many pulses travel the edge.
  final double weight;
}

class NeuralGraph {
  const NeuralGraph({required this.nodes, required this.links});

  final List<NeuralNode> nodes;
  final List<NeuralLink> links;

  static const NeuralGraph empty =
      NeuralGraph(nodes: <NeuralNode>[], links: <NeuralLink>[]);

  int get layers {
    var maxLayer = 0;
    for (final node in nodes) {
      maxLayer = math.max(maxLayer, node.layer);
    }
    return maxLayer + 1;
  }
}

/// Live view of how the councils feed each other on their way to the chief.
///
/// Nodes are agent groups, edges are the flow of opinions, and the travelling
/// pulses are paced by each edge's current weight — so the picture actually
/// moves faster where the evidence is stronger.
class LiquidNeuralNetwork extends StatefulWidget {
  const LiquidNeuralNetwork({
    super.key,
    required this.graph,
    this.height = 330,
  });

  final NeuralGraph graph;
  final double height;

  @override
  State<LiquidNeuralNetwork> createState() => _LiquidNeuralNetworkState();
}

class _LiquidNeuralNetworkState extends State<LiquidNeuralNetwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Construyendo la red de analistas…',
            style: LiquidType.caption,
          ),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: _NeuralPainter(
              graph: widget.graph,
              phase: _controller.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _NeuralPainter extends CustomPainter {
  _NeuralPainter({required this.graph, required this.phase});

  final NeuralGraph graph;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final layers = graph.layers;
    if (layers == 0) return;

    // Layout: layers are columns, nodes spread vertically inside each column.
    final byLayer = <int, List<int>>{};
    for (var i = 0; i < graph.nodes.length; i++) {
      byLayer.putIfAbsent(graph.nodes[i].layer, () => <int>[]).add(i);
    }

    const leftPad = 46.0;
    const rightPad = 46.0;
    final usableWidth = math.max(size.width - leftPad - rightPad, 1);
    final positions = List<Offset>.filled(graph.nodes.length, Offset.zero);
    for (final entry in byLayer.entries) {
      final x = layers == 1
          ? size.width / 2
          : leftPad + usableWidth * (entry.key / (layers - 1));
      final count = entry.value.length;
      for (var i = 0; i < count; i++) {
        final t = count == 1 ? .5 : (i + .5) / count;
        // A slow vertical sway keeps the network feeling alive.
        final sway = math.sin(phase * 2 * math.pi + entry.key * .8 + i * .6) * 2.4;
        positions[entry.value[i]] =
            Offset(x, 20 + (size.height - 40) * t + sway);
      }
    }

    // --- Edges --------------------------------------------------------------
    for (final link in graph.links) {
      if (link.from >= positions.length || link.to >= positions.length) continue;
      final a = positions[link.from];
      final b = positions[link.to];
      final target = graph.nodes[link.to];
      final source = graph.nodes[link.from];
      final tone = _tone(
        (source.activation + target.activation) / 2,
        math.max(source.strength, target.strength),
      );

      final control = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(control.dx, a.dy, b.dx, b.dy);

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .5 + link.weight * 1.7
          ..color = tone.withValues(alpha: .10 + link.weight * .30),
      );

      // Travelling pulses.
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final metric = metrics.first;
      final pulses = 1 + (link.weight * 2).round();
      for (var p = 0; p < pulses; p++) {
        final offset = (phase * (.6 + link.weight) + p / pulses +
                link.from * .07) %
            1.0;
        final position = metric.getTangentForOffset(metric.length * offset);
        if (position == null) continue;
        canvas.drawCircle(
          position.position,
          1.6 + link.weight * 1.4,
          Paint()..color = tone.withValues(alpha: .55 + link.weight * .35),
        );
      }
    }

    // --- Nodes --------------------------------------------------------------
    for (var i = 0; i < graph.nodes.length; i++) {
      final node = graph.nodes[i];
      final center = positions[i];
      final tone = _tone(node.activation, node.strength);
      final radius = 6.0 + node.strength * 7 + (node.layer == 4 ? 7 : 0);

      canvas.drawCircle(
        center,
        radius + 8,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius + 8,
            <Color>[
              tone.withValues(alpha: .22 * (.35 + node.strength)),
              tone.withValues(alpha: 0),
            ],
          ),
      );
      canvas.drawCircle(center, radius, Paint()..color = LiquidPalette.surface);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = tone,
      );
      canvas.drawCircle(
        center,
        radius * .45,
        Paint()..color = tone.withValues(alpha: .55 + node.strength * .4),
      );

      // Label: outside on the flanks, above elsewhere.
      final isFirst = node.layer == 0;
      final isLast = node.layer == graph.layers - 1;
      final painter = TextPainter(
        text: TextSpan(
          text: node.members > 1 ? '${node.label}\n${node.members}' : node.label,
          style: TextStyle(
            fontSize: 8.4,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: LiquidPalette.inkSoft,
          ),
        ),
        textAlign: isFirst
            ? TextAlign.right
            : (isLast ? TextAlign.left : TextAlign.center),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: isFirst || isLast ? 44 : 62);

      final Offset labelOffset;
      if (isFirst) {
        labelOffset =
            Offset(center.dx - radius - 6 - painter.width, center.dy - painter.height / 2);
      } else if (isLast) {
        labelOffset =
            Offset(center.dx + radius + 6, center.dy - painter.height / 2);
      } else {
        labelOffset =
            Offset(center.dx - painter.width / 2, center.dy - radius - painter.height - 3);
      }
      painter.paint(canvas, labelOffset);
    }
  }

  Color _tone(double activation, double strength) {
    if (activation.abs() < .04 || strength < .06) {
      return LiquidPalette.inkFaint;
    }
    return LiquidPalette.directional(activation > 0);
  }

  @override
  bool shouldRepaint(covariant _NeuralPainter oldDelegate) => true;
}
