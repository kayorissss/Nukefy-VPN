import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/update_service.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../dialogs/progress_dialog.dart';
import '../import_actions.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';
import 'log_screen.dart';
import 'per_app_screen.dart';
import 'routing_screen.dart';
import 'update_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          // Telegram proxy is the thing people look for first when the
          // messenger is throttled — so it goes right on top.
          _TelegramCard(strings: s),
          // Desktop downloads sing-box as a separate binary; Android ships
          // the core inside the APK (libbox), so there is nothing to install.
          if (!Platform.isAndroid) _CoreCard(vpn: vpn, strings: s),
          SectionCard(
            title: s.t('general'),
            icon: Icons.tune_rounded,
            child: Column(
              children: [
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
                SettingsTile(
                  icon: Icons.language_rounded,
                  title: s.t('language'),
                  trailing: NukefyDropdown<LanguagePreference>(
                    value: value.language,
                    items: {
                      LanguagePreference.ru: s.t('russian'),
                      LanguagePreference.en: s.t('english'),
                      LanguagePreference.system: s.t('system'),
                    },
                    onChanged: (next) => settings.update((item) => item.language = next),
                  ),
                ),
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
                    await VpnPlatform().setAutoStart(next);
                  },
                ),
                SwitchTile(
                  icon: Icons.notifications_none_rounded,
                  title: s.t('notifications'),
                  value: value.notifications,
                  onChanged: (next) => settings.update((item) => item.notifications = next),
                ),
                if (Platform.isWindows)
                  SwitchTile(
                    icon: Icons.minimize_rounded,
                    title: s.t('minimizeToTray'),
                    value: value.minimizeToTray,
                    onChanged: (next) => settings.update((item) => item.minimizeToTray = next),
                  ),
              ],
            ),
          ),
          SectionCard(
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
                if (!Platform.isAndroid)
                  SwitchTile(
                    icon: Icons.router_outlined,
                    title: s.t('tun'),
                    subtitle: s.t('tunHint'),
                    value: value.tunEnabled,
                    onChanged: (next) => settings.update((item) => item.tunEnabled = next),
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
          if (Platform.isAndroid)
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
          _MoreCard(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(s.t('dnsHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: ValueKey('proxy-${value.proxyDns}'),
                  controller: TextEditingController(text: value.proxyDns),
                  decoration: InputDecoration(labelText: s.t('proxyDns'), helperText: s.t('proxyDnsHint')),
                  onSubmitted: (text) => settings.update((item) => item.proxyDns = text.trim()),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: ValueKey('direct-${value.directDns}'),
                  controller: TextEditingController(text: value.directDns),
                  decoration: InputDecoration(labelText: s.t('directDns'), helperText: s.t('directDnsHint')),
                  onSubmitted: (text) => settings.update((item) => item.directDns = text.trim()),
                ),
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
          SectionCard(
            title: s.t('about'),
            icon: Icons.info_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsTile(
                  icon: Icons.tag_rounded,
                  title: s.t('version'),
                  subtitle: AppConstants.version,
                  trailing: TextButton(
                    onPressed: () => checkUpdatesFlow(context),
                    child: Text(s.t('checkUpdates')),
                  ),
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

class _TelegramCard extends StatelessWidget {
  const _TelegramCard({required this.strings});
  final S strings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const tg = Color(0xFF2AABEE);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => launchUrl(Uri.parse(AppConstants.telegramProxyUrl), mode: LaunchMode.externalApplication),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tg.withValues(alpha: p.isDark ? 0.22 : 0.16), p.accent2.withValues(alpha: 0.10)],
              ),
              border: Border.all(color: tg.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: tg, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.t('telegramButton'), style: AppTextStyles.headline.copyWith(fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(strings.t('telegramHelp'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new_rounded, color: p.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
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
    final color = core == null ? p.textSecondary : (ready ? p.success : AppColors.warning);
    final status = core == null
        ? s.t('checking')
        : ready
            ? '${s.t('coreInstalledState')}${core.version == null ? '' : ' · sing-box ${core.version}'}'
            : s.t('coreMissing');
    return SectionCard(
      title: s.t('core'),
      icon: Icons.memory_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(status, key: ValueKey(status), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              IconButton(
                tooltip: s.t('refresh'),
                onPressed: () => vpn.refreshCore(),
                icon: Icon(Icons.refresh_rounded, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.t('coreWindows'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ready
                ? OutlinedButton.icon(
                    onPressed: vpn.coreBusy ? null : () => _downloadCore(context),
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
  bool _open = false;

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
                        Text(widget.title.toUpperCase(), style: AppTextStyles.section),
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
    _ => raw,
  };
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
    final message = '$error'.contains('404') ? s.t('noReleases') : s.t('networkError');
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
    widget.task((next) {
      if (mounted) setState(() => _progress = next);
    }).then((value) {
      if (mounted) Navigator.pop(context, value);
    }).catchError((Object error) {
      if (mounted) Navigator.pop(context, '$error');
    });
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
