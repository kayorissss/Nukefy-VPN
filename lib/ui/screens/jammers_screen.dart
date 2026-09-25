import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/network_check_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/section_card.dart';

/// Third tab: checks whether the current network looks jammed or whether the
/// ISP simply runs a whitelist. Everything is a plain TCP connect to port 443.
class JammersScreen extends StatefulWidget {
  const JammersScreen({super.key});

  @override
  State<JammersScreen> createState() => _JammersScreenState();
}

class _JammersScreenState extends State<JammersScreen> {
  static const _service = NetworkCheckService();
  static const _timeout = Duration(seconds: 4);

  NetworkCheckResult? _result;
  bool _busy = false;
  bool _autoChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoChecked) return;
    _autoChecked = true;
    // The tab is a diagnostic screen: run the probe once when it is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result ??= NetworkCheckResult(latencies: const {});
    });
    try {
      final result = await _service.check(
        timeout: _timeout,
        onHost: (host, ms) {
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final result = _result;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(s.t('jammers'), style: AppTextStyles.title),
          const SizedBox(height: 6),
          Text(s.t('jammersHint'), style: AppTextStyles.bodySecondary),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _busy ? null : _check,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: Text(
                _busy ? s.t('checking') : s.t('checkNetwork'),
                style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (result != null && !_busy) _VerdictCard(result: result),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(s.t('checking'), style: AppTextStyles.bodySecondary),
                ],
              ),
            ),
          SectionCard(
            title: s.t('russianHosts'),
            child: Column(
              children: [
                for (final host in NetworkCheckService.russianHosts)
                  _HostRow(host: host, latencyMs: result?.latencyOf(host)),
              ],
            ),
          ),
          SectionCard(
            title: s.t('otherHosts'),
            child: Column(
              children: [
                for (final host in NetworkCheckService.otherHosts)
                  _HostRow(host: host, latencyMs: result?.latencyOf(host)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(s.t('jammersFooter'), style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.result});

  final NetworkCheckResult result;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final verdict = result.verdict;
    final color = switch (verdict) {
      NetworkVerdict.whitelists => AppColors.warning,
      NetworkVerdict.noJamming => AppColors.success,
      NetworkVerdict.offline => AppColors.error,
      NetworkVerdict.partial => AppColors.warning,
    };
    final icon = switch (verdict) {
      NetworkVerdict.whitelists => Icons.filter_alt_off_outlined,
      NetworkVerdict.noJamming => Icons.verified_user_outlined,
      NetworkVerdict.offline => Icons.wifi_off_rounded,
      NetworkVerdict.partial => Icons.help_outline_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t(networkVerdictKey(verdict)),
                  style: AppTextStyles.headline.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  s.t(networkVerdictHintKey(verdict)),
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.host, this.latencyMs});

  final String host;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final untested = latencyMs == null;
    final failed = latencyMs != null && latencyMs! < 0;
    final color = untested
        ? AppColors.textDisabled
        : failed
            ? AppColors.error
            : AppColors.pingColor(latencyMs);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            untested
                ? Icons.radio_button_unchecked_rounded
                : failed
                    ? Icons.cancel_outlined
                    : Icons.check_circle_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyRegular,
            ),
          ),
          Text(
            untested
                ? '—'
                : failed
                    ? '✕'
                    : '$latencyMs ms',
            style: AppTextStyles.monoValue.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
