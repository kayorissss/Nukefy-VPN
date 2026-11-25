import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'world_map_data.dart';

/// The dotted world map that sits behind the home screen.
///
/// The land mask is a rasterised copy of Natural Earth's 1:110m land outline
/// (see `world_map_data.dart`), drawn as one small dot per land cell: cheap,
/// pixel-crisp at any size and free of image assets. When the active server
/// changes the camera glides towards that country and a single ring expands
/// from it — one animation, then everything stops. Nothing here pulses on a
/// timer: an always-running animation would eat exactly the CPU this update
/// was asked to save.
class WorldMapBackdrop extends StatefulWidget {
  const WorldMapBackdrop({
    super.key,
    this.countryCode,
    this.connected = false,
  });

  /// ISO-3166 alpha-2 code of the server in use, if known.
  final String? countryCode;

  /// Connected servers get a brighter marker; a dial that is only selected
  /// still shows where it is, just quietly.
  final bool connected;

  @override
  State<WorldMapBackdrop> createState() => _WorldMapBackdropState();
}

class _WorldMapBackdropState extends State<WorldMapBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _camera = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    // First frame: no flight, just let the marker arrive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ring.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant WorldMapBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countryCode != widget.countryCode) {
      _camera.forward(from: 0);
      _ring.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final latLon = widget.countryCode == null
        ? null
        : kCountryCentroids[widget.countryCode!.toUpperCase()];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_camera, _ring]),
        builder: (context, _) => CustomPaint(
          painter: _WorldMapPainter(
            progress: _camera.value,
            pulse: _ring.value,
            dark: p.isDark,
            dotColor: p.text,
            accent: p.accent,
            success: p.success,
            country: latLon,
            connected: widget.connected,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  _WorldMapPainter({
    required this.progress,
    required this.pulse,
    required this.dark,
    required this.dotColor,
    required this.accent,
    required this.success,
    required this.country,
    required this.connected,
  });

  final double progress;
  final double pulse;
  final bool dark;
  final Color dotColor;
  final Color accent;
  final Color success;
  final (double, double)? country;
  final bool connected;

  /// Device position of every land dot, cached between frames of one size.
  static List<Offset> _dots = const [];
  static double _dotCell = 0;
  static Size _dotSize = Size.zero;

  static Offset _toDevice(double lat, double lon, double cell, Size size) {
    final col = (lon - kWorldMapLonMin) / (kWorldMapLonMax - kWorldMapLonMin) * kWorldMapColumns;
    final row = (kWorldMapLatTop - lat) / (kWorldMapLatTop - kWorldMapLatBottom) * kWorldMapRows;
    final origin = Offset((size.width - kWorldMapColumns * cell) / 2, (size.height - kWorldMapRows * cell) / 2);
    return origin + Offset(col * cell + cell / 2, row * cell + cell / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cell = math.min(size.width / kWorldMapColumns, size.height / kWorldMapRows);
    if (cell <= 0) return;
    if (_dots.isEmpty || _dotSize != size || _dotCell != cell) {
      _rebuildDots(cell, size);
    }

    // Camera: p' = p * s + t, where s grows 1 → zoom and t keeps the chosen
    // country drifting towards the upper middle of the canvas.
    const zoom = 2.7;
    final anchor = Offset(size.width / 2, size.height * 0.42);
    // Local, because a field never promotes: `country.$1` needs a non-null
    // receiver that the compiler can actually prove.
    final point = country;
    final focal = point == null ? null : _toDevice(point.$1, point.$2, cell, size);
    final t = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));
    final active = focal == null ? 0.0 : t;
    final s = 1 + active * (zoom - 1);
    final tx = focal == null ? 0.0 : active * (anchor.dx - focal.dx - focal.dx * (zoom - 1));
    final ty = focal == null ? 0.0 : active * (anchor.dy - focal.dy - focal.dy * (zoom - 1));

    // Land dots. Two passes: the whole world faintly, then everything near
    // the marker a little brighter, so the eye goes to the right place.
    final base = Paint()
      ..color = dotColor.withValues(alpha: dark ? 0.16 : 0.22)
      ..isAntiAlias = true;
    final near = Paint()
      ..color = accent.withValues(alpha: dark ? 0.42 : 0.34)
      ..isAntiAlias = true;
    final r = math.max(0.7, cell * 0.30);
    final glowRadius = focal == null ? 0.0 : cell * 9;
    for (final dot in _dots) {
      final x = dot.dx * s + tx;
      final y = dot.dy * s + ty;
      if (x < -cell || y < -cell || x > size.width + cell || y > size.height + cell) continue;
      final isNear = focal != null &&
          (dot - focal).distance < glowRadius &&
          (dot - focal).distance > 0;
      canvas.drawCircle(Offset(x, y), r * (isNear ? 1.25 : 1), isNear ? near : base);
    }

    if (focal == null) return;
    final center = Offset(focal.dx * s + tx, focal.dy * s + ty);
    final marker = connected ? success : accent;

    // Resting glow: one radial gradient, no blur filter.
    final glow = Rect.fromCircle(center: center, radius: cell * (connected ? 7 : 5));
    canvas.drawCircle(
      center,
      cell * (connected ? 7 : 5),
      Paint()
        ..shader = RadialGradient(
          colors: [
            marker.withValues(alpha: connected ? 0.30 : 0.18),
            marker.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );

    // One expanding ring per change of country, then it stops.
    if (pulse < 1) {
      final e = Curves.easeOutCubic.transform(pulse);
      canvas.drawCircle(
        center,
        cell * 1.6 + e * cell * 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = marker.withValues(alpha: (1 - e) * 0.55),
      );
    }

    canvas.drawCircle(
      center,
      cell * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, marker],
        ).createShader(Rect.fromCircle(center: center, radius: cell * 1.5)),
    );
  }

  void _rebuildDots(double cell, Size size) {
    final dots = <Offset>[];
    for (var row = 0; row < kWorldMapRows; row++) {
      final line = row * kWorldMapColumns;
      for (var col = 0; col < kWorldMapColumns; col++) {
        if (kWorldMapMask.codeUnitAt(line + col) != 0x23) continue; // '#'
        dots.add(_toDevice(
          kWorldMapLatTop - (row + 0.5) / kWorldMapRows * (kWorldMapLatTop - kWorldMapLatBottom),
          kWorldMapLonMin + (col + 0.5) / kWorldMapColumns * (kWorldMapLonMax - kWorldMapLonMin),
          cell,
          size,
        ));
      }
    }
    _dots = dots;
    _dotCell = cell;
    _dotSize = size;
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter old) =>
      old.progress != progress ||
      old.pulse != pulse ||
      old.country != country ||
      old.connected != connected ||
      old.dark != dark ||
      old.dotColor != dotColor ||
      old.accent != accent ||
      old.success != success;
}
