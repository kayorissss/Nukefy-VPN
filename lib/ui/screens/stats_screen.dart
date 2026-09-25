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
          // Current speed, large.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SpeedNow(
                    icon: Icons.arrow_downward_rounded,
                    caption: s.t('trafficDown'),
                    value: FormatUtils.speed(stats.downBps),
                    color: AppColors.success,
                  ),
                ),
                Container(
                  width: 1,
                  height: 62,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(
                  child: _SpeedNow(
                    icon: Icons.arrow_upward_rounded,
                    caption: s.t('upload'),
                    value: FormatUtils.speed(stats.upBps),
                    color: AppColors.cyan,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Big traffic chart.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Legend(color: AppColors.success, label: s.t('trafficDown')),
                    const SizedBox(width: 14),
                    _Legend(color: AppColors.cyan, label: s.t('upload')),
                    const Spacer(),
                    Text(s.t('statsNow'), style: AppTextStyles.metricCaption),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SpeedChartPainter(samples: stats.samples),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Session time.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('statsSessionTime').toUpperCase(), style: AppTextStyles.metricCaption),
                const SizedBox(height: 8),
                Text(
                  FormatUtils.duration(stats.sessionDuration),
                  style: AppTextStyles.metric.copyWith(
                    fontFamily: AppTextStyles.mono,
                    fontSize: 34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TrafficCard(
                  title: s.t('statsSessionTraffic'),
                  up: stats.sessionUp,
                  down: stats.sessionDown,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrafficCard(
                  title: s.t('statsAllTime'),
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

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.bodySecondary),
      ],
    );
  }
}

class _SpeedNow extends StatelessWidget {
  const _SpeedNow({
    required this.icon,
    required this.caption,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String caption;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              caption.toUpperCase(),
              style: AppTextStyles.metricCaption.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          child: Text(
            value,
            style: AppTextStyles.metric.copyWith(color: color),
          ),
        ),
      ],
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
    final s = context.watch<SettingsProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.metricCaption),
          const SizedBox(height: 10),
          Text(
            '↓ ${FormatUtils.bytes(down)}',
            style: AppTextStyles.monoValue.copyWith(color: AppColors.success, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '↑ ${FormatUtils.bytes(up)}',
            style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text('${s.t('received')} / ${s.t('sent')}', style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  _SpeedChartPainter({required this.samples});
  final List samples;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF141414));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border,
    );

    final baseline = size.height - 14.0;
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = baseline - (size.height - 34) * i / 4;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), grid);
    }

    if (samples.isEmpty) return;
    var maxValue = 1.0;
    for (final sample in samples) {
      final up = (sample.upBps as int).toDouble();
      final down = (sample.downBps as int).toDouble();
      if (up > maxValue) maxValue = up;
      if (down > maxValue) maxValue = down;
    }

    final download = Path.from(_line(size, maxValue, (sample) => (sample.downBps as int).toDouble()));
    download
      ..lineTo(size.width - 8, baseline)
      ..lineTo(8, baseline)
      ..close();
    canvas.drawPath(download, Paint()..color = AppColors.success.withValues(alpha: 0.14));

    _stroke(canvas, size, maxValue, AppColors.success, (sample) => (sample.downBps as int).toDouble());
    _stroke(canvas, size, maxValue, AppColors.cyan, (sample) => (sample.upBps as int).toDouble());
  }

  Path _line(Size size, double maxValue, double Function(dynamic) pick) {
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1 ? size.width / 2 : i / (samples.length - 1) * (size.width - 16) + 8;
      final y = size.height - 14 - (pick(samples[i]) / maxValue) * (size.height - 34);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  void _stroke(
    Canvas canvas,
    Size size,
    double maxValue,
    Color color,
    double Function(dynamic) pick,
  ) {
    canvas.drawPath(
      _line(size, maxValue, pick),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) => true;
}
