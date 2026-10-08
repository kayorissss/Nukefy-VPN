import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/uninstaller_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';

/// Own uninstall flow: preview of what will be deleted, checkboxes for the
/// parts that are the user's choice, and a final red confirmation. Closes the
/// app when the cleanup script is on its way.
class UninstallScreen extends StatefulWidget {
  const UninstallScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UninstallScreen()),
      );

  @override
  State<UninstallScreen> createState() => _UninstallScreenState();
}

class _UninstallScreenState extends State<UninstallScreen> {
  bool _zapret = true;
  bool _autostart = true;
  bool _data = true;
  bool _appFiles = true;
  bool _busy = false;

  /// The cleanup helper is running: the screen shows a live progress note
  /// instead of an apparently frozen button.
  bool _waiting = false;

  Future<void> _run() async {
    final s = context.read<SettingsProvider>().strings;
    final ok = await confirmDialog(
      context,
      title: s.t('uninstallConfirmTitle'),
      body: s.t('uninstallConfirmBody'),
      confirm: s.t('uninstallConfirm'),
      cancel: s.t('cancel'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    // Never let a failure leave the button spinning forever: the window used
    // to look frozen when the elevated helper could not be started.
    try {
      await UninstallerService.instance
          .start(UninstallOptions(
            stopZapret: _zapret,
            removeAutostart: _autostart,
            removeUserData: _data,
            removeAppFiles: _appFiles,
          ))
          .timeout(const Duration(seconds: 25));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showNukefySnack(context, '${s.t('uninstallFailed')}\n$error', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _waiting = true);
    showNukefySnack(context, s.t('uninstallRunning'));
    // Wait for the marker the cleanup script drops, not for a stopwatch: the
    // window used to sit "frozen" and then close while the script was still
    // working. 90 s is the script's own upper bound (it waits for this process
    // to exit first), the hard stop keeps a broken helper from hanging the UI.
    final flag = File(UninstallerService.doneFlagPath);
    final clock = Stopwatch()..start();
    while (mounted && clock.elapsed < const Duration(seconds: 95)) {
      if (flag.existsSync()) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!mounted) return;
    // Kill the whole process tree: a stray core or winws must not keep the
    // folder locked while the cleanup script is deleting it.
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsProvider>().strings;
    final p = context.palette;
    final canDeleteApp = Platform.isWindows;
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.error.withValues(alpha: .4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('uninstallTitle'), style: AppTextStyles.headline.copyWith(fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(s.t('uninstallBody'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: s.t('uninstallRemove'),
          icon: Icons.checklist_rounded,
          child: Column(
            children: [
              SwitchTile(
                icon: Icons.gpp_maybe_outlined,
                title: s.t('uninstallZapret'),
                subtitle: s.t('uninstallZapretHint'),
                value: _zapret,
                onChanged: _busy ? (_) {} : (next) => setState(() => _zapret = next),
              ),
              SwitchTile(
                icon: Icons.restart_alt_rounded,
                title: s.t('uninstallAutostart'),
                subtitle: s.t('uninstallAutostartHint'),
                value: _autostart,
                onChanged: _busy ? (_) {} : (next) => setState(() => _autostart = next),
              ),
              SwitchTile(
                icon: Icons.folder_delete_outlined,
                title: s.t('uninstallData'),
                subtitle: s.t('uninstallDataHint'),
                value: _data,
                onChanged: _busy ? (_) {} : (next) => setState(() => _data = next),
              ),
              if (canDeleteApp)
                SwitchTile(
                  icon: Icons.apps_outlined,
                  title: s.t('uninstallApp'),
                  subtitle: s.t('uninstallAppHint'),
                  value: _appFiles,
                  onChanged: _busy ? (_) {} : (next) => setState(() => _appFiles = next),
                ),
            ],
          ),
        ),
        SectionCard(
          title: s.t('uninstallHow'),
          icon: Icons.science_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _waiting ? s.t('uninstallRunning') : s.t('uninstallHowBody'),
                style: AppTextStyles.bodySecondary.copyWith(color: _waiting ? p.accent : p.textSecondary),
              ),
              if (_waiting) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: const LinearProgressIndicator(minHeight: 5),
                ),
              ],
              const SizedBox(height: 12),
              NukefyActionButton(
                label: s.t('uninstallConfirm'),
                icon: Icons.delete_forever_rounded,
                onPressed: _busy ? null : _run,
              ),
            ],
          ),
        ),
      ],
    );
    if (Navigator.of(context).canPop()) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.t('uninstallTitle')),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(bottom: false, child: content),
      );
    }
    return SafeArea(bottom: false, child: content);
  }
}
