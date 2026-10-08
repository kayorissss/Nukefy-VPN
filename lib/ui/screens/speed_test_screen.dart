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
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';
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
  bool _historyOpen = false;
  SpeedPhase _phase = SpeedPhase.done;
  int _liveBps = 0;
  int? _ping;
  int? _jitter;
  int? _down;
  int? _up;
  String? _server;
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
      _server = null;
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
            if (progress.phase == SpeedPhase.download) {
              _down = progress.bps;
            } else if (progress.phase == SpeedPhase.upload && progress.bps > 0) {
              _up = progress.bps;
            }
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
        _server = result.server;
        _history = [result, ..._history].take(30).toList();
      });
      HapticFeedback.lightImpact();
      await _saveHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _phase = SpeedPhase.done;
          _liveBps = 0;
        });
      }
    }
  }

  /// Turns a failure into a sentence. Raw Dio text never reaches the screen.
  String _errorText(Object error) {
    if (error is SpeedTestException) {
      return switch (error.code) {
        'blocked' => _s.t('speedBlocked'),
        'server-error' => _s.t('speedServerError'),
        'timeout' => _s.t('speedTimeout'),
        _ => _s.t('speedNoConnection'),
      };
    }
    return _s.t('speedNoConnection');
  }

  S get _s => context.read<SettingsProvider>().strings;

  bool get _isMobile => Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final vpn = context.watch<VpnProvider>();
    final phaseColor = switch (_phase) {
      SpeedPhase.download => p.success,
      SpeedPhase.upload => p.accent,
      _ => p.textSecondary,
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
          child: ResponsiveFrame(
            maxWidth: 1200,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // One hero card: the dial on the left, the four numbers on the
                // right. The old layout glued a bare gauge, a flat row of
                // boxes and a pill button on top of each other.
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: p.card.withValues(alpha: p.isDark ? .78 : .96),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: phaseColor.withValues(alpha: .35)),
                    boxShadow: [
                      BoxShadow(color: phaseColor.withValues(alpha: p.isDark ? .10 : .05), blurRadius: 34, offset: const Offset(0, 14)),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide = box.maxWidth > 720;
                      final dial = SizedBox(
                        width: 268,
                        height: 268,
                        child: AnimatedBuilder(
                          animation: _needle,
                          builder: (context, _) => CustomPaint(
                            painter: _GaugePainter(
                              value: _currentNeedle,
                              color: phaseColor,
                              track: p.border,
                              text: p.textSecondary,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _running || _down != null
                                        ? SpeedTestService.mbps(_running ? _liveBps : (_down ?? 0))
                                            .toStringAsFixed(_liveBps > 100e6 ? 0 : 1)
                                        : '—',
                                    style: AppTextStyles.metric.copyWith(fontSize: 46, color: p.text, height: 1),
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Mbit/s', style: AppTextStyles.metricCaption.copyWith(color: p.textSecondary)),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Container(
                                      key: ValueKey(phaseLabel),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: phaseColor.withValues(alpha: .14),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        phaseLabel.toUpperCase(),
                                        style: AppTextStyles.tab.copyWith(fontSize: 9.5, color: phaseColor, letterSpacing: 1.6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      final tiles = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            _Metric(icon: Icons.speed_rounded, label: s.t('ping'), value: _ping == null ? '—' : '$_ping', unit: 'ms', color: p.textSecondary),
                            _Metric(icon: Icons.timeline_rounded, label: s.t('jitter'), value: _jitter == null ? '—' : '$_jitter', unit: 'ms', color: p.textSecondary),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            _Metric(icon: Icons.download_rounded, label: s.t('download'), value: _down == null ? '—' : SpeedTestService.mbps(_down!).toStringAsFixed(1), unit: 'Mbit/s', color: p.success),
                            _Metric(icon: Icons.upload_rounded, label: s.t('upload'), value: _up == null ? '—' : SpeedTestService.mbps(_up!).toStringAsFixed(1), unit: 'Mbit/s', color: p.accent),
                          ]),
                        ],
                      );
                      if (!wide) {
                        return Column(children: [Center(child: dial), const SizedBox(height: 16), tiles]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          dial,
                          const SizedBox(width: 22),
                          Expanded(child: tiles),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Run button: a wide, obvious call to action with the target
                // server right under it.
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _running ? null : _start,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(colors: _running ? [p.surface, p.surface] : [p.accent, p.accent2]),
                            boxShadow: _running ? null : [BoxShadow(color: p.accent.withValues(alpha: .30), blurRadius: 22, offset: const Offset(0, 8))],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_running)
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                              else
                                Icon(Icons.speed_rounded, color: p.isDark ? Colors.black : Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                (_running ? s.t('speedTesting') : s.t('speedTestStart')).toUpperCase(),
                                style: AppTextStyles.tab.copyWith(
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                  color: _running ? p.textSecondary : (p.isDark ? Colors.black : Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.card.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(vpn.status == VpnStatus.connected ? Icons.vpn_lock_rounded : Icons.public_rounded,
                              size: 16, color: vpn.status == VpnStatus.connected ? p.success : p.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            vpn.status == VpnStatus.connected && (vpn.activeServer?.name ?? '').isNotEmpty
                                ? vpn.activeServer!.name
                                : s.t('noServerShort'),
                            style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_server != null) ...[
                  const SizedBox(height: 8),
                  Text('${s.t('speedServer')}: $_server',
                      style: AppTextStyles.bodySecondary.copyWith(color: p.textDisabled, fontSize: 11.5)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  CopyableError(message: _error!, strings: s),
                ],
                const SizedBox(height: 22),
                // History: a card with its own header, a count and a pill that
                // unfolds the list. Nothing else on the page grows with the
                // number of past runs.
                Container(
                  decoration: BoxDecoration(
                    color: p.card.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _history.isEmpty ? null : () => setState(() => _historyOpen = !_historyOpen),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded, size: 18, color: p.textSecondary),
                              const SizedBox(width: 10),
                              Text(s.t('speedTestHistory').toUpperCase(), style: AppTextStyles.section.copyWith(color: p.textSecondary)),
                              const SizedBox(width: 8),
                              if (_history.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: p.accent.withValues(alpha: .14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('${_history.length}',
                                      style: AppTextStyles.tab.copyWith(fontSize: 10, color: p.accent)),
                                ),
                              const Spacer(),
                              if (_history.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(s.t(_historyOpen ? 'collapse' : 'expand'),
                                        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12, color: p.textSecondary)),
                                    AnimatedRotation(
                                      turns: _historyOpen ? .5 : 0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Icon(Icons.expand_more_rounded, size: 20, color: p.textSecondary),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(s.t('noHistory'), style: AppTextStyles.bodySecondary.copyWith(color: p.textDisabled)),
                          ),
                        )
                      else
                        // Clip so the rows cannot paint outside the rounded card
                        // while they slide open.
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _historyOpen
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                                    child: Column(
                                      children: [
                                        for (var i = 0; i < _history.length; i++)
                                          _HistoryRow(item: _history[i], strings: s, previous: i + 1 < _history.length ? _history[i + 1] : null),
                                      ],
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value, required this.unit, required this.color});

  final IconData icon;
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.surface.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.tab.copyWith(fontSize: 8.5, color: p.textSecondary, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value, style: AppTextStyles.metric.copyWith(fontSize: 17, color: color)),
                      const SizedBox(width: 4),
                      Text(unit, style: AppTextStyles.metricCaption.copyWith(fontSize: 9, color: p.textDisabled)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.strings, this.previous});

  final SpeedTestResult item;
  final S strings;

  /// The run before this one, used for the up/down delta chips.
  final SpeedTestResult? previous;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final when = FormatUtils.timeAgo(item.at, ru: strings.code == 'ru');
    final download = SpeedTestService.mbps(item.downloadBps).toStringAsFixed(1);
    final delta = previous == null ? null : item.downloadBps - previous!.downloadBps;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (item.viaVpn ? p.accent : p.textSecondary).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.viaVpn ? Icons.vpn_lock_rounded : Icons.public_rounded,
                size: 16, color: item.viaVpn ? p.accent : p.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(when, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  [if (item.pingMs > 0) '${item.pingMs} ms', if ((item.server ?? '').isNotEmpty) item.server!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySecondary.copyWith(fontSize: 11, color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (delta != null && delta.abs() > 0.05)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(delta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 14, color: delta >= 0 ? p.success : AppColors.error),
                  const SizedBox(width: 3),
                  Text('${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                      style: AppTextStyles.metricCaption.copyWith(
                          fontSize: 10.5, color: delta >= 0 ? p.success : AppColors.error)),
                ],
              ),
            ),
          Text('$download', style: AppTextStyles.metric.copyWith(fontSize: 15, color: p.text)),
          const SizedBox(width: 3),
          Text('Mbit/s', style: AppTextStyles.metricCaption.copyWith(fontSize: 9, color: p.textDisabled)),
        ],
      ),
    );
  }
}

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
