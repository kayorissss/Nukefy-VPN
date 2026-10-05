import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/app_log.dart';
import '../../core/services/subscription_service.dart';
import '../../core/services/update_service.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/network_diagnostics.dart';
import '../../l10n/strings.dart';
import '../dialogs/progress_dialog.dart';
import '../import_actions.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';
import '../widgets/section_card.dart';
import 'dns_screen.dart';
import 'log_screen.dart';
import 'per_app_screen.dart';
import 'routing_screen.dart';
import 'update_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialSection = 0, this.showSubtabs = true});

  /// Desktop rail destinations open a section directly. Mobile keeps the
  /// compact local tab strip because there is no permanent side rail.
  final int initialSection;
  final bool showSubtabs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _section = widget.initialSection.clamp(0, 2).toInt();

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection.clamp(0, 2).toInt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = settings.strings;
    final value = settings.settings;
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: ResponsiveSections(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        // The rail is the desktop section switcher. On mobile the local tabs
        // and the update banner remain page-level, full-width elements.
        minColumnWidth: 460,
        maxColumns: 2,
        fullWidthCount: (widget.showSubtabs ? 1 : 0) + (_section == 0 ? 1 : 0),
        children: [
          // Desktop downloads sing-box as a separate binary; Android ships
          // the core inside the APK (libbox), so there is nothing to install.
          if (widget.showSubtabs)
            _SettingsSubtabs(selected: _section, onChanged: (value) => setState(() => _section = value)),
          if (_section == 0) const _UpdateBanner(),
          if (_section == 0 && !Platform.isAndroid) ...[
            _CoreCard(vpn: vpn, strings: s),
            _XrayCard(vpn: vpn, strings: s),
          ],
          if (_section == 0) _ToolsCard(strings: s),
          if (_section == 0) SectionCard(
            title: s.t('general'),
            icon: Icons.tune_rounded,
            child: Column(
              children: [
                SwitchTile(
                  icon: Icons.bolt_rounded,
                  title: s.t('autoConnect'),
                  subtitle: s.t('autoConnectHint'),
                  value: value.autoConnect,
                  onChanged: (next) => settings.update((item) => item.autoConnect = next),
                ),
                SwitchTile(
                  icon: Icons.power_settings_new_rounded,
                  title: s.t('launchOnBoot'),
                  value: value.launchOnBoot,
                  onChanged: (next) async {
                    await settings.update((item) => item.launchOnBoot = next);
                    await VpnPlatform().setAutoStart(next, startInTray: settings.settings.startInTray);
                  },
                ),
                if (Platform.isWindows)
                  SwitchTile(
                    icon: Icons.move_to_inbox_rounded,
                    title: s.t('startInTray'),
                    subtitle: s.t('startInTrayHint'),
                    value: value.startInTray,
                    onChanged: (next) async {
                      await settings.update((item) => item.startInTray = next);
                      await VpnPlatform().setAutoStart(value.launchOnBoot, startInTray: next);
                    },
                  ),
                SwitchTile(
                  icon: Icons.notifications_none_rounded,
                  title: s.t('notifications'),
                  value: value.notifications,
                  onChanged: (next) => settings.update((item) => item.notifications = next),
                ),
                if (Platform.isWindows)
                  SettingsTile(
                    icon: Icons.close_rounded,
                    title: s.t('closeAction'),
                    trailing: NukefyDropdown<String>(
                      value: const ['ask', 'tray', 'exit'].contains(value.closeAction) ? value.closeAction : 'ask',
                      items: {
                        'ask': s.t('closeAsk'),
                        'tray': s.t('closeTray'),
                        'exit': s.t('closeExit'),
                      },
                      onChanged: (next) => settings.update((item) => item.closeAction = next),
                    ),
                  ),
              ],
            ),
          ),
          if (_section == 1) _AppearanceCard(settings: settings),
          if (_section == 0) SectionCard(
            title: s.t('subscriptionsSection'),
            icon: Icons.rss_feed_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchTile(
                  icon: Icons.fingerprint_rounded,
                  title: s.t('sendHwid'),
                  subtitle: s.t('sendHwidHint'),
                  value: value.sendHwid,
                  onChanged: (next) => settings.update((item) => item.sendHwid = next),
                ),
                SettingsTile(
                  icon: Icons.badge_outlined,
                  title: s.t('clientIdentity'),
                  subtitle: s.t('clientIdentityHint'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 2, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NukefyDropdown<String>(
                      value: SubscriptionService.clientUserAgents.containsKey(value.clientIdentity) ? value.clientIdentity : 'nukefy',
                      items: const {
                        'nukefy': 'Nukefy VPN',
                        'happ': 'Happ',
                        'v2rayng': 'v2rayNG',
                        'hiddify': 'Hiddify',
                        'streisand': 'Streisand',
                      },
                      onChanged: (next) => settings.update((item) => item.clientIdentity = next),
                    ),
                  ),
                ),
                SettingsTile(
                  icon: Icons.copy_rounded,
                  title: s.t('copyHwid'),
                  onTap: () async {
                    final id = await DeviceIdentity.load();
                    await Clipboard.setData(ClipboardData(text: id.hwid));
                    if (context.mounted) showNukefySnack(context, s.t('copied'));
                  },
                ),
              ],
            ),
          ),
          if (_section == 0) SectionCard(
            title: s.t('vpn'),
            icon: Icons.vpn_key_outlined,
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.alt_route_rounded,
                  title: s.t('routing'),
                  subtitle: _modeLabel(s, value.routingMode),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutingScreen())),
                ),
                if (Platform.isAndroid)
                  SettingsTile(
                    icon: Icons.apps_rounded,
                    title: s.t('perApp'),
                    subtitle: '${_perAppLabel(s, value.perAppMode)} · ${s.t('perAppHint')}',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerAppScreen())),
                  ),
                SettingsTile(
                  icon: Icons.dns_rounded,
                  title: s.t('dnsTitle'),
                  subtitle: '${value.dnsPreset} · ${value.proxyDns}',
                  onTap: () {
                    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS || MediaQuery.sizeOf(context).width >= 840;
                    if (desktop) {
                      context.read<NavProvider>().go(NavDestination.settingsDns);
                    } else {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DnsScreen()));
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('connectionMode'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(s.t('connectionModeHint'), style: context.palette.secondaryStyle),
                      const SizedBox(height: 10),
                      _ConnectionModeChoice(
                        tunEnabled: value.tunEnabled,
                        proxyLabel: s.t('proxyMode'),
                        tunLabel: s.t('tunMode'),
                        onChanged: (tun) => settings.update((item) {
                          item.tunEnabled = tun;
                          if (!tun) item.localProxyEnabled = true;
                        }),
                      ),
                    ],
                  ),
                ),
                SwitchTile(
                  icon: Icons.lan_outlined,
                  title: s.t('localProxy'),
                  subtitle: 'SOCKS ${value.socksPort} · HTTP ${value.httpPort}',
                  value: value.localProxyEnabled,
                  onChanged: (next) => settings.update((item) => item.localProxyEnabled = next),
                ),
                SwitchTile(
                  icon: Icons.block_rounded,
                  title: s.t('blockQuic'),
                  subtitle: s.t('blockQuicHint'),
                  value: value.blockQuic,
                  onChanged: (next) => settings.update((item) => item.blockQuic = next),
                ),
              ],
            ),
          ),
          if (_section == 0 && Platform.isAndroid)
            SectionCard(
              title: s.t('android'),
              icon: Icons.android_rounded,
              child: Column(
                children: [
                  SettingsTile(
                    icon: Icons.battery_charging_full_rounded,
                    title: s.t('battery'),
                    subtitle: s.t('batteryHint'),
                    onTap: () => VpnPlatform().requestBatteryOptimization(),
                  ),
                  SettingsTile(
                    icon: Icons.vpn_lock_rounded,
                    title: s.t('alwaysOn'),
                    subtitle: s.t('alwaysOnHint'),
                    onTap: () => VpnPlatform().openVpnSettings(),
                  ),
                  SettingsTile(
                    icon: Icons.dashboard_customize_rounded,
                    title: s.t('qsTile'),
                    subtitle: s.t('qsTileHint'),
                    onTap: () async {
                      final result = await VpnPlatform().requestAddTile();
                      if (!context.mounted) return;
                      // TILE_ADD_REQUEST_RESULT_TILE_ADDED = 2, ALREADY_ADDED = 1,
                      // NOT_ADDED = 0 (user declined — say nothing).
                      final message = switch (result) {
                        '2' || '1' || 'added' || 'already' => s.t('qsTileAdded'),
                        '0' => null,
                        _ => s.t('qsTileManual'),
                      };
                      if (message != null) showNukefySnack(context, message);
                    },
                  ),
                ],
              ),
            ),
          // Everything below is for people who know what they are doing.
          if (_section == 0) _MoreCard(
            title: s.t('more'),
            description: s.t('moreHint'),
            child: Column(
              children: [
                SwitchTile(
                  title: s.t('allowLan'),
                  value: value.allowLan,
                  onChanged: (next) => settings.update((item) => item.allowLan = next),
                ),
                SwitchTile(
                  title: s.t('blockIpv6'),
                  value: value.blockIpv6,
                  onChanged: (next) => settings.update((item) => item.blockIpv6 = next),
                ),
                if (!Platform.isAndroid)
                  SettingsTile(
                    icon: Icons.layers_outlined,
                    title: s.t('stack'),
                    trailing: NukefyDropdown<String>(
                      value: value.tunStack,
                      items: const {'mixed': 'mixed', 'system': 'system', 'gvisor': 'gVisor'},
                      onChanged: (next) => settings.update((item) => item.tunStack = next),
                    ),
                  ),
                const SizedBox(height: 8),
                const SizedBox(height: 12),
                const Divider(height: 1),
                _SliderTile(
                  title: '${s.t('mtu')}: ${value.mtu}',
                  value: value.mtu.clamp(1280, 9000).toDouble(),
                  min: 1280,
                  max: 9000,
                  divisions: 20,
                  onChanged: (next) => settings.update((item) => item.mtu = next.round()),
                ),
                SwitchTile(
                  title: s.t('fragment'),
                  value: value.tlsFragment,
                  onChanged: (next) => settings.update((item) => item.tlsFragment = next),
                ),
                SwitchTile(
                  title: s.t('recordFragment'),
                  value: value.recordFragment,
                  onChanged: (next) => settings.update((item) => item.recordFragment = next),
                ),
                _SliderTile(
                  title: '${s.t('fragmentDelay')}: ${value.fragmentFallbackMs}',
                  value: value.fragmentFallbackMs.clamp(10, 500).toDouble(),
                  min: 10,
                  max: 500,
                  divisions: 49,
                  onChanged: (next) => settings.update((item) => item.fragmentFallbackMs = next.round()),
                ),
                const Divider(height: 1),
                SwitchTile(
                  title: s.t('mux'),
                  value: value.muxEnabled,
                  onChanged: (next) => settings.update((item) => item.muxEnabled = next),
                ),
                SettingsTile(
                  icon: Icons.hub_outlined,
                  title: s.t('muxProtocol'),
                  trailing: NukefyDropdown<String>(
                    value: value.muxProtocol,
                    items: const {'h2mux': 'h2mux', 'smux': 'smux', 'yamux': 'yamux'},
                    onChanged: (next) => settings.update((item) => item.muxProtocol = next),
                  ),
                ),
                _SliderTile(
                  title: '${s.t('muxConnections')}: ${value.muxMaxConnections}',
                  value: value.muxMaxConnections.clamp(1, 8).toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  onChanged: (next) => settings.update((item) => item.muxMaxConnections = next.round()),
                ),
                SwitchTile(
                  title: s.t('muxPadding'),
                  value: value.muxPadding,
                  onChanged: (next) => settings.update((item) => item.muxPadding = next),
                ),
                const Divider(height: 1),
                SettingsTile(
                  icon: Icons.article_outlined,
                  title: s.t('showLog'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogScreen())),
                ),
                SettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: s.t('logLevel'),
                  trailing: NukefyDropdown<String>(
                    value: value.logLevel,
                    items: const {'debug': 'debug', 'info': 'info', 'warn': 'warn', 'error': 'error'},
                    onChanged: (next) => settings.update((item) => item.logLevel = next),
                  ),
                ),
                SettingsTile(
                  icon: Icons.upload_file_rounded,
                  title: s.t('exportConfig'),
                  onTap: () async {
                    final json = await context.read<VpnProvider>().currentConfig();
                    await SharePlus.instance.share(ShareParams(text: json));
                  },
                ),
                SettingsTile(
                  icon: Icons.download_rounded,
                  title: s.t('importConfig'),
                  onTap: () => ImportActions.fromFile(context),
                ),
                SettingsTile(
                  icon: Icons.restore_rounded,
                  title: s.t('reset'),
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: s.t('reset'),
                      body: s.t('resetBody'),
                      confirm: s.t('confirm'),
                      cancel: s.t('cancel'),
                    );
                    if (ok && context.mounted) await settings.reset();
                  },
                ),
              ],
            ),
          ),
          if (_section == 2) SectionCard(
            title: s.t('about'),
            icon: Icons.info_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsTile(
                  icon: Icons.system_update_alt_rounded,
                  title: s.t('checkUpdates'),
                  subtitle: '${s.t('version')} ${AppConstants.version}',
                  onTap: () => checkUpdatesFlow(context),
                ),
                SettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: s.t('diagnostics'),
                  subtitle: s.t('diagnosticsHint'),
                  onTap: () async {
                    final text = AppLog.read();
                    await Clipboard.setData(ClipboardData(text: text.isEmpty ? '(empty)' : text));
                    if (context.mounted) showNukefySnack(context, s.t('copied'));
                    final path = AppLog.path;
                    if (path != null && !Platform.isAndroid) await VpnPlatform().revealFile(path);
                  },
                ),
                SettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: s.t('author'),
                  subtitle: AppConstants.author,
                  onTap: () => launchUrl(Uri.parse(AppConstants.authorUrl), mode: LaunchMode.externalApplication),
                ),
                SettingsTile(
                  icon: Icons.code_rounded,
                  title: s.t('github'),
                  subtitle: AppConstants.githubRepo,
                  onTap: () => launchUrl(Uri.parse(AppConstants.githubUrl), mode: LaunchMode.externalApplication),
                ),
                SettingsTile(
                  icon: Icons.volunteer_activism_rounded,
                  title: s.t('donate'),
                  subtitle: s.t('donateHint'),
                  onTap: () => launchUrl(Uri.parse('https://pay.cloudtips.ru/p/cab48a6e'), mode: LaunchMode.externalApplication),
                ),
                SwitchTile(
                  icon: Icons.system_update_alt_rounded,
                  title: s.t('checkOnStart'),
                  value: value.checkUpdatesOnStart,
                  onChanged: (next) => settings.update((item) => item.checkUpdatesOnStart = next),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('${s.t('privacy')}\n${s.t('webrtc')}',
                      style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(dynamic s, RoutingMode mode) {
    return switch (mode) {
      RoutingMode.global => s.t('modeGlobal'),
      RoutingMode.blockedOnly => s.t('modeBlocked'),
      RoutingMode.bypassRu => s.t('modeBypass'),
      RoutingMode.custom => s.t('modeCustom'),
    };
  }

  String _perAppLabel(dynamic s, PerAppMode mode) {
    return switch (mode) {
      PerAppMode.off => s.t('perAppOff'),
      PerAppMode.include => s.t('perAppInclude'),
      PerAppMode.exclude => s.t('perAppExclude'),
    };
  }
}

class _UpdateBanner extends StatefulWidget {
  const _UpdateBanner();

  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  UpdateInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_check);
  }

  bool _noUpdates = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _noUpdates = false;
    });
    try {
      final info = await UpdateService().check();
      if (!mounted) return;
      final skipped = context.read<SettingsProvider>().settings.skippedVersion;
      final visible = info != null && info.version != skipped ? info : null;
      setState(() {
        _info = visible;
        _noUpdates = visible == null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final info = _info;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: info == null ? p.card : p.accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: info == null ? p.border : p.accent.withValues(alpha: .42)),
      ),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: p.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Icon(info == null ? Icons.system_update_alt_rounded : Icons.download_rounded, color: p.accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info == null ? s.t('checkUpdates') : '${s.t('updateAvailable')} · ${info.version}', style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    info == null
                        ? (_error ?? (_noUpdates && !_busy ? s.t('updatesNone') : s.t('updateCardHint')))
                        : s.t('updateCardHint'),
                    key: ValueKey(info == null ? (_error ?? (_noUpdates ? 'none' : 'hint')) : 'update'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: p.secondaryStyle,
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 4), SelectableText(_error!, style: p.captionStyle)],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else if (info != null)
            PopupMenuButton<String>(
              tooltip: s.t('actions'),
              onSelected: (value) async {
                if (value == 'open') await UpdateScreen.open(context, info);
                if (value == 'later') {
                  await context.read<SettingsProvider>().update((settings) => settings.skippedVersion = info.version);
                  if (mounted) setState(() => _info = null);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'open', child: Text(s.t('updateNow'))),
                PopupMenuItem(value: 'later', child: Text(s.t('later'))),
              ],
              icon: Icon(Icons.more_vert_rounded, color: p.accent),
            )
          else
            IconButton(onPressed: _check, tooltip: s.t('checkUpdates'), icon: Icon(Icons.refresh_rounded, color: p.accent)),
        ],
      ),
    );
  }
}

