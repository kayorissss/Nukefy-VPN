import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/vpn_status.dart';
import '../../core/theme/app_colors.dart';

class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.onPressed,
  });

  final VpnStatus status;
  final VoidCallback onPressed;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _sync();
      if (widget.status == VpnStatus.error) {
        HapticFeedback.vibrate();
        _shake.forward(from: 0);
      } else if (widget.status == VpnStatus.connected) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _sync() {
    switch (widget.status) {
      case VpnStatus.connecting:
        _spin.repeat();
        _pulse.repeat(reverse: true);
      case VpnStatus.connected:
        _spin.stop();
        _pulse.repeat(reverse: true);
      case VpnStatus.disconnected:
      case VpnStatus.error:
        _spin.stop();
        _pulse.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  Color _colorOf(NukefyPalette p) {
    return switch (widget.status) {
      VpnStatus.connected => p.success,
      VpnStatus.connecting => p.accent,
      VpnStatus.error => AppColors.error,
      VpnStatus.disconnected => p.isDark ? const Color(0xFF3A4352) : const Color(0xFFB8C0CC),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = _colorOf(p);
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _pulse, _shake]),
      builder: (context, _) {
        final shake = math.sin(_shake.value * math.pi * 6) * (1 - _shake.value) * 8;
        final glow = widget.status == VpnStatus.disconnected
            ? 0.0
            : 0.35 + _pulse.value * 0.45;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: widget.status == VpnStatus.connecting ? 0.97 : 1,
              child: SizedBox(
              width: 188,
              height: 188,
              child: CustomPaint(
                painter: _RingPainter(
                  color: color,
                  spin: _spin.value,
                  glow: glow,
                  connected: widget.status == VpnStatus.connected,
                  connecting: widget.status == VpnStatus.connecting,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: p.isDark
                            ? const [Color(0xFF171C25), Color(0xFF0E1218)]
                            : const [Colors.white, Color(0xFFE9EDF3)],
                      ),
                      border: Border.all(color: color, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: glow * 0.7),
                          blurRadius: 30,
                          spreadRadius: 1,
                        ),
                        if (!p.isDark)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        key: ValueKey(widget.status == VpnStatus.disconnected),
                        size: 48,
                        color: widget.status == VpnStatus.disconnected ? p.textSecondary : color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.color,
    required this.spin,
    required this.glow,
    required this.connected,
    required this.connecting,
  });

  final Color color;
  final double spin;
  final double glow;
  final bool connected;
  final bool connecting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: connecting || connected ? 0.55 : 0.35);
    canvas.drawCircle(center, radius, base);
    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..color = color.withValues(alpha: glow * 0.55),
      );
    }
    if (connecting) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        spin * math.pi * 2,
        1.4,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => true;
}
