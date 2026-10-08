import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/services/game_icon_service.dart';
import '../../core/utils/ping_utils.dart';
import '../../l10n/strings.dart';

enum JammerVerdict { idle, none, whitelist, partial, dead }

/// Third tab: probes port 443 on a fixed list of sites and tells whether the
/// network is filtered with whitelists. Starts as a single button; results
/// slide in after the check.
class JammersScreen extends StatefulWidget {
  const JammersScreen({super.key});

  @override
  State<JammersScreen> createState() => _JammersScreenState();
}

class _JammersScreenState extends State<JammersScreen> {
  bool _busy = false;
  bool _checked = false;
  final Map<String, int> _results = <String, int>{};
  JammerVerdict _verdict = JammerVerdict.idle;

  Future<void> _check() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _checked = false;
      _results.clear();
      _verdict = JammerVerdict.idle;
    });
    final targets = <({String id, String host, int port})>[
      for (final host in AppConstants.jammerTargetsRu) (id: host, host: host, port: AppConstants.jammerProbePort),
      for (final host in AppConstants.jammerTargetsOther) (id: host, host: host, port: AppConstants.jammerProbePort),
    ];
    final results = await PingUtils.pingAll(targets, timeout: const Duration(seconds: 5));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checked = true;
      _results
        ..clear()
        ..addAll(results);
      _verdict = verdictOf(results);
    });
  }

  static int reachable(Map<String, int> results, List<String> hosts) {
    return hosts.where((host) => (results[host] ?? -1) >= 0).length;
  }

  /// Only Russian sites answer → whitelists. Google answers too → no jammers.
  /// Nothing answers → the network itself is down.
  static JammerVerdict verdictOf(Map<String, int> results) {
    final ru = reachable(results, AppConstants.jammerTargetsRu);
    final other = reachable(results, AppConstants.jammerTargetsOther);
    final google = (results['google.com'] ?? -1) >= 0;
    if (ru == 0 && other == 0) return JammerVerdict.dead;
    if (ru > 0 && google) return JammerVerdict.none;
    if (ru > 0 && other == 0) return JammerVerdict.whitelist;
    return JammerVerdict.partial;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (!_checked) {
      return SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom + 60),
            child: _BigCheckButton(busy: _busy, label: s.t('checkNetwork'), onTap: _check)
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final ru = _HostGroup(
            title: s.t('jammersRu'),
            hosts: AppConstants.jammerTargetsRu,
            results: _results,
            delay: 120.ms,
          );
          final other = _HostGroup(
            title: s.t('jammersOther'),
            hosts: AppConstants.jammerTargetsOther,
            results: _results,
            delay: 260.ms,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VerdictCard(
                verdict: _verdict,
                strings: s,
                trailing: _CheckAgainButton(busy: _busy, onTap: _check, label: s.t('checkAgain')),
              )
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),
              const SizedBox(height: 16),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ru),
                    const SizedBox(width: 16),
                    Expanded(child: other),
                  ],
                )
              else ...[
                ru,
                const SizedBox(height: 14),
                other,
              ],
              const SizedBox(height: 18),
            ],
          );
        }),
      ),
    );
  }
}

class _BigCheckButton extends StatelessWidget {
  const _BigCheckButton({required this.busy, required this.label, required this.onTap});
  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accent.withValues(alpha: 0.22), p.accent2.withValues(alpha: 0.14)],
              ),
              border: Border.all(color: p.accent.withValues(alpha: 0.55), width: 1.4),
              boxShadow: [
                BoxShadow(color: p.accent.withValues(alpha: busy ? 0.35 : 0.18), blurRadius: 40, spreadRadius: 2),
              ],
            ),
            child: Center(
              child: busy
                  ? Icon(Icons.radar_rounded, size: 60, color: p.accent)
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: const Duration(milliseconds: 1500), curve: Curves.easeInOutCubic)
                  : Icon(Icons.radar_rounded, size: 60, color: p.accent),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(1, 1), end: const Offset(1.03, 1.03), duration: 1800.ms, curve: Curves.easeInOut),
        const SizedBox(height: 26),
        Text(
          label.toUpperCase(),
          style: AppTextStyles.status.copyWith(color: p.text, fontSize: 13),
        ),
      ],
    );
  }
}

/// Tactile "check again" action: dips on press, spins the icon while the
/// probe runs instead of swapping to a bare progress ring.
class _CheckAgainButton extends StatefulWidget {
  const _CheckAgainButton({required this.busy, required this.onTap, required this.label});
  final bool busy;
  final VoidCallback onTap;
  final String label;

  @override
  State<_CheckAgainButton> createState() => _CheckAgainButtonState();
}