class _SettingsSubtabs extends StatelessWidget {
  const _SettingsSubtabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsProvider>().strings;
    final p = context.palette;
    final items = <(String, IconData)>[
      (s.t('settingsTab'), Icons.tune_rounded),
      (s.t('appearanceTab'), Icons.palette_outlined),
      (s.t('aboutTab'), Icons.info_outline_rounded),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == index,
                label: items[index].$1,
                child: InkWell(
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected == index ? p.background : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      border: Border(top: BorderSide(color: selected == index ? p.accent : Colors.transparent, width: 2.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[index].$2, size: 17, color: selected == index ? p.accent : p.textSecondary),
                        const SizedBox(width: 6),
                        Flexible(child: Text(items[index].$1, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppTextStyles.bodySecondary.copyWith(color: selected == index ? p.text : p.textSecondary, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.settings});

  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    final s = settings.strings;
    final value = settings.settings;
    return Column(
      children: [
        SectionCard(
          title: s.t('appearanceTab'),
          icon: Icons.palette_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsTile(icon: Icons.language_rounded, title: s.t('language'), trailing: NukefyDropdown<LanguagePreference>(value: value.language, items: {LanguagePreference.ru: s.t('russian'), LanguagePreference.en: s.t('english'), LanguagePreference.system: s.t('system')}, onChanged: (next) => settings.update((item) => item.language = next))),
              SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: s.t('theme'),
                trailing: NukefyDropdown<ThemePreference>(
                  value: value.theme,
                  items: {
                    ThemePreference.dark: s.t('dark'),
                    ThemePreference.light: s.t('light'),
                    ThemePreference.system: s.t('system'),
                  },
                  onChanged: (next) => settings.update((item) => item.theme = next),
                ),
              ),
              SettingsTile(icon: Icons.palette_outlined, title: s.t('themes'), subtitle: s.t('themesHint')),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 4 : constraints.maxWidth >= 440 ? 3 : 2;
                  final gap = 10.0;
                  final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < ThemePresets.all.entries.length; i++)
                          _ThemeChoice(
                            width: width,
                            label: '${i + 1}. ${_themeLabel(s, ThemePresets.all.entries.elementAt(i).key)}',
                            colors: Theme.of(context).brightness == Brightness.dark
                                ? ThemePresets.all.entries.elementAt(i).value.dark
                                : ThemePresets.all.entries.elementAt(i).value.light,
                            selected: value.visualTheme == ThemePresets.all.entries.elementAt(i).key,
                            onTap: () => settings.update((item) => item.visualTheme = ThemePresets.all.entries.elementAt(i).key),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionModeChoice extends StatelessWidget {
  const _ConnectionModeChoice({
    required this.tunEnabled,
    required this.proxyLabel,
    required this.tunLabel,
    required this.onChanged,
  });

  final bool tunEnabled;
  final String proxyLabel;
  final String tunLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 58,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeOption(
              selected: !tunEnabled,
              icon: Icons.lan_outlined,
              label: proxyLabel,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ModeOption(
              selected: tunEnabled,
              icon: Icons.router_outlined,
              label: tunLabel,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.selected, required this.icon, required this.label, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: .16) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? p.accent.withValues(alpha: .55) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: selected ? p.accent : p.textSecondary),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyRegular.copyWith(color: selected ? p.text : p.textSecondary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XrayCard extends StatelessWidget {
  const _XrayCard({required this.vpn, required this.strings});
  final VpnProvider vpn;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final core = vpn.xrayCore;
    final installed = core?.available == true;
    return SectionCard(
      title: strings.t('xrayCore'),
      icon: Icons.alt_route_rounded,
      trailing: IconButton(onPressed: () => vpn.refreshCore(), tooltip: strings.t('refresh'), icon: const Icon(Icons.refresh_rounded)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(installed ? strings.t('xrayInstalled') : strings.t('xrayNotInstalled'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(strings.t('xrayHint'), style: p.secondaryStyle),
        if (core?.version != null) ...[const SizedBox(height: 5), Text(core!.version!, style: p.captionStyle)],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: vpn.xrayCoreBusy ? null : () => installed ? _confirmXray(context) : _downloadXray(context),
            icon: vpn.xrayCoreBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
            label: Text(installed ? strings.t('xrayUpdate') : strings.t('xrayDownload')),
          ),
        ),
        if (installed)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: vpn.xrayCoreBusy ? null : () => _deleteXray(context),
              icon: Icon(Icons.delete_outline_rounded, color: p.error),
              label: Text(strings.t('deleteCore'), style: TextStyle(color: p.error)),
            ),
          ),
      ]),
    );
  }

  Future<void> _confirmXray(BuildContext context) async {
    final ok = await confirmDialog(context, title: strings.t('xrayUpdate'), body: strings.t('coreReinstallBody'), confirm: strings.t('confirm'), cancel: strings.t('cancel'));
    if (ok && context.mounted) await _downloadXray(context);
  }

  Future<void> _deleteXray(BuildContext context) async {
    final ok = await confirmDialog(context, title: strings.t('deleteCore'), body: strings.t('coreDeleteBody'), confirm: strings.t('delete'), cancel: strings.t('cancel'));
    if (ok && context.mounted) await vpn.deleteXrayCore();
  }

  Future<void> _downloadXray(BuildContext context) async {
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskProgressDialog<bool>(
        title: strings.t('xrayDownload'),
        subtitle: strings.t('downloading'),
        strings: strings,
        task: (progress) => vpn.downloadXrayCore(progress),
      ),
    );
    if (!context.mounted) return;
    if (result is String) {
      showNukefySnack(context, _xrayErrorText(strings, result), error: true);
    } else if (result == true) {
      showNukefySnack(context, strings.t('xrayInstalled'));
    }
  }
}

class _CoreCard extends StatelessWidget {
  const _CoreCard({required this.vpn, required this.strings});
  final VpnProvider vpn;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final p = context.palette;
    final core = vpn.core;
    final ready = core?.available ?? false;
    final checking = core == null;
    final color = checking ? p.textSecondary : (ready ? p.success : p.warning);
    final status = checking
        ? s.t('checking')
        : ready
            ? s.t('coreInstalledState')
            : s.t('coreMissing');
    final detail = core == null
        ? null
        : ready
            ? (core.version == null ? 'sing-box' : 'sing-box ${core.version}')
            : s.t('coreMissingHint');
    return SectionCard(
      title: s.t('core'),
      icon: Icons.memory_rounded,
      trailing: IconButton(
        tooltip: s.t('refresh'),
        onPressed: () => vpn.refreshCore(),
        icon: Icon(Icons.refresh_rounded, color: p.textSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status: icon badge on the left, one text block next to it — the
          // old row floated a bare string between a dot and a button.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  checking
                      ? Icons.hourglass_top_rounded
                      : ready
                          ? Icons.verified_rounded
                          : Icons.download_rounded,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: p.text),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.monoValue.copyWith(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(s.t('coreWindows'), style: context.palette.secondaryStyle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ready
                  ? OutlinedButton.icon(
                      onPressed: vpn.coreBusy ? null : () => _confirmCoreDownload(context),
                      icon: const Icon(Icons.update_rounded),
                      label: Text(s.t('reinstallCore')),
                    )
                  : FilledButton.icon(
                      onPressed: vpn.coreBusy ? null : () => _downloadCore(context),
                      icon: vpn.coreBusy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: Text(s.t('downloadCore')),
                    ),
              if (ready)
                TextButton.icon(
                  onPressed: vpn.coreBusy ? null : () => _deleteCore(context),
                  icon: Icon(Icons.delete_outline_rounded, color: p.error),
                  label: Text(s.t('deleteCore'), style: TextStyle(color: p.error)),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
          Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Collapsible block for the knobs most users never touch.
class _MoreCard extends StatefulWidget {
  const _MoreCard({required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  State<_MoreCard> createState() => _MoreCardState();
}

class _MoreCardState extends State<_MoreCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.science_outlined, size: 18, color: p.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title.toUpperCase(), style: context.palette.sectionStyle),
                        if (widget.description != null)
                          Text(widget.description!, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 220),
                    turns: _open ? 0.5 : 0,
                    child: Icon(Icons.expand_more_rounded, size: 22, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: widget.child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Maps a core download failure code to a readable, localized message.
String _coreErrorText(S s, String raw) {
  return switch (raw) {
    'no-core-asset' => s.t('coreNoAsset'),
    'unsupported-archive' => s.t('coreBadArchive'),
    'extract-failed' => s.t('coreExtractFail'),
    _ => NetworkDiagnostics.textOrRaw(raw, s.t),
  };
}

String _xrayErrorText(S s, String raw) {
  if (raw.contains('xray-platform-unsupported')) return s.t('xrayPlatformUnsupported');
  if (raw.contains('xray-no-digest') || raw.contains('xray-integrity-failed')) return s.t('xrayIntegrity');
  if (raw.contains('xray-no-asset')) return s.t('xrayNoAsset');
  return NetworkDiagnostics.textOrRaw(raw, s.t);
}

Future<void> _downloadCore(BuildContext context) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  final result = await showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TaskProgressDialog<bool>(
      title: s.t('downloadCore'),
      subtitle: s.t('downloading'),
      strings: s,
      task: (onProgress) => vpn.downloadCore(onProgress),
    ),
  );
  if (!context.mounted) return;
  if (result is String) {
    showNukefySnack(context, _coreErrorText(s, result), error: true);
    return;
  }
  if (result == true) {
    // The card above now shows "installed · version"; the snack just confirms.
    final version = vpn.core?.version;
    showNukefySnack(context, version == null ? s.t('coreInstalled') : '${s.t('coreInstalled')} · sing-box $version');
    return;
  }
  showNukefySnack(context, s.t('coreExtractFail'), error: true);
}

Future<void> _confirmCoreDownload(BuildContext context) async {
  final s = context.read<SettingsProvider>().strings;
  final ok = await confirmDialog(context, title: s.t('reinstallCore'), body: s.t('coreReinstallBody'), confirm: s.t('confirm'), cancel: s.t('cancel'));
  if (ok && context.mounted) await _downloadCore(context);
}

Future<void> _deleteCore(BuildContext context) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  final ok = await confirmDialog(context, title: s.t('deleteCore'), body: s.t('coreDeleteBody'), confirm: s.t('delete'), cancel: s.t('cancel'));
  if (ok && context.mounted) await vpn.deleteCore();
}

Future<void> checkUpdatesFlow(BuildContext context, {bool silentIfCurrent = false}) async {
  final s = context.read<SettingsProvider>().strings;
  try {
    final info = await UpdateService().check();
    if (!context.mounted) return;
    if (info == null) {
      if (!silentIfCurrent) showNukefySnack(context, s.t('upToDate'));
      return;
    }
    await UpdateScreen.open(context, info);
  } on Exception catch (error) {
    if (silentIfCurrent || !context.mounted) return;
    final message = '$error'.contains('404') ? s.t('noReleases') : NetworkDiagnostics.textOrRaw(error, s.t);
    showNukefySnack(context, message, error: true);
  }
}

class _TaskProgressDialog<T> extends StatefulWidget {
  const _TaskProgressDialog({
    required this.title,
    required this.subtitle,
    required this.strings,
    required this.task,
  });

  final String title;
  final String subtitle;
  final S strings;
  final Future<T> Function(void Function(DownloadProgress) onProgress) task;

  @override
  State<_TaskProgressDialog<T>> createState() => _TaskProgressDialogState<T>();
}

class _TaskProgressDialogState<T> extends State<_TaskProgressDialog<T>> {
  DownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_run);
  }

  Future<void> _run() async {
    try {
      final value = await widget.task((next) {
        if (mounted) setState(() => _progress = next);
      });
      if (mounted) Navigator.pop(context, value);
    } catch (error) {
      if (mounted) Navigator.pop(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return NukefyProgressDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      progress: _progress,
      strings: widget.strings,
    );
  }
}


class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.width, required this.label, required this.colors, required this.selected, required this.onTap});
  final double width;
  final String label;
  final ThemePalette colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: selected ? 1.03 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: width,
            height: 82,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: selected ? colors.accent : p.border, width: selected ? 2 : 1),
              boxShadow: selected ? [BoxShadow(color: colors.accent.withValues(alpha: .25), blurRadius: 13)] : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.text, fontWeight: FontWeight.w800, fontSize: 11))),
                if (selected) Icon(Icons.check_circle_rounded, color: colors.accent, size: 15),
              ]),
              const Spacer(),
              Container(height: 13, decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(5)), child: Row(children: [Expanded(flex: 3, child: Container(decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(5)))), const SizedBox(width: 3), Expanded(child: Container(decoration: BoxDecoration(color: colors.accent2, borderRadius: BorderRadius.circular(5))))])),
              const SizedBox(height: 5),
              Row(children: [for (final color in [colors.border, colors.success, colors.accent]) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: color, shape: BoxShape.circle))]),
            ]),
          ),
        ),
      ),
    );
  }
}

