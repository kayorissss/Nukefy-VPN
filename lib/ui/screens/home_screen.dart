import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
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
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';
import '../../l10n/strings.dart';
import '../widgets/connect_button.dart';
import '../widgets/country_badge.dart';
import '../widgets/nukefy_logo.dart';
import '../widgets/ping_badge.dart';
import '../../core/services/vpn_platform.dart';
import 'diagnostics_screen.dart';
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
      VpnStatus.error => p.error,
      VpnStatus.disconnected => p.textSecondary,
    };

    final metrics = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Metric(icon: Icons.arrow_upward_rounded, label: FormatUtils.speed(stats.upBps), color: p.accent),
        const SizedBox(width: 28),
        _Metric(icon: Icons.arrow_downward_rounded, label: FormatUtils.speed(stats.downBps), color: p.success),
      ],
    );
    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        metrics,
        const SizedBox(height: 24),
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
        const SizedBox(height: 20),
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
        const SizedBox(height: 8),
        Text(
          stats.sessionStarted == null ? '00:00:00' : FormatUtils.duration(stats.sessionDuration),
          style: AppTextStyles.metric.copyWith(
            fontSize: 22,
            color: vpn.status == VpnStatus.connected ? p.text : p.textDisabled,
          ),
        ),
        if (vpn.conflictNotice != null) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.accent.withValues(alpha: .35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${s.t('conflictWarn')}: ${vpn.conflictNotice}',
                        style: AppTextStyles.bodySecondary.copyWith(color: p.text)),
                  ),
                  IconButton(
                    tooltip: s.t('zCopyReport'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: vpn.conflictNotice ?? ''));
                      if (context.mounted) showNukefySnack(context, s.t('copied'));
                    },
                    icon: Icon(Icons.copy_rounded, size: 15, color: p.accent),
                  ),
                  IconButton(
                    onPressed: vpn.dismissConflict,
                    icon: Icon(Icons.close_rounded, size: 15, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (vpn.errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorCard(message: _friendlyError(s, vpn.errorMessage!)),
        ],
        // The honest answer to "вроде подключено, а ничего не работает":
        // after every connect the app asks the tunnel whether data flows and
        // shows the per-site verdict instead of a green light on faith.
        if (vpn.status == VpnStatus.connected) ...[
          const SizedBox(height: 14),
          _TrafficCard(vpn: vpn, strings: s),
        ],
        const SizedBox(height: 14),
        const _WarpHintCard(),
      ],
    );
    final serverCard = _ServerCard(
      server: server,
      title: server == null ? s.t('selectServer') : server.displayName,
      subtitle: server == null
          ? s.t('tapToChange')
          : '${FormatUtils.protocolLabel(server.protocol)} · ${server.address}',
      mode: vpn.status == VpnStatus.connected ? vpn.mode : null,
      onTap: () => showServerPicker(context),
    ).animate().fadeIn(delay: 120.ms, duration: 400.ms).slideY(begin: 0.04, curve: Curves.easeOutCubic);
    final mobileHeader = Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          const NukefyLogo(size: 32),
          const SizedBox(width: 12),
          Text(s.t('appTitle'), style: AppTextStyles.headline),
          const Spacer(),
          _RoundIcon(
            icon: Icons.tune_rounded,
            onTap: () => context.read<NavProvider>().go(NavDestination.settings),
          ),
        ],
      ),
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(desktop ? 32 : 18, desktop ? 28 : 8, desktop ? 32 : 18, 0),
        child: desktop
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        hero,
                        const SizedBox(height: 28),
                        serverCard,
                      ],
                    ),
                  ),
                ),
              )
            : Column(
                children: [
                  mobileHeader,
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          hero,
                          const SizedBox(height: 26),
                          serverCard,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _friendlyError(S s, String raw) {
    if (raw == 'CORE_MISSING') return s.t('coreMissing');
    if (raw == 'LIBBOX_MISSING') return s.t('libboxMissing');
    if (raw == 'information-entry') return s.t('informationEntry');
    if (raw == 'need-server') return s.t('needServer');
    if (raw == 'XHTTP_UNSUPPORTED') return s.t('xhttpUnsupported');
    if (raw == 'CORE_PROTOCOL_UNSUPPORTED') return s.t('coreProtocolUnsupported');
    if (raw == 'CORE_MIERU_UNSUPPORTED') return s.t('coreMieruUnsupported');
    if (raw == 'CORE_OUTBOUND_MISSING') return s.t('coreOutboundMissing');
    if (raw == 'CORE_ENDPOINT_MISSING') return s.t('coreEndpointMissing');
    if (raw == 'XRAY_TRANSPORT_REQUIRED') return s.t('xrayTransportRequired');
    if (raw == 'XRAY_CORE_MISSING') return s.t('xrayNotInstalled');
    if (raw == 'XRAY_PLATFORM_UNSUPPORTED') return s.t('xrayPlatformUnsupported');
    if (raw == 'XRAY_UNSUPPORTED_PROTOCOL') return s.t('xrayUnsupportedProtocol');
    if (raw == 'XRAY_FRONTEND_MISSING') return s.t('xrayFrontendMissing');
    if (raw.startsWith('XRAY_')) return '${s.t('xrayCore')}: $raw';
    if (raw.startsWith('NO_TRAFFIC:')) return '${s.t('noTraffic')}\n${raw.substring(11)}';
    if (raw == 'NO_TRAFFIC_TARGETS') return s.t('noTrafficTargets');
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
  if (servers.servers.where((server) => !server.isInformational).isEmpty) {
    context.read<NavProvider>().go(NavDestination.servers);
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

class _ServerPickerSheet extends StatefulWidget {
  const _ServerPickerSheet();

  @override
  State<_ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<_ServerPickerSheet> {
  String? _subId;

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<ServersProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final subs = servers.subscriptions.where((e) => e.enabled).toList();
    _subId ??= vpn.activeServer?.subscriptionId ?? (subs.isEmpty ? null : subs.first.id);
    if (_subId != null && !subs.any((e) => e.id == _subId)) _subId = subs.isEmpty ? null : subs.first.id;
    final list = servers.servers
        .where((server) => !server.isInformational && (_subId == null || server.subscriptionId == _subId))
        .toList()
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
                    context.read<NavProvider>().go(NavDestination.servers);
                  },
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          if (subs.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: NukefyDropdown<String>(
                value: _subId ?? '',
                items: {for (final e in subs) e.id: e.name},
                onChanged: (id) => setState(() => _subId = id),
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
                                    server.displayName,
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

/// Post-connect verdict: does traffic really flow, and through which sites?
class _TrafficCard extends StatefulWidget {
  const _TrafficCard({required this.vpn, required this.strings});

  final VpnProvider vpn;
  final S strings;

  @override
  State<_TrafficCard> createState() => _TrafficCardState();
}

class _TrafficCardState extends State<_TrafficCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vpn = widget.vpn;
    final s = widget.strings;
    final bad = vpn.trafficOk == false;
    final color = bad ? AppColors.error : (vpn.trafficOk == true ? AppColors.success : p.textSecondary);
    final icon = bad ? Icons.error_outline_rounded : (vpn.trafficOk == true ? Icons.verified_rounded : Icons.hourglass_top_rounded);
    final title = vpn.trafficOk == null ? s.t('trafficChecking') : (bad ? s.t('trafficBad') : s.t('trafficOk'));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: p.text)),
                ),
                if (_busy)
                  const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  NukefyActionButton(
                    label: s.t('refresh'),
                    filled: false,
                    onPressed: () async {
                      setState(() => _busy = true);
                      await vpn.verifyTrafficNow();
                      if (mounted) setState(() => _busy = false);
                    },
                  ),
              ],
            ),
            if (bad) ...[
              const SizedBox(height: 6),
              Text(s.t('trafficBadHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
              const SizedBox(height: 8),
              NukefyActionButton(
                label: s.t('trafficOpen'),
                icon: Icons.health_and_safety_outlined,
                onPressed: () => DiagnosticsScreen.open(context),
              ),
            ] else if (vpn.trafficTargets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in vpn.trafficTargets.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: (entry.value ? AppColors.success : AppColors.error).withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.value ? Icons.check_rounded : Icons.close_rounded,
                              size: 13, color: entry.value ? AppColors.success : AppColors.error),
                          const SizedBox(width: 5),
                          Text(entry.key, style: AppTextStyles.bodySecondary.copyWith(fontSize: 11.5, color: p.text)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown only to people who actually have Cloudflare WARP installed. It is
/// the one place outside of the settings where WARP can be switched off, and
/// it never fires by itself: two TUN drivers on one machine is a common cause
/// of "подключено, а интернет не работает".
class _WarpHintCard extends StatefulWidget {
  const _WarpHintCard();

  @override
  State<_WarpHintCard> createState() => _WarpHintCardState();
}

class _WarpHintCardState extends State<_WarpHintCard> {
  bool? _present;
  bool _running = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final platform = VpnPlatform();
    final present = await platform.warpInstalled();
    if (!mounted) return;
    if (!present) {
      setState(() => _present = false);
      return;
    }
    final lines = await platform.warpStatus();
    if (!mounted) return;
    setState(() {
      _present = true;
      _running = lines.any((line) => line.split('|').length > 1 && line.split('|')[1] == 'Running');
    });
  }

  Future<void> _toggle() async {
    final s = context.read<SettingsProvider>().strings;
    setState(() => _busy = true);
    final platform = VpnPlatform();
    final result = _running ? await platform.disableWarp() : await platform.enableWarp();
    if (!mounted) return;
    await _check();
    if (!mounted) return;
    setState(() => _busy = false);
    showNukefySnack(context, s.t(_running ? 'warpOffDone' : 'warpOnDone'));
  }

  @override
  Widget build(BuildContext context) {
    if (_present != true) return const SizedBox.shrink();
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: (_running ? AppColors.error : p.textSecondary).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_outlined, size: 18, color: _running ? AppColors.error : p.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('warpCardTitle'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    _running ? s.t('warpCardRunning') : s.t('warpCardHint'),
                    style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (_busy)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              NukefyActionButton(
                label: s.t(_running ? 'warpCardOff' : 'warpCardOn'),
                filled: _running,
                onPressed: _toggle,
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: p.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                message,
                style: AppTextStyles.bodySecondary.copyWith(color: p.error, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: s.t('zCopyReport'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (context.mounted) showNukefySnack(context, s.t('copied'));
              },
              icon: Icon(Icons.copy_rounded, size: 15, color: p.error),
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