class _CheckAgainButtonState extends State<_CheckAgainButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: p.accent.withValues(alpha: _down ? .2 : .12),
              foregroundColor: p.accent,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              elevation: 0,
            ),
            onPressed: widget.busy ? null : widget.onTap,
            icon: widget.busy
                ? const Icon(Icons.refresh_rounded, size: 17)
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: const Duration(milliseconds: 900))
                : const Icon(Icons.refresh_rounded, size: 17),
            label: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(widget.label, key: ValueKey(widget.label)),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict, required this.strings, this.trailing});

  final JammerVerdict verdict;
  final S strings;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color, title, body) = switch (verdict) {
      JammerVerdict.none => (Icons.verified_rounded, p.success, strings.t('jammersNone'), strings.t('jammersNoneDesc')),
      JammerVerdict.whitelist => (Icons.rule_rounded, AppColors.warning, strings.t('jammersWhitelist'), strings.t('jammersWhitelistDesc')),
      JammerVerdict.partial => (Icons.network_check_rounded, AppColors.warning, strings.t('jammersPartial'), strings.t('jammersPartialDesc')),
      JammerVerdict.dead => (Icons.signal_wifi_bad_rounded, AppColors.error, strings.t('jammersDead'), strings.t('jammersDeadDesc')),
      JammerVerdict.idle => (Icons.radar_rounded, p.textSecondary, '', ''),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final message = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.headline.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(body, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
          ],
        );
        final iconBox = Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 30),
        );
        final lead = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            iconBox,
            const SizedBox(width: 16),
            Expanded(child: message),
          ],
        );
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 30)],
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    lead,
                    if (trailing != null) ...[
                      const SizedBox(height: 16),
                      Align(alignment: AlignmentDirectional.center, child: trailing),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    iconBox,
                    const SizedBox(width: 16),
                    Expanded(child: message),
                    if (trailing != null) ...[
                      const SizedBox(width: 16),
                      trailing!,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _HostGroup extends StatelessWidget {
  const _HostGroup({required this.title, required this.hosts, required this.results, required this.delay});

  final String title;
  final List<String> hosts;
  final Map<String, int> results;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.section.copyWith(color: p.textSecondary)),
          const SizedBox(height: 6),
          for (var i = 0; i < hosts.length; i++)
            _HostRow(host: hosts[i], ms: results[hosts[i]])
                .animate()
                .fadeIn(delay: delay + (i * 60).ms, duration: 260.ms)
                .slideX(begin: 0.05, curve: Curves.easeOutCubic),
        ],
      ),
    ).animate().fadeIn(delay: delay, duration: 300.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }
}

/// The real service mark: favicon fetched once and cached on disk. Falls
/// back to the brand-coloured glyph when the network says no.
class _ServiceIcon extends StatefulWidget {
  const _ServiceIcon({required this.host, required this.color, required this.fallback});

  final String host;
  final Color color;
  final IconData fallback;

  @override
  State<_ServiceIcon> createState() => _ServiceIconState();
}

class _ServiceIconState extends State<_ServiceIcon> {
  static final Map<String, Uint8List?> _memory = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _memory[widget.host];
    if (_bytes == null && !_memory.containsKey(widget.host)) _fetch();
  }

  Future<void> _fetch() async {
    _memory[widget.host] = null;
    final bytes = await GameIconService.instance.fetchBytesForFavicon(widget.host);
    _memory[widget.host] = bytes;
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bytes = _bytes;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: p.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: bytes == null
          ? Icon(widget.fallback, size: 20, color: widget.color)
          : ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Icon(widget.fallback, size: 20, color: widget.color)),
            ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.host, required this.ms});

  final String host;
  final int? ms;

  static const _brands = <String, (IconData, String, Color)>{
    'yandex.ru': (Icons.search_rounded, 'Яндекс', Color(0xFFFC3F1D)),
    'vk.com': (Icons.forum_rounded, 'ВКонтакте', Color(0xFF0077FF)),
    'www.gosuslugi.ru': (Icons.account_balance_rounded, 'Госуслуги', Color(0xFF0D4CD3)),
    'mail.ru': (Icons.mail_rounded, 'Mail.ru', Color(0xFF005FF9)),
    'google.com': (Icons.g_mobiledata_rounded, 'Google', Color(0xFF4285F4)),
    'www.gstatic.com': (Icons.cloud_rounded, 'Google Static', Color(0xFF34A853)),
    'update.miui.com': (Icons.system_update_rounded, 'Xiaomi MIUI', Color(0xFFFF6900)),
    'cloudflare.com': (Icons.shield_rounded, 'Cloudflare', Color(0xFFF38020)),
    'github.com': (Icons.code_rounded, 'GitHub', Color(0xFF8B949E)),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ok = ms != null && ms! >= 0;
    final brand = _brands[host];
    final color = brand?.$3 ?? p.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _ServiceIcon(
            host: host,
            color: color,
            fallback: brand?.$1 ?? Icons.language_rounded,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brand?.$2 ?? host, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                Text(host, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          if (ok)
            Text('$ms ms', style: AppTextStyles.number.copyWith(color: p.success, fontSize: 12))
          else
            Icon(Icons.close_rounded, size: 18, color: AppColors.error),
        ],
      ),
    );
  }
}
