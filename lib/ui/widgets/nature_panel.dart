import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated black-and-white nature scene (mountains, pine forest, moon,
/// drifting mist) drawn with a painter — no image assets, always matches
/// the black-and-white app style in both themes. Used to make waiting for
/// a download pleasant.
class NaturePanel extends StatefulWidget {
  const NaturePanel({super.key, required this.progress});

  /// 0..1 download progress, shown as mist clearing over the scene.
  final double progress;

  @override
  State<NaturePanel> createState() => _NaturePanelState();
}

class _NaturePanelState extends State<NaturePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _NaturePainter(
            time: _controller.value,
            progress: widget.progress,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _NaturePainter extends CustomPainter {
  _NaturePainter({required this.time, required this.progress, required this.dark});

  final double time;
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Color shade(double opacity) =>
        (dark ? Colors.white : Colors.black).withValues(alpha: opacity);

    // Sky gradient.
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [const Color(0xFF101010), const Color(0xFF1E1E1E)]
            : [const Color(0xFFEDEDED), const Color(0xFFDCDCDC)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    // Stars (dark theme) drift very slowly.
    if (dark) {
      final star = Paint()..color = Colors.white.withValues(alpha: 0.5);
      final rnd = math.Random(7);
      for (var i = 0; i < 42; i++) {
        final x = rnd.nextDouble() * w;
        final y = rnd.nextDouble() * h * 0.45;
        final twinkle = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(time * math.pi * 2 + i));
        star.color = Colors.white.withValues(alpha: twinkle * 0.6);
        canvas.drawCircle(Offset(x, y), i % 5 == 0 ? 1.4 : 0.8, star);
      }
    }

    // Moon with a slow halo pulse.
    final moonCenter = Offset(w * 0.76, h * 0.24);
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          shade(0.20 + 0.05 * math.sin(time * math.pi * 2)),
          shade(0),
        ],
      ).createShader(Rect.fromCircle(center: moonCenter, radius: 54));
    canvas.drawCircle(moonCenter, 54, halo);
    canvas.drawCircle(moonCenter, 17, Paint()..color = shade(0.92));
    canvas.drawCircle(
      Offset(moonCenter.dx - 6, moonCenter.dy - 4),
      4,
      Paint()..color = shade(0.10),
    );

    // Three mountain layers, parallax drift.
    _ridge(canvas, size, baseY: h * 0.58, amp: h * 0.16, shade: 0.10, drift: time * 6, seed: 3);
    _ridge(canvas, size, baseY: h * 0.70, amp: h * 0.13, shade: 0.18, drift: time * 10, seed: 11);
    _ridge(canvas, size, baseY: h * 0.82, amp: h * 0.10, shade: 0.30, drift: time * 16, seed: 23);

    // Pine forest silhouette along the bottom.
    final forest = Paint()..color = shade(0.55);
    final rnd = math.Random(5);
    for (var x = -8.0; x < w + 8; x += 13) {
      final treeH = 20 + rnd.nextDouble() * 26;
      final base = h + 2;
      final path = Path()
        ..moveTo(x, base)
        ..lineTo(x + 5, base - treeH)
        ..lineTo(x + 10, base)
        ..close();
      canvas.drawPath(path, forest);
      canvas.drawRect(
        Rect.fromLTWH(x + 4.2, base - 6, 1.6, 7),
        forest,
      );
    }

    // Mist: thick at 0%, clears as the download progresses.
    final mistAlpha = (1 - progress) * 0.35;
    if (mistAlpha > 0.01) {
      for (var layer = 0; layer < 3; layer++) {
        final y = h * (0.52 + layer * 0.13) +
            math.sin(time * math.pi * 2 + layer * 1.7) * 4;
        final mist = Paint()
          ..shader = LinearGradient(
            colors: [shade(0), shade(mistAlpha), shade(0)],
          ).createShader(Rect.fromLTWH(0, y - 16, w, 32));
        canvas.drawRect(Rect.fromLTWH(0, y - 16, w, 32), mist);
      }
    }
  }

  void _ridge(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amp,
    required double shade,
    required double drift,
    required int seed,
  }) {
    final path = Path()..moveTo(-10, size.height + 10);
    final rnd = math.Random(seed);
    final peaks = List.generate(7, (_) => 0.35 + rnd.nextDouble() * 0.65);
    for (var i = 0; i <= 6; i++) {
      final x = (size.width + 20) * i / 6 - 10;
      final y = baseY - peaks[i] * amp;
      final driftedX = x + math.sin(drift * 0.1 + i) * 2;
      if (i == 0) {
        path.lineTo(driftedX, y);
      } else {
        final prevX = (size.width + 20) * (i - 1) / 6 - 10;
        final midX = (prevX + driftedX) / 2;
        path.quadraticBezierTo(midX, baseY - amp * 0.15, driftedX, y);
      }
    }
    path
      ..lineTo(size.width + 10, size.height + 10)
      ..close();
    final color = (dark ? Colors.white : Colors.black).withValues(alpha: shade);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NaturePainter oldDelegate) => true;
}
