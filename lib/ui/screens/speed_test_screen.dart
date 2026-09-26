import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/speed_test_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_background.dart';

/// Built-in speed test: gauge with a live needle, ping/jitter/down/up
/// results and a persisted history of previous runs.
class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> with SingleTickerProviderStateMixin {
  static const _historyKey = 'speed_history';

  bool _running = false;
  SpeedPhase _phase = SpeedPhase.done;
  int _liveBps = 0;
  int? _ping;
  int? _jitter;
  int? _down;
  int? _up;
  String? _error;
  List<SpeedTestResult> _history = const [];

  late final AnimationController _needle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  double _needleFrom = 0;
  double _needleTo = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _needle.dispose();
    super.dispose();
  }

  void _loadHistory() {
    final json = StorageService.instance.readJson(_historyKey);
    final list = (json?['items'] as List?) ?? const [];
    _history = list.whereType<Map>().map((e) => SpeedTestResult.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _saveHistory() async {
    await StorageService.instance.writeJson(_historyKey, {'items': _history.take(30).map((e) => e.toJson()).toList()});
  }

  void _animateNeedle(int bps) {
    _needleFrom = _currentNeedle;
    _needleTo = SpeedTestService.gauge(bps);
    _needle.forward(from: 0);
  }

  double get _currentNeedle => _needleFrom + (_needleTo - _needleFrom) * Curves.easeOutCubic.transform(_needle.value);

  Future<void> _start() async {
    if (_running) return;
    HapticFeedback.mediumImpact();
    final vpn = context.read<VpnProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final viaVpn = vpn.status == VpnStatus.connected;
    // Desktop routes the app itself outside the tunnel; go through the local
    // HTTP proxy when it is on so the number reflects the VPN.
    final proxyPort = viaVpn && !_isMobile && settings.localProxyEnabled ? settings.httpPort : null;
    setState(() {
      _running = true;
      _error = null;
      _phase = SpeedPhase.ping;
      _liveBps = 0;
      _ping = _jitter = _down = _up = null;
    });
    _animateNeedle(0);
    try {
      final result = await SpeedTestService().run(
        httpProxyPort: proxyPort,
        viaVpn: viaVpn,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _phase = progress.phase;
            _liveBps = progress.bps;
            _ping = progress.pingMs ?? _ping;
            _jitter = progress.jitterMs ?? _jitter;
            if (progress.phase == SpeedPhase.download) _lastDownLive = progress.bps;
            if (progress.phase == SpeedPhase.upload && _down == null) _down = _lastDownLive;
          });
          _animateNeedle(progress.bps);
        },
      );
      if (!mounted) return;
      setState(() {
        _down = result.downloadBps;
        _up = result.uploadBps;
        _ping = result.pingMs;
        _jitter = result.jitterMs;
        _history = [result, ..._history].take(30).toList();
      });
      HapticFeedback.lightImpact();
      await _saveHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _phase = SpeedPhase.done;
        });
      }
    }
  }

  int _lastDownLive = 0;

  bool get _isMobile => Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final vpn = context.watch<VpnProvider>();
    final phaseColor = switch (_phase) {
      SpeedPhase.download => p.success,
      SpeedPhase.upload => p.accent,
      _ => p.accent2,
    };
    final phaseLabel = switch (_phase) {
      SpeedPhase.ping => s.t('ping'),
      SpeedPhase.download => s.t('download'),
      SpeedPhase.upload => s.t('upload'),
      SpeedPhase.done => _down == null ? '' : s.t('download'),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(s.t('speedTest')),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              tooltip: s.t('clearHistory'),
              onPressed: _running
                  ? null
                  : () async {
                      setState(() => _history = const []);
                      await _saveHistory();
                    },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: NukefyBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Gauge.
              AnimatedBuilder(
                animation: _needle,
                builder: (context, _) => SizedBox(
                  height: 250,
                  child: CustomPaint(
                    painter: _GaugePainter(
                      value: _currentNeedle,
                      color: phaseColor,
                      track: p.border,
                      text: p.textSecondary,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 34),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _running || _down != null
                                  ? SpeedTestService.mbps(_running ? _liveBps : (_down ?? 0)).toStringAsFixed(_liveBps > 100e6 ? 0 : 1)
                                  : '—',
                              style: AppTextStyles.metric.copyWith(fontSize: 44, color: p.text, height: 1),
                            ),
                            const SizedBox(height: 4),
                            Text('Mbit/s', style: AppTextStyles.metricCaption.copyWith(color: p.textSecondary)),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                phaseLabel.toUpperCase(),
                                key: ValueKey(phaseLabel),
                                style: AppTextStyles.tab.copyWith(fontSize: 10, color: phaseColor, letterSpacing: 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Four metrics.
              Row(
                children: [
                  _Metric(label: s.t('ping'), value: _ping == null ? '—' : '$_ping', unit: 'ms', color: p.accent2),
                  _Metric(label: s.t('jitter'), value: _jitter == null ? '—' : '$_jitter', unit: 'ms', color: p.accent2),
                  _Metric(label: s.t('download'), value: _down == null ? '—' : SpeedTestService.mbps(_down!).toStringAsFixed(1), unit: 'Mbit/s', color: p.success),
                  _Metric(label: s.t('upload'), value: _up == null ? '—' : SpeedTestService.mbps(_up!).toStringAsFixed(1), unit: 'Mbit/s', color: p.accent),
                ],
              ),
              const SizedBox(height: 18),
              // Start button.
              Center(
                child: GestureDetector(
                  onTap: _running ? null : _start,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: LinearGradient(colors: _running ? [p.surface, p.surface] : [p.accent, p.accent2]),
                      boxShadow: _running ? null : [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_running)
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                        else
                          Icon(Icons.play_arrow_rounded, color: p.isDark ? const Color(0xFF07131A) : Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          (_running ? s.t('speedTesting') : s.t('speedTestStart')).toUpperCase(),
                          style: AppTextStyles.tab.copyWith(
                            fontSize: 12,
                            letterSpacing: 1.5,
                            color: _running ? p.textSecondary : (p.isDark ? const Color(0xFF07131A) : Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  vpn.status == VpnStatus.connected ? '${s.t('viaVpn')} · ${vpn.activeServer?.name ?? ''}' : s.t('direct'),
                  style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Center(child: Text(_error!, style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error))),
              ],
              const SizedBox(height: 26),
              Text(s.t('speedTestHistory').toUpperCase(), style: AppTextStyles.section.copyWith(color: p.textSecondary)),
              const SizedBox(height: 10),
              if (_history.isEmpty)
                Text(s.t('noHistory'), style: AppTextStyles.bodySecondary.copyWith(color: p.textDisabled))
              else
                for (final item in _history) _HistoryRow(item: item, strings: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit, required this.color});
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: p.isDark ? 0.85 : 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        child: Column(
          children: [
            Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.tab.copyWith(fontSize: 8.5, color: p.textSecondary, letterSpacing: 1)),
            const SizedBox(height: 6),
            FittedBox(child: Text(value, style: AppTextStyles.metric.copyWith(fontSize: 18, color: color))),
            Text(unit, style: AppTextStyles.metricCaption.copyWith(fontSize: 9, color: p.textDisabled)),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.strings});
  final SpeedTestResult item;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final when = FormatUtils.timeAgo(item.at, ru: strings.code == 'ru');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: p.isDark ? 0.85 : 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(item.viaVpn ? Icons.vpn_lock_rounded : Icons.public_rounded, size: 18, color: item.viaVpn ? p.accent : p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 14, color: p.success),
                    Text(' ${SpeedTestService.mbps(item.downloadBps).toStringAsFixed(1)}', style: AppTextStyles.metric.copyWith(fontSize: 14, color: p.text)),
                    const SizedBox(width: 12),
                    Icon(Icons.arrow_upward_rounded, size: 14, color: p.accent),
                    Text(' ${SpeedTestService.mbps(item.uploadBps).toStringAsFixed(1)}', style: AppTextStyles.metric.copyWith(fontSize: 14, color: p.text)),
                    const SizedBox(width: 12),
                    Text('${item.pingMs} ms', style: AppTextStyles.metric.copyWith(fontSize: 13, color: p.accent2)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$when · ${item.viaVpn ? strings.t('viaVpn') : strings.t('direct')} · ${strings.t('jitter').toLowerCase()} ${item.jitterMs} ms',
                  style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 240° arc with ticks and a glowing progress sweep.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, required this.track, required this.text});
  final double value;
  final Color color;
  final Color track;
  final Color text;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 14);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, _start, _sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = track);

    if (value > 0) {
      final sweep = _sweep * value;
      canvas.drawArc(rect, _start, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
        ..color = color.withValues(alpha: 0.45));
      canvas.drawArc(rect, _start, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [color.withValues(alpha: 0.5), color],
        ).createShader(rect));
    }

    // Ticks: 0, 1, 5, 10, 50, 100, 500, 1000 Mbit on the log scale.
    final tickPaint = Paint()
      ..color = text.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final m in const [0, 1, 5, 10, 50, 100, 500, 1000]) {
      final t = SpeedTestService.gauge((m * 1e6 / 8).round());
      final a = _start + _sweep * t;
      final inner = Offset(center.dx + (radius - 20) * math.cos(a), center.dy + (radius - 20) * math.sin(a));
      final outer = Offset(center.dx + (radius - 26) * math.cos(a), center.dy + (radius - 26) * math.sin(a));
      canvas.drawLine(inner, outer, tickPaint);
      final tp = TextPainter(
        text: TextSpan(text: '$m', style: TextStyle(fontSize: 9, color: text, fontFamily: 'Unbounded')),
        textDirection: TextDirection.ltr,
      )..layout();
      final lp = Offset(center.dx + (radius - 40) * math.cos(a) - tp.width / 2, center.dy + (radius - 40) * math.sin(a) - tp.height / 2);
      tp.paint(canvas, lp);
    }

    // Needle dot.
    final a = _start + _sweep * value;
    final dot = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
    canvas.drawCircle(dot, 9, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawCircle(dot, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value || old.color != color;
}
