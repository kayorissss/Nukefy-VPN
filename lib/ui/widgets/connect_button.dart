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

  Color get _color {
    return switch (widget.status) {
      VpnStatus.connected => AppColors.success,
      VpnStatus.connecting => AppColors.cyan,
      VpnStatus.error => AppColors.error,
      VpnStatus.disconnected => AppColors.border,
    };
  }

  @override
  Widget build(BuildContext context) {
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
            child: SizedBox(
              width: 188,
              height: 188,
              child: CustomPaint(
                painter: _RingPainter(
                  color: _color,
                  spin: _spin.value,
                  glow: glow,
                  connected: widget.status == VpnStatus.connected,
                  connecting: widget.status == VpnStatus.connecting,
                ),
                child: Center(
                  child: Container(
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF141414),
                      border: Border.all(color: _color, width: 1.4),
                      boxShadow: [
                        BoxShadow(
                          color: _color.withValues(alpha: glow * 0.7),
                          blurRadius: 28,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 48,
                      color: widget.status == VpnStatus.disconnected
                          ? AppColors.textSecondary
                          : Colors.white,
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
