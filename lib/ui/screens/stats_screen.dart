import '../widgets/nukefy_feedback.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/stats_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _logPage = 0;

  Future<void> _clearLogs() async {
    final s = context.read<SettingsProvider>().strings;
    final confirmed = await confirmDialog(
      context,
      title: s.t('clear'),
      body: s.t('clearStatsBody'),
      confirm: s.t('clear'),
      cancel: s.t('cancel'),
    );
    if (!confirmed || !mounted) return;
    context.read<StatsProvider>().clearLogs();
    setState(() => _logPage = 0);
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<StatsProvider>();
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final totalUp = settings.settings.allTimeUp + stats.sessionUp;
    final totalDown = settings.settings.allTimeDown + stats.sessionDown;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 900
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child:
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: Theme.of(context).dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(s.t('statsSessionTime').toUpperCase(), style: context.palette.captionStyle),
                                            const SizedBox(height: 8),
                                            Text(FormatUtils.duration(stats.sessionDuration), style: AppTextStyles.metric.copyWith(fontFamily: AppTextStyles.mono, fontSize: 30)),
                                          ],
                                        ),
                                      ),
                                      Container(width: 1, height: 58, color: Theme.of(context).dividerColor),
                                      Expanded(child: _SpeedNow(icon: Icons.arrow_downward_rounded, caption: s.t('trafficDown'), value: FormatUtils.speed(stats.downBps), color: p.success)),
                                      Expanded(child: _SpeedNow(icon: Icons.arrow_upward_rounded, caption: s.t('upload'), value: FormatUtils.speed(stats.upBps), color: p.accent)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Divider(height: 1, color: p.border),
                                  const SizedBox(height: 10),
                                  Text(s.t('allTraffic').toUpperCase(), style: p.captionStyle),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Expanded(child: _TrafficTotal(icon: Icons.arrow_downward_rounded, label: s.t('trafficDown'), value: FormatUtils.bytes(totalDown), color: p.success)),
                                      const SizedBox(width: 10),
                                      Expanded(child: _TrafficTotal(icon: Icons.arrow_upward_rounded, label: s.t('upload'), value: FormatUtils.bytes(totalUp), color: p.accent)),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child:
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: Theme.of(context).dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _Legend(color: p.success, label: s.t('trafficDown')),
                                      const SizedBox(width: 14),
                                      _Legend(color: p.accent, label: s.t('upload')),
                                      const Spacer(),
                                      Text(s.t('statsNow'), style: context.palette.captionStyle),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 240,
                                    width: double.infinity,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CustomPaint(
                                          painter: _SpeedChartPainter(samples: stats.samples, palette: context.palette),
                                        ),
                                        if (stats.samples.isEmpty)
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.monitor_heart_outlined, size: 30, color: p.textSecondary),
                                                  const SizedBox(height: 10),
                                                  Text(s.t('statsNoTraffic'), textAlign: TextAlign.center, style: p.secondaryStyle),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.t('statsSessionTime').toUpperCase(), style: context.palette.captionStyle),
                                        const SizedBox(height: 8),
                                        Text(FormatUtils.duration(stats.sessionDuration), style: AppTextStyles.metric.copyWith(fontFamily: AppTextStyles.mono, fontSize: 30)),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1, height: 58, color: Theme.of(context).dividerColor),
                                  Expanded(child: _SpeedNow(icon: Icons.arrow_downward_rounded, caption: s.t('trafficDown'), value: FormatUtils.speed(stats.downBps), color: p.success)),
                                  Expanded(child: _SpeedNow(icon: Icons.arrow_upward_rounded, caption: s.t('upload'), value: FormatUtils.speed(stats.upBps), color: p.accent)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Divider(height: 1, color: p.border),
                              const SizedBox(height: 10),
                              Text(s.t('allTraffic').toUpperCase(), style: p.captionStyle),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Expanded(child: _TrafficTotal(icon: Icons.arrow_downward_rounded, label: s.t('trafficDown'), value: FormatUtils.bytes(totalDown), color: p.success)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _TrafficTotal(icon: Icons.arrow_upward_rounded, label: s.t('upload'), value: FormatUtils.bytes(totalUp), color: p.accent)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _Legend(color: p.success, label: s.t('trafficDown')),
                                  const SizedBox(width: 14),
                                  _Legend(color: p.accent, label: s.t('upload')),
                                  const Spacer(),
                                  Text(s.t('statsNow'), style: context.palette.captionStyle),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 240,
                                width: double.infinity,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: _SpeedChartPainter(samples: stats.samples, palette: context.palette),
                                    ),
                                    if (stats.samples.isEmpty)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.monitor_heart_outlined, size: 30, color: p.textSecondary),
                                              const SizedBox(height: 10),
                                              Text(s.t('statsNoTraffic'), textAlign: TextAlign.center, style: p.secondaryStyle),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            // The journal is one full-width block: header line with the
            // clear action, then the entries stretched edge to edge.
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(s.t('log').toUpperCase(), style: context.palette.sectionStyle),
                      const Spacer(),
                      TextButton(onPressed: _clearLogs, child: Text(s.t('clear'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (stats.logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(s.t('logEmpty'), style: context.palette.secondaryStyle),
                    )
                  else ...[
                    Builder(
                      builder: (context) {
                        const pageSize = 8;
                        final newestFirst = stats.logs.reversed.toList(growable: false);
                        final pageCount = (newestFirst.length / pageSize).ceil();
                        final page = _logPage.clamp(0, pageCount - 1);
                        final entries = newestFirst.skip(page * pageSize).take(pageSize);
                        return Column(
                          children: [
                            for (final entry in entries)
                              _JournalLine(entry: entry, palette: p),
                            if (pageCount > 1)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(onPressed: page > 0 ? () => setState(() => _logPage = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                                  Text('${page + 1} / $pageCount', style: context.palette.captionStyle),
                                  IconButton(onPressed: page + 1 < pageCount ? () => setState(() => _logPage = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalLine extends StatelessWidget {
  const _JournalLine({required this.entry, required this.palette});

  final dynamic entry;
  final NukefyPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.status) {
      'connected' => palette.success,
      'error' => AppColors.error,
      _ => palette.textSecondary,
    };
    final message = entry.message == null ? '' : ' · ${entry.message}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: palette.border)),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 9),
            Expanded(child: Text('${FormatUtils.clock(entry.time)} · ${entry.serverName} · ${entry.status}$message', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySecondary.copyWith(color: palette.textSecondary))),
          ],
        ),
      ),
    );
  }
}

class _TrafficTotal extends StatelessWidget {
  const _TrafficTotal({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.captionStyle.copyWith(fontSize: 9))),
          const SizedBox(width: 6),
          Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: color))),
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
        Text(label, style: context.palette.secondaryStyle),
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

class _SpeedChartPainter extends CustomPainter {
  _SpeedChartPainter({required this.samples, required this.palette});
  final List samples;
  final NukefyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(rect, Paint()..color = palette.surface);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = palette.border,
    );

    final baseline = size.height - 14.0;
    final grid = Paint()
      ..color = palette.border.withValues(alpha: 0.6)
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
    canvas.drawPath(download, Paint()..color = palette.success.withValues(alpha: 0.14));

    _stroke(canvas, size, maxValue, palette.success, (sample) => (sample.downBps as int).toDouble());
    _stroke(canvas, size, maxValue, palette.accent, (sample) => (sample.upBps as int).toDouble());
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
