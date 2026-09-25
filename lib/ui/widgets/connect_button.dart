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
    final off = widget.status == VpnStatus.disconnected;
    final busy = widget.status == VpnStatus.connecting;
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _pulse, _shake]),
      builder: (context, _) {
        final shake = math.sin(_shake.value * math.pi * 6) * (1 - _shake.value) * 8;
        final glow = off ? 0.0 : 0.35 + _pulse.value * 0.45;
        // Disc gradient: brand gradient when on, quiet graphite when off.
        final discColors = switch (widget.status) {
          VpnStatus.connected => [p.success, const Color(0xFF0FA3B1)],
          VpnStatus.connecting => [p.accent, AppColors.violet],
          VpnStatus.error => [AppColors.error, const Color(0xFFB0244A)],
          VpnStatus.disconnected => p.isDark
              ? const [Color(0xFF232A36), Color(0xFF12161E)]
              : const [Color(0xFFFFFFFF), Color(0xFFE3E8F0)],
        };
        return Transform.translate(
          offset: Offset(shake, 0),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: busy ? 0.97 : 1,
              child: SizedBox(
                width: 212,
                height: 212,
                child: CustomPaint(
                  painter: _RingPainter(
                    color: off ? p.border : color,
                    spin: _spin.value,
                    glow: glow,
                    connected: widget.status == VpnStatus.connected,
                    connecting: busy,
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: discColors,
                        ),
                        border: Border.all(
                          color: off ? p.border : Colors.white.withValues(alpha: 0.18),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: off ? 0 : glow * 0.55),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.10),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Inner highlight for depth.
                          Container(
                            margin: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.4, -0.5),
                                radius: 1,
                                colors: [
                                  Colors.white.withValues(alpha: off ? 0.04 : 0.22),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOutBack,
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              key: ValueKey(off),
                              size: 60,
                              color: off ? p.textSecondary : (p.isDark ? const Color(0xFF07131A) : Colors.white),
                            ),
                          ),
                        ],
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
    final radius = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: connected || connecting ? 0.22 : 0.6),
    );
    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..color = color.withValues(alpha: glow * 0.5),
      );
    }
    if (connected) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = color,
      );
    }
    if (connecting) {
      // Two chasing arcs.
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color;
      for (var i = 0; i < 2; i++) {
        canvas.drawArc(rect, spin * math.pi * 2 + i * math.pi, 1.2, false, arc);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => true;
}
