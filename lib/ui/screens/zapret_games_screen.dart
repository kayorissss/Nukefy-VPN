import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/services/game_blocklist_service.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/network_diagnostics.dart';
import '../widgets/game_mark.dart';
import 'zapret_domain_dialog.dart';

class ZapretGamesScreen extends StatefulWidget {
  const ZapretGamesScreen({super.key, this.active = true, this.embedded = false});
  final bool active;
  final bool embedded;
  @override
  State<ZapretGamesScreen> createState() => _ZapretGamesScreenState();
}

class _ZapretGamesScreenState extends State<ZapretGamesScreen> {
  final _games = GameBlocklistService.instance;
  final _zapret = ZapretService.instance;
  final _scroll = ScrollController();
  List<GameListInfo> _catalog = [];
  bool _loading = false, _grid = true;
  String? _error;
  String? _notice;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalog = _games.cachedCatalog();
    _zapret.addListener(_changed);
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _refresh(); });
  }

  @override
  void didUpdateWidget(covariant ZapretGamesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && widget.active) _refresh(); });
  }

  @override
  void dispose() { _zapret.removeListener(_changed); _scroll.dispose(); super.dispose(); }
  void _changed() { if (mounted) setState(() {}); }

  Future<void> _operation(Future<bool> Function() action) async {
    if (_zapret.busy || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _zapret.exclusive(() async {
        final changed = await action();
        await _zapret.refreshGameLists();
        if (changed && _zapret.isRunning) {
          final strategy = _zapret.strategies().firstWhere((s) => s.id == _zapret.runningStrategyId);
          if (!await _zapret.start(strategy)) throw StateError(_zapret.lastError ?? 'Restart failed');
        }
      });
    } catch (e) { if (mounted) setState(() => _error = NetworkDiagnostics.textOrRaw(e, context.read<SettingsProvider>().strings.t)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _refresh() => _operation(() async {
    final catalog = await _games.refreshCatalog();
    if (catalog != null && mounted) {
      final s = context.read<SettingsProvider>().strings;
      setState(() {
        _catalog = catalog;
        _notice = _games.usedFallback ? s.t('zCatalogOffline') : null;
      });
    }
    return await _games.refreshInstalled() > 0;
  });

  Future<void> _install(GameListInfo game) async {
    final s = context.read<SettingsProvider>().strings;
    GameListPreview? preview;
    await _operation(() async { preview = await _games.prepare(game); return false; });
    if (preview == null || !mounted) return;
    final list = preview!;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(game.name), content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('zGameConsent')), const SizedBox(height: 12),
        Text('${s.t('zDomainCount')}: ${list.domains.length} · ${s.t('zRejected')}: ${list.rejected}'),
        const SizedBox(height: 12), SelectableText(list.domains.join('\n')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('add')))],
    ));
    if (yes != true || !mounted) return;
    await _operation(() async { await _games.install(list); return true; });
  }

  Future<void> _view(GameListInfo game) async {
    List<String>? list;
    await _operation(() async { list = await _games.domains(game.id); return false; });
    if (!mounted || list == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => DomainManagerDialog(game: game, initial: list!, games: _games),
    );
    if (changed == true && mounted) {
      await _operation(() async => true);
    }
  }

  Future<void> _removeGame(GameListInfo game) async {
    final s = context.read<SettingsProvider>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.t('zRemoveGameTitle')),
        content: Text('${s.t('zRemoveGameBody')}\n\n${game.name}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.t('delete'))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _operation(() async { await _games.remove(game.id); return true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final catalog = _catalog.where((g) => g.name.toLowerCase().contains(_query.toLowerCase())).toList();
    final content = SafeArea(bottom: false, child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
      controller: _scroll, key: const PageStorageKey('zapret-games'), padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (widget.embedded)
            IconButton(
              tooltip: s.t('zapret'),
              onPressed: () => context.read<NavProvider>().go(NavDestination.zapret),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const BackButton(),
          Expanded(child: Text(s.t('zApps'), style: AppTextStyles.title)),
          IconButton(tooltip: s.t('zRefresh'), onPressed: _loading || _zapret.busy ? null : _refresh, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: s.t('zView'), onPressed: () => setState(() => _grid = !_grid), icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_rounded))]),
        const SizedBox(height: 16),
        Text(s.t('zCatalogHint'), style: p.secondaryStyle),
        const SizedBox(height: 12),
        Text('medvedeff-true/ru-gaming-blocklist • games/*.txt', style: p.captionStyle),
        const SizedBox(height: 16),
        TextField(onChanged: (v) => setState(() => _query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.t('zFindGame'))),
        SizedBox(height: 40, child: _loading ? const Center(child: LinearProgressIndicator()) : _error != null ? Text(_error!, maxLines: 2, style: TextStyle(color: p.error)) : _notice != null ? Text(_notice!, maxLines: 3, style: p.secondaryStyle) : _zapret.busy ? Text(s.t('zBusy')) : const SizedBox()),
        if (catalog.isEmpty && !_loading) Text(s.t('zNoGames')),
        LayoutBuilder(builder: (context, box) {
          final count = _grid ? (box.maxWidth / 270).floor().clamp(1, 8) : 1;
          final width = (box.maxWidth - (count - 1) * 12) / count;
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final game in catalog) SizedBox(width: width, child: _card(game))]);
        }),
      ]),
    )));
    return widget.embedded ? content : Scaffold(backgroundColor: p.background, body: content);
  }

  Widget _card(GameListInfo game) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final installed = _games.installed().where((g) => g.id == game.id).firstOrNull;
    final enabled = !_loading && !_zapret.busy;
    final heading = Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: p.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Center(child: GameMark(id: game.id))),
      const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(game.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
        Text(installed == null ? s.t('zNotAdded') : '${installed.count} ${s.t('zDomains')}', style: p.captionStyle)]))]);
    final actions = Wrap(spacing: 8, children: installed == null
      ? [FilledButton.icon(onPressed: enabled ? () => _install(game) : null, icon: const Icon(Icons.add, size: 18), label: Text(s.t('add')))]
      : [TextButton(onPressed: enabled ? () => _view(game) : null, child: Text(s.t('zShowDomains'))), IconButton(tooltip: s.t('delete'), onPressed: enabled ? () => _removeGame(game) : null, icon: const Icon(Icons.delete_outline, size: 20))]);
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: p.card, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
      child: _grid ? SizedBox(height: 130 * MediaQuery.textScalerOf(context).scale(1), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const Spacer(), actions])) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 10), actions]));
  }
}
