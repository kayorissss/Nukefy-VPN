import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/game_blocklist_service.dart';
import '../../core/services/zapret_probe.dart';
import '../../core/services/zapret_service.dart';
import '../../core/services/zapret_update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/section_card.dart';
import '../widgets/game_mark.dart';

class ZapretScreen extends StatefulWidget {
  const ZapretScreen({super.key, this.active = true});
  final bool active;
  @override
  State<ZapretScreen> createState() => _ZapretScreenState();
}

class _ZapretScreenState extends State<ZapretScreen> {
  final _zapret = ZapretService.instance;
  final _scroll = ScrollController();
  final _updater = ZapretUpdateService();
  List<ZapretStrategy> _strategies = [];
  final Map<String, List<ZapretProbeResult>> _results = {};
  List<ZapretProbeTarget> _targets = ZapretProbe.defaults;
  CancelToken? _cancel;
  String? _current, _best, _error;
  bool _analyzing = false, _quick = true, _showLog = false;
  int _step = 0;
  ZapretUpdateInfo? _update;
  double? _download;
  bool _checking = false, _preparingAnalysis = false;

  S get s => context.read<SettingsProvider>().strings;

  @override
  void initState() {
    super.initState();
    _strategies = _zapret.strategies();
    _zapret.addListener(_changed);
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _enter(); });
  }

  @override
  void didUpdateWidget(covariant ZapretScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && widget.active) _enter(); });
  }

  Future<void> _enter() async {
    if (!_zapret.isSupported || _zapret.busy) return;
    await _run(() async { await _zapret.serviceInstalled(); await _loadTargets(); });
    if (mounted && context.read<SettingsProvider>().settings.zapretAutoUpdateCheck) await _checkUpdate(automatic: true);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _zapret.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() { if (mounted) setState(() {}); }

  Future<void> _run(Future<void> Function() action) async {
    if (_zapret.busy) return;
    setState(() => _error = null);
    try { await _zapret.exclusive(action); }
    catch (error) { if (mounted) setState(() => _error = '$error'.contains('ipset-backup-missing') ? s.t('zNoIpsetBackup') : '$error'); }
    finally { if (mounted && _download != null) setState(() => _download = null); }
  }

  Future<void> _loadTargets() async {
    final games = GameBlocklistService.instance;
    final targets = [...ZapretProbe.defaults];
    for (final game in games.installed()) {
      final domains = await games.domains(game.id);
      if (domains.isNotEmpty) targets.add(ZapretProbeTarget(id: 'game:${game.id}', name: game.name, url: 'https://${domains.first}/', okCodes: const [200, 204, 301, 302, 307, 308]));
    }
    if (mounted) setState(() => _targets = targets);
  }

  Future<void> _start(ZapretStrategy strategy) async {
    _zapret.configure(context.read<SettingsProvider>().settings);
    if (!await _zapret.start(strategy)) throw StateError(_zapret.lastError ?? 'winws failed');
  }

  ZapretStrategy? _selected() => _strategies.where((e) => e.id == context.read<SettingsProvider>().settings.zapretStrategy).firstOrNull ?? _strategies.firstOrNull;

  Future<void> _restart() async {
    if (_zapret.isRunning && _selected() != null) await _start(_selected()!);
  }

  Future<void> _analyze() async {
    if (_zapret.busy || _checking || _preparingAnalysis) return;
    setState(() => _preparingAnalysis = true);
    try { await _loadTargets(); }
    catch (e) { if (mounted) setState(() => _error = '$e'); return; }
    finally { if (mounted) setState(() => _preparingAnalysis = false); }
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final selected = _targets.where((t) => settings.settings.zapretCheckTargets.contains(t.id)).toList();
    if (selected.isEmpty) return;
    final previous = _selected();
    final wasRunning = _zapret.isRunning;
    final token = CancelToken();
    _cancel = token;
    await _run(() async {
      setState(() { _analyzing = true; _step = 0; _best = null; _results.clear(); });
      String? best;
      var score = 0;
      var completed = false;
      try {
        for (final strategy in _strategies) {
          if (token.isCancelled) break;
          if (mounted) setState(() { _current = strategy.id; _step++; });
          _zapret.configure(settings.settings);
          final started = await _zapret.start(strategy);
          if (token.isCancelled) break;
          final result = started
              ? await ZapretProbe.instance.check(targets: selected, cancelToken: token)
              : [for (final t in selected) ZapretProbeResult(targetId: t.id, ok: false)];
          if (token.isCancelled) break;
          _results[strategy.id] = result;
          final passed = result.where((r) => r.ok).length;
          if (passed > score) { score = passed; best = strategy.id; }
          _changed();
          if (_quick && passed == selected.length) break;
        }
        completed = !token.isCancelled;
      } finally {
        await _zapret.stop();
        // Cancellation restores the original selection and running state.
        final chosen = completed && best != null ? _strategies.firstWhere((e) => e.id == best) : previous;
        if (completed && best != null) await settings.update((v) => v.zapretStrategy = best!);
        if (wasRunning && chosen != null) {
          _zapret.configure(settings.settings);
          if (!await _zapret.start(chosen)) throw StateError(_zapret.lastError ?? 'Restore failed');
        }
        if (mounted) setState(() { _analyzing = false; _current = null; _best = completed ? best : null; });
      }
    });
    if (mounted) setState(() { _analyzing = false; _current = null; });
  }

  Future<void> _checkUpdate({bool automatic = false}) async {
    if (_checking) return;
    setState(() { _checking = true; _error = null; });
    try {
      final update = await _updater.check();
      if (mounted) {
        setState(() => _update = update);
        if (!automatic && update != null) await context.read<SettingsProvider>().update((a) => a.zapretSkippedVersion = null);
      }
      if (!automatic && mounted && update == null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('zUpToDate'))));
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _checking = false); }
  }

  Future<void> _text(String title, String body) => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: Text(title), content: SizedBox(width: 640, child: SingleChildScrollView(child: SelectableText(body))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('close')))],
  ));

  Future<String?> _input(String title, String initial, {bool ports = false}) async {
    var text = initial;
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: Form(key: form, child: TextFormField(
        initialValue: initial, autofocus: true, onChanged: (v) => text = v,
        validator: (v) => ports && !ZapretService.validPorts(v ?? '') ? s.t('zPortsInvalid') : null,
      )), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, text); }, child: Text(s.t('save')))],
    ));
    return value;
  }

  Future<void> _hosts() async {
    final text = await _zapret.hostsProposal();
    if (!mounted) return;
    final apply = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(s.t('zHostsReview')), content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('zHostsWarning')), const SizedBox(height: 12), SelectableText(text),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('zHostsApply')))],
    ));
    if (apply == true) await _zapret.applyHosts(text);
  }

  Future<void> _ports(bool tcp) async {
    final settings = context.read<SettingsProvider>();
    final value = await _input(tcp ? 'TCP' : 'UDP', tcp ? settings.settings.zapretGameTcp : settings.settings.zapretGameUdp, ports: true);
    if (value == null || !mounted) return;
    await _run(() async {
      await settings.update((v) { if (tcp) { v.zapretGameTcp = value; } else { v.zapretGameUdp = value; } });
      _zapret.configure(settings.settings);
      await _zapret.saveGameFilter();
      await _restart();
    });
  }

  Future<void> _addDomain() async {
    final value = await _input(s.t('zapretAddDomain'), '');
    if (value == null || !mounted) return;
    await _run(() async {
      final domain = ZapretService.normalizeDomain(value);
      if (!GameBlocklistService.validDomain(domain)) throw FormatException(s.t('zapretDomainInvalid'));
      await _zapret.saveDomains({..._zapret.loadDomains(), domain}.toList());
      await _restart();
    });
  }

  Widget _button(String key, IconData icon, Future<void> Function() action) => OutlinedButton.icon(
    onPressed: _zapret.busy ? null : () => _run(action), icon: Icon(icon, size: 18), label: Text(s.t(key)),
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final busy = _zapret.busy;
    final chosen = _selected();
    final vpnOn = context.select<VpnProvider, bool>((v) => v.status != VpnStatus.disconnected);
    final domains = _zapret.loadDomains();
    final controls = SectionCard(title: s.t('zapret'), icon: Icons.shield_outlined, child: Column(children: [
      const SizedBox(height: 20),
      Icon(Icons.shield_rounded, size: 80, color: _zapret.isRunning ? p.success : p.textSecondary),
      const SizedBox(height: 24),
      Text(s.t(_zapret.isRunning ? 'zapretOn' : 'zapretOff'), style: AppTextStyles.headline),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: busy || chosen == null ? null : () => _run(() async {
        if (_zapret.isRunning) { await _zapret.stop(); } else { await _start(chosen); }
      }), icon: const Icon(Icons.power_settings_new), label: Text(s.t(_zapret.isRunning ? 'zDeactivate' : 'zActivate'))),
      const SizedBox(height: 16),
      Text('${s.t('zVersion')}: ${_zapret.version ?? '—'}'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : () => context.read<NavProvider>().setIndex(6),
        icon: const Icon(Icons.sports_esports_outlined),
        label: Text(s.t('zApps')),
      ),
      _button('zFolder', Icons.folder_open_outlined, _zapret.openFolder),
    ]));

    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(title: s.t('general'), icon: Icons.tune, child: Column(children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _dropdown(s.t('zapretGameFilter'), settings.settings.zapretGameMode,
            {'off': s.t('zOff'), 'all': 'TCP + UDP', 'tcp': 'TCP', 'udp': 'UDP'},
            (v) => _run(() async {
              await settings.update((a) { a.zapretGameMode = v; a.zapretGameFilter = v != 'off'; });
              _zapret.configure(settings.settings); await _zapret.saveGameFilter(); await _restart();
            })),
          _dropdown('IPSet Filter', _zapret.ipsetMode(), {'any': s.t('zIpsetAny'), 'loaded': s.t('zIpsetLoaded'), 'none': s.t('zIpsetNone')},
            (v) => _run(() async { await _zapret.setIpsetMode(v); await _restart(); })),
          OutlinedButton(onPressed: busy ? null : () => _ports(true), child: Text('TCP: ${settings.settings.zapretGameTcp}')),
          OutlinedButton(onPressed: busy ? null : () => _ports(false), child: Text('UDP: ${settings.settings.zapretGameUdp}')),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('zapretAutoStart')), value: settings.settings.zapretAutoStart,
          onChanged: busy || _zapret.servicePresent ? null : (v) => settings.update((a) => a.zapretAutoStart = v)),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(s.t('zTools')), children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('zAutoUpdate')), value: settings.settings.zapretAutoUpdateCheck,
            onChanged: busy ? null : (v) => _run(() async { await _zapret.setAutoUpdateCheck(v); await settings.update((a) => a.zapretAutoUpdateCheck = v); })),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _button('zIpsetUpdate', Icons.download, () async { await _zapret.updateIpsetList(); await _restart(); }),
            _button('zHosts', Icons.description_outlined, _hosts),
            _button('zDiagnostics', Icons.health_and_safety_outlined, () async { final report = await _zapret.diagnostics(); if (mounted) await _text(s.t('zDiagnostics'), report); }),
            _button('zServiceStatus', Icons.info_outline, () async { await _zapret.serviceInstalled(); if (mounted) await _text(s.t('zServiceStatus'), s.t(_zapret.serviceRunning ? 'zapretOn' : _zapret.servicePresent ? 'zServiceStopped' : 'zServiceAbsent')); }),
            _button(_zapret.servicePresent ? 'zServiceRemove' : 'zServiceInstall', Icons.settings_suggest_outlined, () async {
              final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(s.t('zServiceStatus')), content: Text(s.t('zServiceWarning')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('confirm')))]));
              if (confirmed != true) return;
              if (_zapret.servicePresent) { await _zapret.removeService(); }
              else if (chosen != null) { _zapret.configure(settings.settings); await _zapret.installService(chosen); }
            }),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [for (final kind in ['discord', 'game'])
            _dropdown(kind == 'discord' ? s.t('zDiscordFake') : s.t('zGameFake'), _zapret.activeFake(kind), {for (final name in _zapret.fakeFiles()) name: name},
              (name) => _run(() async { final running = _zapret.isRunning; if (running) await _zapret.stop(); await _zapret.setActiveFake(kind, name); if (running && chosen != null) await _start(chosen); })),
          ]),
          const SizedBox(height: 16),
        ]),
      ])),
      SectionCard(title: s.t('zapretAnalyze'), icon: Icons.analytics_outlined, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('zProbeHint'), style: context.palette.secondaryStyle),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final target in _targets)
          FilterChip(avatar: ZapretTargetIcon(id: target.id), label: Text(target.name), selected: settings.settings.zapretCheckTargets.contains(target.id),
            onSelected: busy ? null : (v) => settings.update((a) { a.zapretCheckTargets = [...a.zapretCheckTargets]..remove(target.id); if (v) a.zapretCheckTargets.add(target.id); })),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('zQuick')), value: _quick, onChanged: busy ? null : (v) => setState(() => _quick = v)),
        if (vpnOn) Text(s.t('zapretAnalyzeVpnOn'), style: TextStyle(color: p.accent)),
        SizedBox(height: 56, child: Row(children: [
          FilledButton.icon(onPressed: _analyzing ? () => _cancel?.cancel() : busy || _checking || _preparingAnalysis || vpnOn || !_targets.any((t) => settings.settings.zapretCheckTargets.contains(t.id)) ? null : _analyze,
            icon: Icon(_analyzing ? Icons.stop : Icons.play_arrow), label: Text(s.t(_analyzing ? 'cancel' : 'zapretAnalyze'))),
          const SizedBox(width: 16),
          Expanded(child: Text(_analyzing ? '$_step / ${_strategies.length}' : _best != null ? s.t('zapretApplied') : _step > 0 ? s.t('zAnalysisFinished') : '', maxLines: 2)),
        ])),
        LinearProgressIndicator(value: _analyzing ? _step / _strategies.length : 0, minHeight: 3),
      ])),
      SectionCard(
        title: s.t('zapretStrategies'),
        icon: Icons.view_module_outlined,
        description: s.t('zapretStrategyHint'),
        child: LayoutBuilder(builder: (context, constraints) {
          final count = (constraints.maxWidth / 250).floor().clamp(1, 8).toInt();
          final width = (constraints.maxWidth - 12 * (count - 1)) / count;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final strategy in _strategies)
                SizedBox(
                  width: width,
                  height: 186 * MediaQuery.textScalerOf(context).scale(1),
                  child: _tile(strategy, strategy.id == chosen?.id, busy),
                ),
            ],
          );
        }),
      ),
    ]);

    return SafeArea(bottom: false, child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
      key: const PageStorageKey('zapret-main'), controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text('ZAPRET', style: AppTextStyles.title)), TextButton.icon(onPressed: _checking || busy ? null : _checkUpdate, icon: const Icon(Icons.system_update_alt), label: Text(s.t(_checking ? 'zChecking' : 'zCheckUpdate')))]),
        SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: _error == null ? Text(s.t('zapretHint'), style: context.palette.secondaryStyle) : InkWell(onTap: () => _text(s.t('zError'), _error!), child: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.error))))),
        if (_update != null && settings.settings.zapretSkippedVersion != _update!.version)
          SectionCard(title: '${s.t('zUpdateAvailable')} ${_update!.version}', icon: Icons.update, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('zUpdateTrust')),
            Wrap(spacing: 12, children: [TextButton(onPressed: () => _text(_update!.version, _update!.notes), child: Text(s.t('zReleaseNotes'))),
              FilledButton(onPressed: busy ? null : () => _run(() async {
                await _updater.install(_update!, (progress) { if (mounted) setState(() => _download = progress.fraction); });
                if (mounted) setState(() { _strategies = _zapret.strategies(); _update = null; _download = null; });
              }), child: Text(s.t('zInstall'))),
              TextButton(onPressed: busy ? null : () => settings.update((a) => a.zapretSkippedVersion = _update!.version), child: Text(s.t('zLater')))]),
            if (_download != null) LinearProgressIndicator(value: _download),
          ])),
        if (!_zapret.isSupported) Text(s.t('zapretMissing'))
        else ...[
          if (constraints.maxWidth >= 980) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 300, child: controls), const SizedBox(width: 20), Expanded(child: main)])
          else ...[controls, main],
          const SizedBox(height: 20),
          SectionCard(title: s.t('zapretAddDomain'), icon: Icons.language, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [for (final domain in domains) InputChip(label: Text(domain), onDeleted: busy ? null : () => _run(() async { await _zapret.saveDomains([...domains]..remove(domain)); await _restart(); })),
              ActionChip(label: Text(s.t('add')), avatar: const Icon(Icons.add), onPressed: busy ? null : _addDomain)]),
          ])),
          SectionCard(
            title: s.t('logs'),
            icon: Icons.terminal_rounded,
            trailing: IconButton(
              tooltip: s.t(_showLog ? 'collapse' : 'expand'),
              onPressed: () => setState(() => _showLog = !_showLog),
              icon: Icon(_showLog ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            ),
            child: _showLog
                ? SizedBox(
                    height: 260,
                    child: SingleChildScrollView(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _zapret.logRevision,
                        builder: (context, _, child) => SelectableText(
                          _zapret.log.join('\n'),
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                        ),
                      ),
                    ),
                  )
                : Text(s.t('logsCollapsed'), style: p.secondaryStyle),
          ),
        ],
      ]),
    )));
  }

  Widget _dropdown(String label, String? value, Map<String, String> values, void Function(String) changed) => SizedBox(width: 240,
    child: DropdownButtonFormField<String>(initialValue: values.containsKey(value) ? value : null,
      key: ValueKey('$label:$value'), isExpanded: true, decoration: InputDecoration(labelText: label),
      items: [for (final e in values.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
      onChanged: _zapret.busy ? null : (v) { if (v != null) changed(v); },
    ));

  Widget _tile(ZapretStrategy strategy, bool selected, bool busy) {
    final p = context.palette;
    final results = _results[strategy.id];
    final color = _best == strategy.id ? p.success : p.accent;
    return Material(color: selected ? color.withValues(alpha: .12) : p.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: selected ? color : p.border)), clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: busy ? null : () => _run(() async {
        final settings = context.read<SettingsProvider>();
        final running = _zapret.isRunning;
        if (running) await _start(strategy);
        await settings.update((a) => a.zapretStrategy = strategy.id);
      }), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('#${strategy.number.toString().padLeft(2, '0')}', style: TextStyle(color: color, fontWeight: FontWeight.w700)), const Spacer(),
          if (_current == strategy.id) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else if (_best == strategy.id) Icon(Icons.verified, color: color, size: 20)
          else if (selected) Icon(Icons.check_circle, color: color, size: 20)]),
        const SizedBox(height: 10),
        Text(strategy.id == 'general' ? s.t('zapretSubMain') : strategy.id.replaceFirst('general', '').trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        SizedBox(height: 36, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final target in _targets.where((t) => context.read<SettingsProvider>().settings.zapretCheckTargets.contains(t.id)))
            Padding(padding: const EdgeInsets.only(right: 10), child: Tooltip(message: '${target.name}: ${results?.where((r) => r.targetId == target.id).firstOrNull?.statusCode ?? '—'}', child: Row(children: [ZapretTargetIcon(id: target.id), const SizedBox(width: 3),
              Icon(results == null ? Icons.remove : results.any((r) => r.targetId == target.id && r.ok) ? Icons.check : Icons.close, size: 14, color: results == null ? p.textSecondary : results.any((r) => r.targetId == target.id && r.ok) ? p.success : AppColors.error)]))),
        ]))),
      ]))),
    );
  }
}

class ZapretTargetIcon extends StatelessWidget {
  const ZapretTargetIcon({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => id == 'youtube' || id == 'discord'
      ? Image.asset('assets/brands/$id.png', width: 20, height: 20)
      : GameMark(id: id.replaceFirst('game:', ''), size: 20);
}
