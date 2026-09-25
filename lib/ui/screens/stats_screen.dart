import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/stats_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<StatsProvider>();
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(s.t('stats'), style: AppTextStyles.title),
          const SizedBox(height: 14),
          _SpeedNowCard(up: stats.upBps, down: stats.downBps),
          const SizedBox(height: 12),
          _ChartCard(samples: stats.samples),
          const SizedBox(height: 12),
          _SessionTimeCard(duration: stats.sessionDuration),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TrafficCard(
                  title: s.t('sessionTraffic'),
                  up: stats.sessionUp,
                  down: stats.sessionDown,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrafficCard(
                  title: s.t('allTimeTraffic'),
                  up: settings.settings.allTimeUp + stats.sessionUp,
                  down: settings.settings.allTimeDown + stats.sessionDown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(s.t('log').toUpperCase(), style: AppTextStyles.section),
              const Spacer(),
              TextButton(onPressed: stats.clearLogs, child: Text(s.t('clear'))),
            ],
          ),
          if (stats.logs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(s.t('logEmpty'), style: AppTextStyles.bodySecondary),
            )
          else
            ...stats.logs.map((entry) {
              final color = switch (entry.status) {
                'connected' => AppColors.success,
                'error' => AppColors.error,
                _ => AppColors.textSecondary,
              };
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.serverName, style: AppTextStyles.bodyRegular),
                subtitle: Text(
                  '${FormatUtils.clock(entry.time)} · ${entry.status}${entry.message == null ? '' : ' · ${entry.message}'}',
                  style: AppTextStyles.bodySecondary,
                ),
                leading: Icon(Icons.circle, size: 10, color: color),
              );
            }),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

/// Live speed, the first thing the eye lands on.
class _SpeedNowCard extends StatelessWidget {
  const _SpeedNowCard({required this.up, required this.down});

  final int up;
  final int down;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('speedNow').toUpperCase(), style: AppTextStyles.section),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SpeedValue(
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.cyan,
                  label: s.t('upload'),
                  value: FormatUtils.speed(up),
                ),
              ),
              Container(width: 1, height: 52, color: Theme.of(context).dividerColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _SpeedValue(
                    icon: Icons.arrow_downward_rounded,
                    color: AppColors.success,
                    label: s.t('trafficDown'),
                    value: FormatUtils.speed(down),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedValue extends StatelessWidget {
  const _SpeedValue({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodySecondary),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.monoValue.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.samples});

  final List samples;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Legend(color: AppColors.cyan, label: s.t('upload')),
              const SizedBox(width: 14),
              _Legend(color: AppColors.success, label: s.t('trafficDown')),
              const Spacer(),
              Flexible(
                child: Text(
                  FormatUtils.speed(_peak(samples, up: true)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySecondary.copyWith(color: AppColors.cyan),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  FormatUtils.speed(_peak(samples, up: false)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySecondary.copyWith(color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: CustomPaint(
              painter: _SpeedChartPainter(samples: samples),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  int _peak(List samples, {required bool up}) {
    var peak = 0;
    for (final sample in samples) {
      final value = (up ? sample.upBps : sample.downBps) as int;
      if (value > peak) peak = value;
    }
    return peak;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.bodySecondary),
      ],
    );
  }
}

class _SessionTimeCard extends StatelessWidget {
  const _SessionTimeCard({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.cyan, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('sessionTime').toUpperCase(), style: AppTextStyles.section),
                const SizedBox(height: 6),
                Text(
                  FormatUtils.duration(duration),
                  style: AppTextStyles.monoValue.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.title,
    required this.up,
    required this.down,
  });

  final String title;
  final int up;
  final int down;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.section),
          const SizedBox(height: 10),
          _TrafficRow(
            icon: Icons.arrow_upward_rounded,
            color: AppColors.cyan,
            value: FormatUtils.bytes(up),
          ),
          const SizedBox(height: 6),
          _TrafficRow(
            icon: Icons.arrow_downward_rounded,
            color: AppColors.success,
            value: FormatUtils.bytes(down),
          ),
        ],
      ),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({
    required this.icon,
    required this.color,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.monoValue.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  _SpeedChartPainter({required this.samples});

  final List samples;

  static const _steps = [
    1024.0,
    4096.0,
    16384.0,
    65536.0,
    262144.0,
    1048576.0,
    4194304.0,
    16777216.0,
    67108864.0,
    268435456.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF141414));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border,
    );

    var maxValue = 1.0;
    for (final sample in samples) {
      final up = (sample.upBps as int).toDouble();
      final down = (sample.downBps as int).toDouble();
      if (up > maxValue) maxValue = up;
      if (down > maxValue) maxValue = down;
    }
    maxValue = _ceiling(maxValue);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.border.withValues(alpha: 0.7);
    for (var i = 1; i < 4; i++) {
      final y = size.height - 10 - i * (size.height - 26) / 4;
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), grid);
    }

    _series(canvas, size, maxValue, AppColors.cyan, (sample) => (sample.upBps as int).toDouble());
    _series(canvas, size, maxValue, AppColors.success, (sample) => (sample.downBps as int).toDouble());
  }

  void _series(
    Canvas canvas,
    Size size,
    double maxValue,
    Color color,
    double Function(dynamic) pick,
  ) {
    if (samples.isEmpty) return;
    final points = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1
          ? size.width / 2
          : i / (samples.length - 1) * (size.width - 16) + 8;
      final y = size.height - 12 - (pick(samples[i]) / maxValue) * (size.height - 28);
      points.add(Offset(x, y));
    }
    final area = Path()..addPolygon(points, false);
    area
      ..lineTo(points.last.dx, size.height - 6)
      ..lineTo(points.first.dx, size.height - 6)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [color.withValues(alpha: 0.32), color.withValues(alpha: 0.02)],
        ),
    );
    canvas.drawPath(
      Path()..addPolygon(points, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  double _ceiling(double value) {
    for (final step in _steps) {
      if (value <= step) return step;
    }
    return value;
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) => true;
}
