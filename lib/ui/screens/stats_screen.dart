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
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _SpeedChartPainter(samples: stats.samples),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _StatCard(title: s.t('statsSession'), up: stats.sessionUp, down: stats.sessionDown, extra: FormatUtils.duration(stats.sessionDuration))),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(title: s.t('statsAll'), up: settings.settings.allTimeUp + stats.sessionUp, down: settings.settings.allTimeDown + stats.sessionDown)),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.up,
    required this.down,
    this.extra,
  });

  final String title;
  final int up;
  final int down;
  final String? extra;

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
          Text(title.toUpperCase(), style: AppTextStyles.section),
          const SizedBox(height: 8),
          Text('↑ ${FormatUtils.bytes(up)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan)),
          Text('↓ ${FormatUtils.bytes(down)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.success)),
          if (extra != null) Text(extra!, style: AppTextStyles.bodySecondary),
          Text('${s.t('sent')} / ${s.t('received')}', style: AppTextStyles.bodySecondary),
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
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF141414));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border,
    );
    if (samples.isEmpty) return;
    var maxValue = 1.0;
    for (final sample in samples) {
      final up = (sample.upBps as int).toDouble();
      final down = (sample.downBps as int).toDouble();
      if (up > maxValue) maxValue = up;
      if (down > maxValue) maxValue = down;
    }
    _line(canvas, size, maxValue, AppColors.cyan, (sample) => (sample.upBps as int).toDouble());
    _line(canvas, size, maxValue, AppColors.success, (sample) => (sample.downBps as int).toDouble());
  }

  void _line(Canvas canvas, Size size, double maxValue, Color color, double Function(dynamic) pick) {
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1 ? size.width / 2 : i / (samples.length - 1) * (size.width - 16) + 8;
      final y = size.height - 12 - (pick(samples[i]) / maxValue) * (size.height - 28);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
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
