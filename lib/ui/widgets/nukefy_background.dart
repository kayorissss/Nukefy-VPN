import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Soft animated gradient orbs behind every screen. No grid, no crosses —
/// just the palette background with two slowly drifting glows.
class NukefyBackground extends StatefulWidget {
  const NukefyBackground({super.key, required this.child});

  final Widget child;

  @override
  State<NukefyBackground> createState() => _NukefyBackgroundState();
}

class _NukefyBackgroundState extends State<NukefyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _OrbsPainter(progress: _controller.value, palette: p),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.progress, required this.palette});

  final double progress;
  final NukefyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    final t = progress * 2 * math.pi;
    final dark = palette.isDark;
    final r = math.max(size.width, size.height) * 0.42;
    _orb(
      canvas,
      Offset(size.width * (0.22 + 0.10 * math.sin(t)), size.height * (0.18 + 0.06 * math.cos(t * 0.8))),
      r,
      palette.accent.withValues(alpha: dark ? 0.16 : 0.14),
    );
    _orb(
      canvas,
      Offset(size.width * (0.82 - 0.08 * math.cos(t * 0.9)), size.height * (0.78 + 0.07 * math.sin(t * 0.7))),
      r * 0.9,
      palette.accent2.withValues(alpha: dark ? 0.14 : 0.12),
    );
  }

  void _orb(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbsPainter old) => old.progress != progress || old.palette != palette;
}
