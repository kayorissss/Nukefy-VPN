import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/game_blocklist_service.dart';
import '../../core/theme/app_colors.dart;
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';

class DomainManagerDialog extends StatefulWidget {
  const DomainManagerDialog({super.key, required this.game, required this.initial, required this.games});
  final GameListInfo game;
  final List<String> initial;
  final GameBlocklistService games;

  @override
  State<DomainManagerDialog> createState() => _DomainManagerDialogState();
}

class _DomainManagerDialogState extends State<DomainManagerDialog> {
  late final TextEditingController _input;
  late List<String> _domains;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  S get s => context.read<SettingsProvider>().strings;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
    _domains = [...widget.initial];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = _input.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.games.addDomain(widget.game.id, value);
      _domains = await widget.games.domains(widget.game.id);
      _input.clear();
      _changed = true;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String domain) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.t('zRemoveDomainTitle')),
        content: Text('$domain\n\n${s.t('zRemoveDomainBody')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.t('delete'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.games.removeDomain(widget.game.id, domain);
      _domains = await widget.games.domains(widget.game.id);
      _changed = true;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.t('zRestoreDomainTitle')),
        content: Text(s.t('zRestoreDomainBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.t('zRestore'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.games.restore(widget.game.id, widget.game.name);
      _domains = await widget.games.domains(widget.game.id);
      _changed = true;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String domain) async {
    await Clipboard.setData(ClipboardData(text: domain));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t('copied'))));
  }

  Future<void> _open(bool file) async {
    try {
      if (file) {
        await widget.games.openFile(widget.game.id);
      } else {
        await widget.games.openFolder();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(widget.game.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        Text('${_domains.length}', style: p.secondaryStyle),
      ]),
      content: SizedBox(
        width: 720,
        height: 500,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('zDomainActions'), style: p.secondaryStyle),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: 360, child: TextField(controller: _input, enabled: !_busy, onSubmitted: (_) => _add(), decoration: InputDecoration(isDense: true, hintText: s.t('zDomainPlaceholder'), prefixIcon: const Icon(Icons.add_rounded)))),
            FilledButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add_rounded), label: Text(s.t('zAddDomain'))),
            OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore_rounded), label: Text(s.t('zRestore'))),
            IconButton(tooltip: s.t('zOpenFile'), onPressed: _busy ? null : () => _open(true), icon: const Icon(Icons.description_outlined)),
            IconButton(tooltip: s.t('zOpenFolder'), onPressed: _busy ? null : () => _open(false), icon: const Icon(Icons.folder_open_outlined)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.error))),
          const SizedBox(height: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.surface.withValues(alpha: .55), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
              child: _domains.isEmpty
                  ? Center(child: Text(s.t('zDomainsEmpty'), style: p.secondaryStyle))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _domains.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
                      itemBuilder: (context, index) {
                        final domain = _domains[index];
                        return ListTile(
                          dense: true,
                          leading: Text('${index + 1}', style: p.captionStyle),
                          title: SelectableText(domain, style: AppTextStyles.bodyRegular.copyWith(fontFamily: 'JetBrainsMono', fontSize: 12)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: s.t('copyDomain'), onPressed: _busy ? null : () => _copy(domain), icon: const Icon(Icons.copy_rounded, size: 18)), IconButton(tooltip: s.t('zRemoveDomain'), onPressed: _busy ? null : () => _remove(domain), icon: Icon(Icons.remove_circle_outline_rounded, color: p.error, size: 19))]),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, _changed), child: Text(s.t('close')))],
    );
  }
}
