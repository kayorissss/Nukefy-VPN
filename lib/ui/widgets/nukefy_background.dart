import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class NukefyBackground extends StatefulWidget {
  const NukefyBackground({super.key, required this.child});

  final Widget child;

  @override
  State<NukefyBackground> createState() => _NukefyBackgroundState();
}

class _NukefyBackgroundState extends State<NukefyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _GridPainter(progress: _controller.value, dark: dark),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.progress, required this.dark});

  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = dark ? AppColors.background : AppColors.lightBackground;
    canvas.drawRect(Offset.zero & size, bg);
    final grid = Paint()
      ..color = (dark ? AppColors.cyan : AppColors.violet).withValues(alpha: dark ? 0.035 : 0.05)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final t = progress * math.pi * 2;
    _orb(canvas, size, Offset(size.width * (0.82 + math.sin(t) * 0.04), size.height * 0.12), AppColors.cyan, 180);
    _orb(canvas, size, Offset(size.width * (0.1 + math.cos(t) * 0.03), size.height * 0.78), AppColors.violet, 220);
  }

  void _orb(Canvas canvas, Size size, Offset center, Color color, double radius) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.dark != dark;
}
