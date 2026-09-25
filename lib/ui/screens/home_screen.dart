import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/stats_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/geo_utils.dart';
import '../widgets/connect_button.dart';
import '../widgets/nukefy_logo.dart';
import '../widgets/ping_badge.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final stats = context.watch<StatsProvider>();
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final server = vpn.activeServer;
    final statusText = switch (vpn.status) {
      VpnStatus.connected => s.t('connected'),
      VpnStatus.connecting => s.t('connecting'),
      VpnStatus.error => s.t('connectionError'),
      VpnStatus.disconnected => s.t('disconnected'),
    };
    final statusColor = switch (vpn.status) {
      VpnStatus.connected => AppColors.success,
      VpnStatus.connecting => AppColors.cyan,
      VpnStatus.error => AppColors.error,
      VpnStatus.disconnected => AppColors.textSecondary,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          children: [
            Row(
              children: [
                const NukefyLogo(size: 36),
                const SizedBox(width: 10),
                Text(s.t('appTitle'), style: AppTextStyles.headline),
                const Spacer(),
                IconButton(
                  onPressed: () => context.read<NavProvider>().setIndex(3),
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            const Spacer(),
            ConnectButton(
              status: vpn.status,
              onPressed: () {
                if (server == null) {
                  context.read<NavProvider>().setIndex(1);
                  return;
                }
                vpn.toggle();
              },
            ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.96, 0.96)),
            const SizedBox(height: 22),
            Text(statusText, style: AppTextStyles.status.copyWith(color: statusColor))
                .animate(
                  onPlay: vpn.status == VpnStatus.connecting
                      ? (controller) => controller.repeat(reverse: true)
                      : null,
                )
                .fade(begin: vpn.status == VpnStatus.connecting ? 0.35 : 1, end: 1),
            if (vpn.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                vpn.errorMessage == 'CORE_MISSING'
                    ? s.t('coreMissing')
                    : vpn.errorMessage!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Metric(
                  icon: Icons.timer_outlined,
                  label: stats.sessionStarted == null
                      ? '00:00:00'
                      : FormatUtils.duration(stats.sessionDuration),
                ),
                const SizedBox(width: 18),
                _Metric(
                  icon: Icons.arrow_upward_rounded,
                  label: FormatUtils.speed(stats.upBps),
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 18),
                _Metric(
                  icon: Icons.arrow_downward_rounded,
                  label: FormatUtils.speed(stats.downBps),
                  color: AppColors.success,
                ),
              ],
            ),
            const Spacer(),
            _ServerCard(
              flag: GeoUtils.flagEmoji(server?.countryCode),
              title: server == null ? s.t('selectServer') : server.name,
              subtitle: server == null
                  ? s.t('tapToChange')
                  : '${FormatUtils.protocolLabel(server.protocol)} · ${server.address}:${server.port}',
              ping: server?.pingMs,
              mode: vpn.status == VpnStatus.connected ? vpn.mode : null,
              onTap: () => context.read<NavProvider>().setIndex(1),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.monoValue.copyWith(color: color)),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.ping,
    this.mode,
  });

  final String flag;
  final String title;
  final String subtitle;
  final int? ping;
  final String? mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySecondary),
                    if (mode != null)
                      Text(
                        mode == 'proxy' ? 'SOCKS / HTTP' : 'TUN',
                        style: AppTextStyles.bodySecondary.copyWith(color: AppColors.cyan, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (ping != null) PingBadge(pingMs: ping),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
