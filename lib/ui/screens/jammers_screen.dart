import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/ping_utils.dart';

enum JammerVerdict { idle, none, whitelist, partial, dead }

/// Third tab: probes port 443 on a fixed list of sites and tells whether the
/// network is filtered with whitelists.
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
    final results = await PingUtils.pingAll(
      targets,
      timeout: const Duration(seconds: 5),
    );
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(s.t('jammers'), style: AppTextStyles.title),
          const SizedBox(height: 10),
          Text(s.t('jammersHint'), style: AppTextStyles.bodySecondary),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _check,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: Text(s.t('checkNetwork')),
            ),
          ),
          const SizedBox(height: 14),
          _VerdictCard(verdict: _verdict, busy: _busy, checked: _checked),
          const SizedBox(height: 18),
          _HostGroup(
            title: s.t('jammersRu'),
            hosts: AppConstants.jammerTargetsRu,
            results: _results,
          ),
          const SizedBox(height: 12),
          _HostGroup(
            title: s.t('jammersOther'),
            hosts: AppConstants.jammerTargetsOther,
            results: _results,
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict, required this.busy, required this.checked});

  final JammerVerdict verdict;
  final bool busy;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final color = switch (verdict) {
      JammerVerdict.none => AppColors.success,
      JammerVerdict.dead => AppColors.error,
      JammerVerdict.whitelist => AppColors.warning,
      JammerVerdict.partial => AppColors.warning,
      JammerVerdict.idle => AppColors.textSecondary,
    };
    final icon = switch (verdict) {
      JammerVerdict.none => Icons.verified_user_rounded,
      JammerVerdict.dead => Icons.signal_wifi_bad_rounded,
      JammerVerdict.whitelist => Icons.rule_rounded,
      JammerVerdict.partial => Icons.gpp_maybe_rounded,
      JammerVerdict.idle => Icons.radar_rounded,
    };
    final text = switch (verdict) {
      JammerVerdict.none => s.t('jammersNone'),
      JammerVerdict.whitelist => s.t('jammersWhitelist'),
      JammerVerdict.dead => s.t('jammersDead'),
      JammerVerdict.partial => s.t('jammersPartial'),
      JammerVerdict.idle => busy ? s.t('jammersChecking') : s.t('jammersIdle'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: color),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.headline.copyWith(color: color, fontSize: 20),
          ),
          if (checked) ...[
            const SizedBox(height: 6),
            Text(
              '${s.t('jammersVerdict')} · :${AppConstants.jammerProbePort}',
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _HostGroup extends StatelessWidget {
  const _HostGroup({required this.title, required this.hosts, required this.results});

  final String title;
  final List<String> hosts;
  final Map<String, int> results;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(title.toUpperCase(), style: AppTextStyles.section),
          ),
          for (final host in hosts) _HostRow(host: host, ms: results[host]),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.host, required this.ms});

  final String host;
  final int? ms;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final ok = ms != null && ms! >= 0;
    final color = ok ? AppColors.success : (ms == null ? AppColors.textSecondary : AppColors.error);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Icon(
        ok ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
        size: 18,
        color: color,
      ),
      title: Text(host, style: AppTextStyles.bodyRegular.copyWith(fontSize: 13.5)),
      trailing: Text(
        ok ? '$ms ms' : (ms == null ? '—' : s.t('jammersNoReply')),
        style: AppTextStyles.monoValue.copyWith(color: color, fontSize: 12),
      ),
    );
  }
}
