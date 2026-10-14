import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/stats_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/geo_utils.dart';
import '../dialogs/auto_setup_dialog.dart';
import '../widgets/connect_button.dart';
import '../widgets/notification_overlay.dart';
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
              child: Column(
                children: [
                  if (!wide)
                    Row(
                      children: [
                        Text(s.t('appTitle'), style: AppTextStyles.headline),
                        const Spacer(),
                        const NotificationBell(),
                        IconButton(
                          onPressed: () =>
                              context.read<NavProvider>().goSettings(),
                          icon: const Icon(Icons.settings_rounded),
                        ),
                      ],
                    ),
                  if (!settings.settings.guideHidden) ...[
                    const SizedBox(height: 10),
                    const _GuideCard(),
                  ],
                  const SizedBox(height: 18),
                  ConnectButton(
                    status: vpn.status,
                    onPressed: () {
                      if (server == null) {
                        context.read<NotificationsProvider>().push(
                              title: s.t('selectServer'),
                              body: s.t('errNeedServer'),
                              kind: AppNotificationKind.info,
                              routeIndex: NavTabs.servers,
                              actionLabel: s.t('openServers'),
                            );
                        context.read<NavProvider>().goServers();
                        return;
                      }
                      vpn.toggle();
                    },
                  ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.96, 0.96)),
                  const SizedBox(height: 20),
                  Text(statusText, style: AppTextStyles.status.copyWith(color: statusColor))
                      .animate(
                        onPlay: vpn.status == VpnStatus.connecting
                            ? (controller) => controller.repeat(reverse: true)
                            : null,
                      )
                      .fade(begin: vpn.status == VpnStatus.connecting ? 0.35 : 1, end: 1),
                  if (vpn.status == VpnStatus.connected)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        vpn.engine == 'xray'
                            ? '${s.t('engine')}: Xray · SOCKS/HTTP'
                            : '${s.t('engine')}: sing-box · ${vpn.mode == 'proxy' ? 'SOCKS/HTTP' : 'TUN'}',
                        style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _Metric(
                        icon: Icons.timer_outlined,
                        label: stats.sessionStarted == null
                            ? '00:00:00'
                            : FormatUtils.duration(stats.sessionDuration),
                      ),
                      _Metric(
                        icon: Icons.arrow_upward_rounded,
                        label: FormatUtils.speed(stats.upBps),
                        color: AppColors.cyan,
                      ),
                      _Metric(
                        icon: Icons.arrow_downward_rounded,
                        label: FormatUtils.speed(stats.downBps),
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _ServerCard(
                    flag: GeoUtils.flagEmoji(server?.countryCode),
                    title: server == null ? s.t('selectServer') : server.name,
                    subtitle: server == null
                        ? s.t('tapToChange')
                        : '${FormatUtils.protocolLabel(server.protocol)} · ${server.address}:${server.port}',
                    ping: server?.pingMs,
                    xhttp: server?.isXhttp ?? false,
                    onTap: () => context.read<NavProvider>().goServers(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Three-step starter guide with real state checkmarks. Hides forever via
/// the settings flag once the user dismisses it.
class _GuideCard extends StatelessWidget {
  const _GuideCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final servers = context.watch<ServersProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = settings.strings;
    final coreReady = vpn.core?.available ?? false;
    final hasServers = servers.servers.isNotEmpty;
    final connected = vpn.status == VpnStatus.connected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
              Text(s.t('guideTitle').toUpperCase(), style: AppTextStyles.section),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    settings.update((value) => value.guideHidden = true),
                child: Text(s.t('guideDone')),
              ),
            ],
          ),
          _GuideStep(
            done: coreReady,
            title: s.t('guideStep1'),
            body: s.t('guideStep1Body'),
            actionLabel: coreReady ? null : s.t('autoSetupRun'),
            onAction: coreReady ? null : () => showAutoSetupDialog(context),
          ),
          _GuideStep(
            done: hasServers,
            title: s.t('guideStep2'),
            body: s.t('guideStep2Body'),
            actionLabel: hasServers ? null : s.t('openServers'),
            onAction: hasServers
                ? null
                : () => context.read<NavProvider>().goServers(),
          ),
          _GuideStep(
            done: connected,
            title: s.t('guideStep3'),
            body: s.t('guideStep3Body'),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.done,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final bool done;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 20,
            color: done ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(body, style: AppTextStyles.bodySecondary),
                if (actionLabel != null && onAction != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
    required this.xhttp,
    this.ping,
  });

  final String flag;
  final String title;
  final String subtitle;
  final int? ping;
  final bool xhttp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
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
                    if (xhttp)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'XHTTP · ${s.t('viaXray')}',
                          style: AppTextStyles.bodySecondary.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
