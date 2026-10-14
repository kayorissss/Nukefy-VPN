import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Calm monochrome landscape shown while a download runs: a moon, twinkling
/// stars and slow-drifting hill silhouettes, all in the app's own palette.
/// It is deliberately quiet — a 30-second loop of cheap shapes, no images,
/// no timers beyond the animation controller, and it stops with the widget.
class NaturePanel extends StatefulWidget {
  const NaturePanel({super.key, this.height = 190});

  final double height;

  @override
  State<NaturePanel> createState() => _NaturePanelState();
}

class _NaturePanelState extends State<NaturePanel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _NaturePainter(progress: _controller.value, palette: p),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _NaturePainter extends CustomPainter {
  _NaturePainter({required this.progress, required this.palette});

  final double progress;
  final NukefyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.surface, p.background],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    // Stars: deterministic pseudo-random field, twinkling out of phase.
    final starPaint = Paint();
    for (var i = 0; i < 70; i++) {
      final fx = ((i * 73.7) % 97) / 97;
      final fy = ((i * 31.3) % 61) / 61 * 0.62;
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(progress * math.pi * 2 + i * 1.7));
      starPaint.color = p.text.withValues(alpha: 0.55 * twinkle);
      final r = i % 5 == 0 ? 1.6 : 1.0;
      canvas.drawCircle(Offset(fx * size.width, fy * size.height), r, starPaint);
    }

    // Moon with a soft halo, drifting a few pixels over the loop.
    final moonCenter = Offset(size.width * 0.78 + math.sin(progress * math.pi * 2) * 4, size.height * 0.26);
    canvas.drawCircle(moonCenter, 26, Paint()..color = p.text.withValues(alpha: 0.08));
    canvas.drawCircle(moonCenter, 17, Paint()..color = p.text.withValues(alpha: 0.9));
    canvas.drawCircle(moonCenter + const Offset(-6, -4), 13, Paint()..color = p.background.withValues(alpha: 0.18));

    // Three hill layers parallax-drifting at different speeds.
    _hills(canvas, size, base: 0.66, amp: 10, shift: progress * 14, color: p.text.withValues(alpha: 0.10));
    _hills(canvas, size, base: 0.78, amp: 13, shift: -progress * 22, color: p.text.withValues(alpha: 0.16));
    _hills(canvas, size, base: 0.9, amp: 9, shift: progress * 30, color: p.text.withValues(alpha: 0.24));
  }

  void _hills(Canvas canvas, Size size, {required double base, required double amp, required double shift, required Color color}) {
    final path = Path()..moveTo(-4, size.height);
    for (var x = -4.0; x <= size.width + 4; x += 8) {
      final y = size.height * base + math.sin((x + shift) / 57) * amp + math.cos((x + shift) / 31) * amp * 0.4;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width + 4, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NaturePainter old) => old.progress != progress || old.palette != palette;
}
