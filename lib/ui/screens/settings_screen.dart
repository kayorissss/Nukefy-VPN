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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = settings.strings;
    final value = settings.settings;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(s.t('settings'), style: AppTextStyles.title),
          const SizedBox(height: 14),
          // The core has to be downloaded before anything else works, so it
          // sits at the very top instead of hiding under MUX and Telegram.
          SectionCard(
            title: s.t('core'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vpn.core == null
                      ? s.t('checking')
                      : vpn.core!.available
                          ? '${s.t('coreReady')}${vpn.core!.version == null ? '' : ' · ${vpn.core!.version}'}'
                          : s.t('coreMissing'),
                  style: AppTextStyles.bodyRegular,
                ),
                const SizedBox(height: 6),
                Text(Platform.isAndroid ? s.t('coreAndroid') : s.t('coreWindows'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: vpn.coreBusy ? null : () => _downloadCore(context),
                    icon: vpn.coreBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(s.t('downloadCore')),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => vpn.refreshCore(),
                    child: Text(s.t('refresh')),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          SectionCard(
            title: s.t('general'),
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: s.t('theme'),
                  trailing: DropdownButton<ThemePreference>(
                    value: value.theme,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: ThemePreference.dark, child: Text(s.t('dark'))),
                      DropdownMenuItem(value: ThemePreference.light, child: Text(s.t('light'))),
                      DropdownMenuItem(value: ThemePreference.system, child: Text(s.t('system'))),
                    ],
                    onChanged: (next) {
                      if (next != null) settings.update((item) => item.theme = next);
                    },
                  ),
                ),
                SettingsTile(
                  icon: Icons.language_rounded,
                  title: s.t('language'),
                  trailing: DropdownButton<LanguagePreference>(
                    value: value.language,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: LanguagePreference.ru, child: Text(s.t('russian'))),
                      DropdownMenuItem(value: LanguagePreference.en, child: Text(s.t('english'))),
                      DropdownMenuItem(value: LanguagePreference.system, child: Text(s.t('system'))),
                    ],
                    onChanged: (next) {
                      if (next != null) settings.update((item) => item.language = next);
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('autoConnect'), style: AppTextStyles.bodyRegular),
                  value: value.autoConnect,
                  onChanged: (next) => settings.update((item) => item.autoConnect = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('launchOnBoot'), style: AppTextStyles.bodyRegular),
                  value: value.launchOnBoot,
                  onChanged: (next) async {
                    await settings.update((item) => item.launchOnBoot = next);
                    await VpnPlatform().setAutoStart(next);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('notifications'), style: AppTextStyles.bodyRegular),
                  value: value.notifications,
                  onChanged: (next) => settings.update((item) => item.notifications = next),
                ),
                if (Platform.isWindows)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.t('minimizeToTray'), style: AppTextStyles.bodyRegular),
                    value: value.minimizeToTray,
                    onChanged: (next) => settings.update((item) => item.minimizeToTray = next),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('vpn'),
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.alt_route_rounded,
                  title: s.t('routing'),
                  subtitle: _modeLabel(s, value.routingMode),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutingScreen())),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('tun'), style: AppTextStyles.bodyRegular),
                  subtitle: Text(s.t('tunHint'), style: AppTextStyles.bodySecondary),
                  value: value.tunEnabled,
                  onChanged: (next) => settings.update((item) => item.tunEnabled = next),
                ),
                SettingsTile(
                  icon: Icons.layers_outlined,
                  title: s.t('stack'),
                  trailing: DropdownButton<String>(
                    value: value.tunStack,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'mixed', child: Text('mixed')),
                      DropdownMenuItem(value: 'system', child: Text('system')),
                      DropdownMenuItem(value: 'gvisor', child: Text('gVisor')),
                    ],
                    onChanged: (next) {
                      if (next != null) settings.update((item) => item.tunStack = next);
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('localProxy'), style: AppTextStyles.bodyRegular),
                  subtitle: Text('SOCKS ${value.socksPort} · HTTP ${value.httpPort}', style: AppTextStyles.monoValue),
                  value: value.localProxyEnabled,
                  onChanged: (next) => settings.update((item) => item.localProxyEnabled = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('allowLan'), style: AppTextStyles.bodyRegular),
                  value: value.allowLan,
                  onChanged: (next) => settings.update((item) => item.allowLan = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('blockQuic'), style: AppTextStyles.bodyRegular),
                  value: value.blockQuic,
                  onChanged: (next) => settings.update((item) => item.blockQuic = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('blockIpv6'), style: AppTextStyles.bodyRegular),
                  value: value.blockIpv6,
                  onChanged: (next) => settings.update((item) => item.blockIpv6 = next),
                ),
                TextField(
                  key: ValueKey('proxy-${value.proxyDns}'),
                  controller: TextEditingController(text: value.proxyDns),
                  decoration: InputDecoration(labelText: s.t('proxyDns')),
                  onSubmitted: (text) => settings.update((item) => item.proxyDns = text.trim()),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: ValueKey('direct-${value.directDns}'),
                  controller: TextEditingController(text: value.directDns),
                  decoration: InputDecoration(labelText: s.t('directDns')),
                  onSubmitted: (text) => settings.update((item) => item.directDns = text.trim()),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SectionCard(
            title: s.t('antiblockTitle'),
            child: Column(
              children: [
                Text(s.t('antiblockHint'), style: AppTextStyles.bodySecondary),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('antiblockTitle'), style: AppTextStyles.bodyRegular),
                  value: value.antiblock,
                  onChanged: (next) => settings.update((item) => item.antiblock = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('preferBridge'), style: AppTextStyles.bodyRegular),
                  value: value.preferBridge,
                  onChanged: (next) => settings.update((item) => item.preferBridge = next),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          // Knobs that almost nobody needs: MUX, TLS fragmentation, MTU.
          _MoreCard(
            title: s.t('more'),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s.t('mtu')}: ${value.mtu}', style: AppTextStyles.bodyRegular),
                  subtitle: Slider(
                    value: value.mtu.clamp(1280, 9000).toDouble(),
                    min: 1280,
                    max: 9000,
                    divisions: 20,
                    label: '${value.mtu}',
                    onChanged: (next) => settings.update((item) => item.mtu = next.round()),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('fragment'), style: AppTextStyles.bodyRegular),
                  value: value.tlsFragment,
                  onChanged: (next) => settings.update((item) => item.tlsFragment = next),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('recordFragment'), style: AppTextStyles.bodyRegular),
                  value: value.recordFragment,
                  onChanged: (next) => settings.update((item) => item.recordFragment = next),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s.t('fragmentDelay')}: ${value.fragmentFallbackMs}', style: AppTextStyles.bodyRegular),
                  subtitle: Slider(
                    value: value.fragmentFallbackMs.clamp(10, 500).toDouble(),
                    min: 10,
                    max: 500,
                    divisions: 49,
                    onChanged: (next) => settings.update((item) => item.fragmentFallbackMs = next.round()),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('mux'), style: AppTextStyles.bodyRegular),
                  value: value.muxEnabled,
                  onChanged: (next) => settings.update((item) => item.muxEnabled = next),
                ),
                SettingsTile(
                  icon: Icons.hub_outlined,
                  title: s.t('muxProtocol'),
                  trailing: DropdownButton<String>(
                    value: value.muxProtocol,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'h2mux', child: Text('h2mux')),
                      DropdownMenuItem(value: 'smux', child: Text('smux')),
                      DropdownMenuItem(value: 'yamux', child: Text('yamux')),
                    ],
                    onChanged: (next) {
                      if (next != null) settings.update((item) => item.muxProtocol = next);
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s.t('muxConnections')}: ${value.muxMaxConnections}', style: AppTextStyles.bodyRegular),
                  subtitle: Slider(
                    value: value.muxMaxConnections.clamp(1, 8).toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    onChanged: (next) => settings.update((item) => item.muxMaxConnections = next.round()),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('muxPadding'), style: AppTextStyles.bodyRegular),
                  value: value.muxPadding,
                  onChanged: (next) => settings.update((item) => item.muxPadding = next),
                ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('telegram'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('telegramHelp'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(AppConstants.telegramProxyUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(s.t('telegramButton')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (Platform.isAndroid)
            SectionCard(
              title: s.t('apps'),
              child: Column(
                children: [
                  SettingsTile(
                    icon: Icons.apps_rounded,
                    title: s.t('perApp'),
                    subtitle: _perAppLabel(s, value.perAppMode),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerAppScreen())),
                  ),
                  SettingsTile(
                    icon: Icons.battery_charging_full_rounded,
                    title: s.t('battery'),
                    onTap: () => VpnPlatform().requestBatteryOptimization(),
                  ),
                  SettingsTile(
                    icon: Icons.vpn_lock_rounded,
                    title: s.t('alwaysOn'),
                    onTap: () => VpnPlatform().openVpnSettings(),
                  ),
                ],
              ),
            ),
          SectionCard(
            title: s.t('advanced'),
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.article_outlined,
                  title: s.t('showLog'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogScreen())),
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
                SettingsTile(
                  icon: Icons.tune_rounded,
                  title: s.t('logLevel'),
                  trailing: DropdownButton<String>(
                    value: value.logLevel,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'debug', child: Text('debug')),
                      DropdownMenuItem(value: 'info', child: Text('info')),
                      DropdownMenuItem(value: 'warn', child: Text('warn')),
                      DropdownMenuItem(value: 'error', child: Text('error')),
                    ],
                    onChanged: (next) {
                      if (next != null) settings.update((item) => item.logLevel = next);
                    },
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('about'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: s.t('version'),
                  subtitle: AppConstants.version,
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('checkOnStart'), style: AppTextStyles.bodyRegular),
                  value: value.checkUpdatesOnStart,
                  onChanged: (next) => settings.update((item) => item.checkUpdatesOnStart = next),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => checkUpdatesFlow(context),
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: Text(s.t('checkUpdates')),
                  ),
                ),
                const SizedBox(height: 10),
                Text(s.t('privacy'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 6),
                Text(s.t('webrtc'), style: AppTextStyles.bodySecondary),
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

/// Collapsible block for the knobs most users never touch.
class _MoreCard extends StatefulWidget {
  const _MoreCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_MoreCard> createState() => _MoreCardState();
}

class _MoreCardState extends State<_MoreCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Text(widget.title.toUpperCase(), style: AppTextStyles.section),
                  const Spacer(),
                  Icon(
                    _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: widget.child,
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
  // A successful install reports success — never the binary path.
  showNukefySnack(context, s.t('coreInstalled'));
}

Future<void> checkUpdatesFlow(BuildContext context, {bool silentIfCurrent = false}) async {
  final s = context.read<SettingsProvider>().strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final info = await UpdateService().check();
    if (!context.mounted) return;
    if (info == null) {
      if (!silentIfCurrent) showNukefySnack(context, s.t('upToDate'));
      return;
    }
    if (!context.mounted) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('updateAvailable')),
        content: Text('${s.t('newVersion')}: ${info.version}\n\n${info.notes}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('later'))),
          if (!info.hasAsset)
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse(info.htmlUrl), mode: LaunchMode.externalApplication);
                Navigator.pop(context, false);
              },
              child: Text(s.t('openRelease')),
            ),
          if (info.hasAsset)
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('download'))),
        ],
      ),
    );
    if (start != true || !context.mounted) return;
    final file = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TaskProgressDialog<File>(
        title: s.t('updateTitle'),
        subtitle: '${s.t('newVersion')} ${info.version}',
        strings: s,
        task: (onProgress) => UpdateService().download(info, onProgress: onProgress),
      ),
    );
    if (file is! File || !context.mounted) {
      if (file is String && context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(file)));
      }
      return;
    }
    if (Platform.isAndroid && file.path.endsWith('.apk')) {
      await VpnPlatform().installApk(file.path);
    } else {
      await VpnPlatform().revealFile(file.path);
    }
    if (context.mounted) showNukefySnack(context, s.t('ready'));
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
