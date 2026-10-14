import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_text_styles.dart';
import '../dialogs/auto_setup_dialog.dart';
import '../dialogs/progress_dialog.dart';
import '../import_actions.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';
import 'log_screen.dart';

/// "Дополнения": cores (sing-box + Xray for XHTTP), Telegram proxy and
/// service tools. Everything shows real status from the actual binaries.
class ExtrasScreen extends StatelessWidget {
  const ExtrasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final vpn = context.watch<VpnProvider>();
    final s = settings.strings;
    final core = vpn.core;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('addons'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(s.t('addonsBody'), style: AppTextStyles.bodySecondary),
          const SizedBox(height: 14),
          SectionCard(
            title: s.t('autoSetup'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('autoSetupBody'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => showAutoSetupDialog(context),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text(s.t('autoSetupRun')),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          SectionCard(
            title: s.t('core'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  core == null
                      ? s.t('checking')
                      : core.available
                          ? '${s.t('coreReady')}${core.version == null ? '' : ' · ${core.version}'}'
                          : s.t('coreMissing'),
                  style: AppTextStyles.bodyRegular,
                ),
                const SizedBox(height: 6),
                Text(
                  Platform.isAndroid ? s.t('coreAndroid') : s.t('coreWindows'),
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: vpn.coreBusy ? null : () => _downloadCore(context),
                      child: Text(s.t('downloadCore')),
                    ),
                    TextButton(
                      onPressed: () => vpn.refreshCore(),
                      child: Text(s.t('refresh')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          SectionCard(
            title: s.t('xrayCore'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  core == null
                      ? s.t('checking')
                      : core.xray
                          ? s.t('xrayReady')
                          : s.t('xrayMissing'),
                  style: AppTextStyles.bodyRegular,
                ),
                const SizedBox(height: 6),
                Text(s.t('xrayCoreBody'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: vpn.coreBusy ? null : () => _downloadXray(context),
                      child: Text(s.t('downloadXray')),
                    ),
                    TextButton(
                      onPressed: () => vpn.refreshCore(),
                      child: Text(s.t('refresh')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          SectionCard(
            title: s.t('telegram'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('telegramHelp'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(AppConstants.telegramProxyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(s.t('telegramButton')),
                  ),
                ),
                const SizedBox(height: 6),
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LogScreen()),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _downloadCore(BuildContext context) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  final result = await showTaskProgressDialog<String>(
    context,
    title: s.t('downloadCore'),
    subtitle: s.t('downloading'),
    strings: s,
    task: (onProgress) => vpn.downloadCore(onProgress),
  );
  if (!context.mounted) return;
  final failed = result is String;
  showNukefySnack(context, failed ? result : s.t('coreInstalled'), error: failed);
}

Future<void> _downloadXray(BuildContext context) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  final result = await showTaskProgressDialog<String>(
    context,
    title: s.t('downloadXray'),
    subtitle: s.t('downloading'),
    strings: s,
    task: (onProgress) => vpn.downloadXray(onProgress),
  );
  if (!context.mounted) return;
  final failed = result is String;
  showNukefySnack(context, failed ? result : s.t('xrayReady'), error: failed);
}
