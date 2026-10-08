import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/addons_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';
import '../widgets/section_card.dart';

/// "Дополнения и программы": optional payloads downloaded from the author's
/// repositories on demand, so the shipped app stays small.
class AddonsScreen extends StatefulWidget {
  const AddonsScreen({super.key});

  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen> {
  final _addons = AddonsService.instance;

  S get s => context.read<SettingsProvider>().strings;

  @override
  void initState() {
    super.initState();
    _addons.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _addons.catalog.isEmpty && !_addons.loading) _addons.refreshCatalog();
    });
  }

  @override
  void dispose() {
    _addons.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _install(String name) async {
    await _addons.install(name);
    if (!mounted) return;
    showNukefySnack(
      context,
      _addons.error == null ? s.t('addonsInstalledOk') : '${_addons.error}',
      error: _addons.error != null,
    );
  }

  Future<void> _remove(String name) async {
    final ok = await confirmDialog(
      context,
      title: s.t('addonsRemove'),
      body: name,
      confirm: s.t('delete'),
      cancel: s.t('cancel'),
    );
    if (!ok || !mounted) return;
    await _addons.remove(name);
    if (mounted) showNukefySnack(context, s.t('addonsRemoved'));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final progress = _addons.progress;

    return SafeArea(
      bottom: false,
      child: ResponsiveSections(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          SectionCard(
            title: s.t('addonsTitle'),
            icon: Icons.extension_rounded,
            description: s.t('addonsHint'),
            trailing: TextButton(
              onPressed: _addons.loading ? null : () => _addons.refreshCatalog(),
              child: Text(s.t('addonsRefresh')),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_addons.loading && _addons.catalog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
                  )
                else if (_addons.catalog.isEmpty)
                  Text(_addons.error ?? s.t('addonsEmpty'), style: p.secondaryStyle)
                else
                  for (final repo in _addons.catalog)
                    _AddonCard(
                      repo: repo,
                      release: _addons.releases[repo.name],
                      installed: _addons.installed[repo.name],
                      installing: _addons.installing == repo.name,
                      progress: _addons.installing == repo.name ? _addons.progress : null,
                      needsUpdate: _addons.needsUpdate(repo.name),
                      onInstall: () => _install(repo.name),
                      onRemove: () => _remove(repo.name),
                    ),
                if (_addons.installing != null && progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text(s.t('addonsDownloading'), style: p.captionStyle),
                ],
              ],
            ),
          ),
          if (_addons.installed.isNotEmpty)
            SectionCard(
              title: s.t('addonsInstalled'),
              icon: Icons.download_done_rounded,
              child: Column(
                children: [
                  for (final entry in _addons.installed.entries)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(
                        entry.key.toLowerCase().contains('music') ? Icons.library_music_rounded : Icons.apps_rounded,
                        color: p.accent,
                      ),
                      title: Text(entry.key),
                      subtitle: Text('${s.t('addonsVersion')}: ${entry.value.version}'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: s.t('addonsOpen'),
                            onPressed: () => _addons.openFolder(entry.key),
                            icon: const Icon(Icons.folder_open_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: s.t('addonsRemove'),
                            onPressed: () => _remove(entry.key),
                            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(s.t('addonsMusicHint'), style: p.captionStyle),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AddonCard extends StatelessWidget {
  const _AddonCard({
    required this.repo,
    required this.release,
    required this.installed,
    required this.installing,
    required this.progress,
    required this.needsUpdate,
    required this.onInstall,
    required this.onRemove,
  });

  final AddonRepo repo;
  final AddonRelease? release;
  final InstalledAddon? installed;
  final bool installing;
  final double? progress;
  final bool needsUpdate;
  final VoidCallback onInstall;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final progress = this.progress;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: installed != null ? p.success.withValues(alpha: .5) : p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(repo.isMusic ? Icons.library_music_rounded : Icons.inventory_2_outlined, size: 18, color: p.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(repo.name, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700))),
              if (installed != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: p.success.withValues(alpha: .16), borderRadius: BorderRadius.circular(8)),
                  child: Text(s.t('addonsInstalled'), style: AppTextStyles.tab.copyWith(fontSize: 8.5, color: p.success)),
                ),
            ],
          ),
          if (repo.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(repo.description, style: p.secondaryStyle),
          ],
          const SizedBox(height: 8),
          Text(
            release == null
                ? s.t('addonsNotInstalled')
                : '${s.t('addonsLatest')}: ${release!.version}${installed == null ? '' : ' · ${s.t('addonsVersion')}: ${installed!.version}'}',
            style: p.captionStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (release != null)
                FilledButton.icon(
                  onPressed: installing ? null : onInstall,
                  icon: installing
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(needsUpdate ? Icons.update_rounded : Icons.download_rounded, size: 17),
                  label: Text(needsUpdate ? s.t('addonsUpdate') : (installed == null ? s.t('addonsInstall') : s.t('addonsUpdate'))),
                ),
              if (installed != null) ...[
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  label: Text(s.t('addonsRemove')),
                ),
                OutlinedButton.icon(
                  onPressed: () => AddonsService.instance.openFolder(repo.name),
                  icon: const Icon(Icons.folder_open_outlined, size: 17),
                  label: Text(s.t('addonsOpen')),
                ),
              ],
              if (repo.htmlUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(repo.htmlUrl), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('GitHub'),
                ),
            ],
          ),
          if (installing && progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
    );
  }
}