String _themeLabel(S s, String name) => s.t('theme_$name');

/// Windows repair corner: the full network-reset ladder the community uses
/// (Winsock, TCP/IP, WinHTTP proxy, DHCP lease, DNS cache) and a permanent
/// Cloudflare WARP kill switch.
class _ToolsCard extends StatefulWidget {
  const _ToolsCard({required this.strings});
  final S strings;

  @override
  State<_ToolsCard> createState() => _ToolsCardState();
}

class _ToolsCardState extends State<_ToolsCard> {
  List<String> _services = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final lines = await VpnPlatform().warpStatus();
    if (!mounted) return;
    setState(() {
      _services = lines;
      _loading = false;
    });
  }

  Future<void> _act(bool disable) async {
    if (disable) {
      final ok = await confirmDialog(
        context,
        title: widget.strings.t('warpTitle'),
        body: widget.strings.t('warpOffWarn'),
        confirm: widget.strings.t('warpOffBtn'),
        cancel: widget.strings.t('cancel'),
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final platform = VpnPlatform();
    final result = disable ? await platform.disableWarp() : await platform.enableWarp();
    if (!mounted) return;
    await context.read<SettingsProvider>().update((item) => item.warpDisabled = disable);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    showNukefySnack(
      context,
      result.startsWith('ok') || result.isEmpty
          ? widget.strings.t(disable ? 'warpOffDone' : 'warpOnDone')
          : result,
    );
  }

  String _warpSubtitle(S s) {
    if (_busy) return s.t('warpWorking');
    if (_loading) return s.t('warpLoading');
    if (_services.isEmpty) return s.t('warpNotFound');
    return _services.map((line) {
      final parts = line.split('|');
      if (parts.length < 3) return line;
      final status = parts[1] == 'Running' ? s.t('warpStateRunning') : s.t('warpStateStopped');
      final start = parts[2] == 'Disabled'
          ? s.t('warpStartDisabled')
          : parts[2] == 'Automatic'
              ? s.t('warpStartAuto')
              : s.t('warpStartManual');
      return '${parts[0]}: $status, $start';
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return SectionCard(
      title: strings.t('netResetTitle'),
      icon: Icons.build_circle_outlined,
      child: Column(
        children: [
          SettingsTile(
            icon: Icons.refresh_rounded,
            title: strings.t('netResetRun'),
            subtitle: strings.t('netResetHint'),
            trailing: FilledButton.icon(
              onPressed: () async {
                final result = await VpnPlatform().windowsNetworkReset();
                if (!context.mounted) return;
                showNukefySnack(context, result == 'ok-reboot' ? '${strings.t('netResetTitle')}: OK — ${strings.t('restart')}' : result);
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(strings.t('netResetRun')),
            ),
          ),
          SettingsTile(
            icon: Icons.cloud_outlined,
            title: strings.t('warpTitle'),
            subtitle: _warpSubtitle(strings),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: strings.t('refresh'),
                  onPressed: _loading || _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: _busy || _loading ? null : () => _act(true),
                  child: Text(strings.t('warpOffBtn')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy || _loading ? null : () => _act(false),
                  child: Text(strings.t('warpOnBtn')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
