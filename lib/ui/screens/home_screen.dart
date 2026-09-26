import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/models/server_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/stats_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';
import '../widgets/connect_button.dart';
import '../widgets/country_badge.dart';
import '../widgets/nukefy_logo.dart';
import '../widgets/ping_badge.dart';
import 'main_shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final stats = context.watch<StatsProvider>();
    final settings = context.watch<SettingsProvider>();
    final p = context.palette;
    final s = settings.strings;
    final server = vpn.activeServer;
    final desktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final statusText = switch (vpn.status) {
      VpnStatus.connected => s.t('connected'),
      VpnStatus.connecting => s.t('connecting'),
      VpnStatus.error => s.t('connectionError'),
      VpnStatus.disconnected => s.t('disconnected'),
    };
    final statusColor = switch (vpn.status) {
      VpnStatus.connected => p.success,
      VpnStatus.connecting => p.accent,
      VpnStatus.error => AppColors.error,
      VpnStatus.disconnected => p.textSecondary,
    };

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, desktop ? 20 : 8, 20, 0),
        child: Column(
          children: [
            if (!desktop)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Row(
                  children: [
                    const NukefyLogo(size: 32),
                    const SizedBox(width: 12),
                    Text(s.t('appTitle'), style: AppTextStyles.headline),
                    const Spacer(),
                    _RoundIcon(
                      icon: Icons.tune_rounded,
                      onTap: () => context.read<NavProvider>().setIndex(4),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            // Speeds above the button, timer below — the button stays the hero.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Metric(icon: Icons.arrow_upward_rounded, label: FormatUtils.speed(stats.upBps), color: p.accent),
                const SizedBox(width: 28),
                _Metric(icon: Icons.arrow_downward_rounded, label: FormatUtils.speed(stats.downBps), color: p.success),
              ],
            ),
            const SizedBox(height: 30),
            ConnectButton(
              status: vpn.status,
              onPressed: () {
                if (server == null) {
                  showServerPicker(context);
                  return;
                }
                vpn.toggle();
              },
            ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.94, 0.94), curve: Curves.easeOutBack),
            const SizedBox(height: 26),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                statusText,
                key: ValueKey(statusText),
                style: AppTextStyles.status.copyWith(color: statusColor),
              ),
            ).animate(
              onPlay: vpn.status == VpnStatus.connecting
                  ? (controller) => controller.repeat(reverse: true)
                  : null,
            ).fade(begin: vpn.status == VpnStatus.connecting ? 0.4 : 1, end: 1),
            const SizedBox(height: 10),
            Text(
              stats.sessionStarted == null ? '00:00:00' : FormatUtils.duration(stats.sessionDuration),
              style: AppTextStyles.metric.copyWith(
                fontSize: 22,
                color: vpn.status == VpnStatus.connected ? p.text : p.textDisabled,
              ),
            ),
            if (vpn.errorMessage != null) ...[
              const SizedBox(height: 14),
              _ErrorCard(message: _friendlyError(s, vpn.errorMessage!)),
            ],
            const Spacer(),
            _ServerCard(
              server: server,
              title: server == null ? s.t('selectServer') : server.name,
              subtitle: server == null
                  ? s.t('tapToChange')
                  : '${FormatUtils.protocolLabel(server.protocol)} · ${server.address}',
              mode: vpn.status == VpnStatus.connected ? vpn.mode : null,
              onTap: () => showServerPicker(context),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic),
            SizedBox(height: desktop ? 24 : 96),
          ],
        ),
      ),
    );
  }

  String _friendlyError(S s, String raw) {
    if (raw == 'CORE_MISSING') return s.t('coreMissing');
    if (raw == 'LIBBOX_MISSING') return s.t('libboxMissing');
    if (raw == 'need-server') return s.t('needServer');
    if (raw == 'XHTTP_UNSUPPORTED') return s.t('xhttpUnsupported');
    if (raw.startsWith('NO_TRAFFIC:')) return '${s.t('noTraffic')}\n${raw.substring(11)}';
    if (raw.contains('Permission denied') && raw.contains('sing-box')) return s.t('libboxMissing');
    if (raw.contains('legacy inbound fields')) return s.t('coreOutdatedConfig');
    // Strip ANSI colour codes and the timestamp prefix from core logs.
    final clean = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').replaceAll(RegExp(r'^\S*FATAL\S*\[\d+\]\s*'), '');
    return clean.length > 260 ? '${clean.substring(0, 260)}…' : clean;
  }
}

/// Bottom sheet with every server; tapping one connects right away.
Future<void> showServerPicker(BuildContext context) async {
  final servers = context.read<ServersProvider>();
  if (servers.servers.isEmpty) {
    context.read<NavProvider>().setIndex(1);
    return;
  }
  final picked = await showModalBottomSheet<ServerModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const _ServerPickerSheet(),
  );
  if (picked != null && context.mounted) {
    await context.read<VpnProvider>().connect(picked);
  }
}

class _ServerPickerSheet extends StatelessWidget {
  const _ServerPickerSheet();

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<ServersProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final list = [...servers.servers]
      ..sort((a, b) {
        int rank(ServerModel m) => m.pingMs == null ? 1 : (m.pingMs! < 0 ? 2 : 0);
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return (a.pingMs ?? 0).compareTo(b.pingMs ?? 0);
      });
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(s.t('chooseServer'), style: AppTextStyles.headline)),
                TextButton.icon(
                  onPressed: servers.pinging ? null : () => servers.pingAll(),
                  icon: servers.pinging
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_rounded, size: 18),
                  label: Text(s.t('checkPing')),
                ),
                IconButton(
                  tooltip: s.t('servers'),
                  onPressed: () {
                    Navigator.pop(context);
                    context.read<NavProvider>().setIndex(1);
                  },
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final server = list[i];
                final active = vpn.activeServerId == server.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: active ? p.accent.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, server),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        child: Row(
                          children: [
                            CountryBadge(code: server.countryCode, size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodyRegular.copyWith(
                                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    FormatUtils.protocolLabel(server.protocol),
                                    style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PingBadge(pingMs: server.pingMs, compact: true),
                            if (active) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: (i * 18).clamp(0, 240).ms, duration: 220.ms);
              },
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
    final p = context.palette;
    return Row(
      children: [
        Icon(icon, size: 15, color: color ?? p.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.number.copyWith(color: color ?? p.text, fontSize: 13)),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                message,
                style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.1);
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.mode,
  });

  final ServerModel? server;
  final String title;
  final String subtitle;
  final String? mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        color: p.card.withValues(alpha: p.isDark ? 0.92 : 1),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                CountryBadge(code: server?.countryCode, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
                if (server?.pingMs != null) PingBadge(pingMs: server!.pingMs),
                const SizedBox(width: 4),
                Icon(Icons.unfold_more_rounded, color: p.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Kept for the desktop tray menu which still refers to the platform label.
String platformModeLabel(String mode) => mode == 'proxy' ? 'SOCKS / HTTP' : (Platform.isAndroid ? 'VPN' : 'TUN');


class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: p.isDark ? 0.9 : 0.96),
          shape: BoxShape.circle,
          border: Border.all(color: p.border),
        ),
        child: Icon(icon, size: 20, color: p.textSecondary),
      ),
    );
  }
}
