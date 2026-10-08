import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/game_blocklist_service.dart';
import '../../core/services/zapret_probe.dart';
import '../../core/services/zapret_service.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/services/zapret_update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/network_diagnostics.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';
import '../widgets/game_mark.dart';

class ZapretScreen extends StatefulWidget {
  const ZapretScreen({super.key, this.active = true, this.settingsOnly = false});
  final bool active;
  final bool settingsOnly;
  @override
  State<ZapretScreen> createState() => _ZapretScreenState();
}

class _ZapretScreenState extends State<ZapretScreen> {
  final _zapret = ZapretService.instance;
  final _scroll = ScrollController();
  late final TextEditingController _extraArgs = TextEditingController();
  final _updater = ZapretUpdateService();
  List<ZapretStrategy> _strategies = [];
  final Map<String, List<ZapretProbeResult>> _results = {};
  List<ZapretProbeTarget> _targets = ZapretProbe.defaults;
  CancelToken? _cancel;
  String? _current, _best, _error;
  String? _failureReport;
  bool _analyzing = false, _quick = true, _showLog = false, _showTools = false, _showAnalysis = false;
  int _step = 0;
  ZapretUpdateInfo? _update;
  double? _download;
  bool _checking = false, _preparingAnalysis = false;

  S get s => context.read<SettingsProvider>().strings;

  @override
  void initState() {
    _extraArgs.text = context.read<SettingsProvider>().settings.zapretExtraArgs;
    super.initState();
    _strategies = _zapret.strategies();
    _zapret.addListener(_changed);
    // Whatever else does DPI bypass on this machine has to be known before the
    // user presses anything: two captures at once is the usual reason "zapret
    // does not work" while another client works fine.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _refreshConflicts(); });
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
    _extraArgs.dispose();
    super.dispose();
  }

  void _changed() { if (mounted) setState(() {}); }

  Future<void> _run(Future<void> Function() action) async {
    if (_zapret.busy) return;
    setState(() => _error = null);
    try { await _zapret.exclusive(action); }
    catch (error) {
      if (!mounted) return;
      final raw = '$error';
      setState(() => _error = raw.contains('ipset-backup-missing') ? s.t('zNoIpsetBackup') : NetworkDiagnostics.textOrRaw(error, s.t));
    }
    finally { if (mounted && _download != null) setState(() => _download = null); }
  }

  Future<void> _loadTargets() async {
    final games = GameBlocklistService.instance;
    final targets = [...ZapretProbe.defaults];
    for (final game in games.installed()) {
      final domains = await games.domains(game.id);
      if (domains.isNotEmpty) targets.add(ZapretProbeTarget(id: 'game:${game.id}', name: game.name, url: 'https://${domains.first}/', okCodes: const [200, 204, 301, 302, 307, 308]));
    }
    for (final host in context.read<SettingsProvider>().settings.probeHosts) {
      targets.add(ZapretProbeTarget(id: 'custom:$host', name: host, url: 'https://$host/', okCodes: const [200, 204, 301, 302]));
    }
    if (mounted) setState(() => _targets = targets);
  }

  /// Editor for user-defined probe services: presets for the popular ones
  /// plus a free-form host field.
  Future<void> _addService() async {
    final s = context.read<SettingsProvider>().strings;
    final controller = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('zAddService')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in ZapretProbe.presets.entries)
                    ActionChip(label: Text(entry.key), onPressed: () => Navigator.pop(ctx, entry.value)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(controller: controller, decoration: InputDecoration(hintText: 'my-service.tv')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(s.t('add'))),
        ],
      ),
    );
    controller.dispose();
    if (picked == null || picked.isEmpty || !mounted) return;
    final host = picked.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    if (host.isEmpty || !host.contains('.')) return;
    await context.read<SettingsProvider>().update((a) {
      if (!a.probeHosts.contains(host)) a.probeHosts = [...a.probeHosts, host];
      if (!a.zapretCheckTargets.contains('custom:$host')) a.zapretCheckTargets = [...a.zapretCheckTargets, 'custom:$host'];
    });
    await _loadTargets();
  }

  List<String> _conflicts = const [];

  /// Asks the service what else on this machine is doing DPI bypass. The app
  /// never closes someone else's program, so the answer is shown to the user.
  Future<void> _refreshConflicts() async {
    final found = await _zapret.detectConflicts();
    if (mounted) setState(() => _conflicts = found);
  }

  Future<void> _start(ZapretStrategy strategy) async {
    _zapret.configure(context.read<SettingsProvider>().settings);
    await _refreshConflicts();
    if (!await _zapret.start(strategy)) {
      final conflicts = _zapret.conflicts;
      if (conflicts.isNotEmpty) {
        throw StateError('${s.t('zConflictTitle')}\n${conflicts.join('\n')}\n${s.t('zConflictBody')}');
      }
      throw StateError(_zapret.lastError ?? 'winws failed');
    }
  }

  ZapretStrategy? _selected() => _strategies.where((e) => e.id == context.read<SettingsProvider>().settings.zapretStrategy).firstOrNull ?? _strategies.firstOrNull;

  Future<void> _restart() async {
    if (_zapret.isRunning && _selected() != null) await _start(_selected()!);
  }

  Future<void> _analyze() async {
    if (_zapret.busy || _checking || _preparingAnalysis) return;
    setState(() => _preparingAnalysis = true);
    try { await _loadTargets(); }
    catch (e) {
      if (mounted) setState(() => _error = NetworkDiagnostics.textOrRaw(e, s.t));
      return;
    }
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
        // Every strategy failed: collect the machine-level reasons instead
        // of leaving the user with a wall of red crosses.
        if (completed && best == null) {
          try {
            _failureReport = await _zapret.diagnostics();
          } catch (_) {
            _failureReport = null;
          }
        } else if (completed) {
          _failureReport = null;
        }
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
    } catch (e) {
      if (mounted) setState(() => _error = NetworkDiagnostics.textOrRaw(e, s.t));
    }
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

  Future<void> _connectionTest() async {
    if (vpnOnForTest()) return;
    final targets = _targets.take(2).toList();
    if (targets.isEmpty) return;
    final results = await ZapretProbe.instance.check(targets: targets);
    if (!mounted) return;
    await _text(s.t('zConnectionTest'), results.map((r) => '${r.targetId}: ${r.ok ? 'OK' : 'FAIL'}${r.statusCode == null ? '' : ' (${r.statusCode})'}').join('\n'));
  }

  bool vpnOnForTest() => context.read<VpnProvider>().status != VpnStatus.disconnected;

  Future<void> _restartDiscord() async {
    final confirmed = await confirmDialog(
      context,
      title: s.t('zRestartDiscord'),
      body: s.t('zRestartDiscordWarning'),
      confirm: s.t('confirm'),
      cancel: s.t('cancel'),
    );
    if (!confirmed) return;
    final report = await VpnPlatform().restartDiscord();
    if (mounted && report.isNotEmpty) await _text(s.t('zRestartDiscord'), report);
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
    final running = _zapret.isRunning;
    final statusColor = running ? p.success : p.textSecondary;

    final conflictCard = _conflicts.isEmpty
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.accent.withValues(alpha: .38)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: p.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('zConflictTitle'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      NukefySelectableText(
                        '${s.t('zConflictBody')}\n${_conflicts.join('\n')}',
                        style: p.secondaryStyle,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _refreshConflicts,
                  child: Text(s.t('zConflictRecheck')),
                ),
              ],
            ),
          );

    final activation = SectionCard(
      title: s.t('zapretActivation'),
      icon: Icons.shield_outlined,
      child: LayoutBuilder(builder: (context, constraints) {
        final power = _ZapretPowerButton(
          running: running,
          busy: busy,
          label: s.t(running ? 'zDeactivate' : 'zActivate'),
          onTap: busy || chosen == null
              ? null
              : () => _run(() async {
                  if (running) {
                    await _zapret.stop();
                  } else {
                    await _start(chosen);
                  }
                }),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t(running ? 'zapretOn' : 'zapretOff'),
              style: AppTextStyles.title.copyWith(color: statusColor, fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text('${s.t('zVersion')}: ${_zapret.version ?? '—'}', style: p.secondaryStyle),
            const SizedBox(height: 14),
            // The active strategy stays next to the power button: switching
            // it is the most frequent action on the page.
            Text(s.t('zapretStrategy').toUpperCase(), style: p.captionStyle),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: NukefyDropdown<String>(
                value: chosen?.id ?? '',
                items: {for (final item in _strategies) item.id: '#${item.number.toString().padLeft(2, '0')} ${item.title}'},
                onChanged: busy
                    ? (_) {}
                    : (id) => _run(() async {
                          final strategy = _strategies.where((e) => e.id == id).firstOrNull;
                          if (strategy == null) return;
                          final running = _zapret.isRunning;
                          if (running && !settings.settings.zapretAutoRestart) {
                            final ok = await confirmDialog(
                              context,
                              title: s.t('zAutoRestart'),
                              body: '${strategy.id}: ${s.t('zapretRestartConfirm')}',
                              confirm: s.t('confirm'),
                              cancel: s.t('cancel'),
                            );
                            if (!ok) return;
                          }
                          await settings.update((a) => a.zapretStrategy = id);
                          if (running) await _start(strategy);
                        }),
              ),
            ),
            const SizedBox(height: 16),
            // The analysis plate: opens the analysis section below the fold.
            Material(
              color: p.accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() => _showAnalysis = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scroll.hasClients) {
                      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Row(
                    children: [
                      Icon(Icons.analytics_outlined, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.t('zapretAnalyze'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(s.t('zAnalysisPlateHint'), style: p.captionStyle),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_downward_rounded, size: 18, color: p.accent),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        if (constraints.maxWidth >= 560) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Center(child: power)),
              const SizedBox(width: 32),
              Expanded(child: details),
            ],
          );
        }
        return Column(
          children: [
            power,
            const SizedBox(height: 20),
            details,
          ],
        );
      }),
    );

    final domainCard = SectionCard(
      title: s.t('zapretAddDomain'),
      icon: Icons.language,
      description: s.t('zapretDomainsHint'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final domain in domains)
            InputChip(
              label: Text(domain),
              onDeleted: busy
                  ? null
                  : () async {
                      final confirmed = await confirmDialog(
                        context,
                        title: s.t('zRemoveDomainTitle'),
                        body: s.t('zRemoveDomainBody'),
                        confirm: s.t('delete'),
                        cancel: s.t('cancel'),
                      );
                      if (!confirmed || !mounted) return;
                      await _run(() async {
                        await _zapret.saveDomains([...domains]..remove(domain));
                        await _restart();
                      });
                    },
            ),
          ActionChip(
            label: Text(s.t('add')),
            avatar: const Icon(Icons.add),
            onPressed: busy ? null : _addDomain,
          ),
        ],
      ),
    );

    final settingsPage = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: s.t('general'),
          icon: Icons.tune,
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _dropdown(
                    s.t('zapretGameFilter'),
                    settings.settings.zapretGameMode,
                    {'off': s.t('zOff'), 'all': 'TCP + UDP', 'tcp': 'TCP', 'udp': 'UDP'},
                    (v) => _run(() async {
                      await settings.update((a) {
                        a.zapretGameMode = v;
                        a.zapretGameFilter = v != 'off';
                      });
                      _zapret.configure(settings.settings);
                      await _zapret.saveGameFilter();
                      await _restart();
                    }),
                  ),
                  _dropdown(
                    'IPSet Filter',
                    _zapret.ipsetMode(),
                    {'any': s.t('zIpsetAny'), 'loaded': s.t('zIpsetLoaded'), 'none': s.t('zIpsetNone')},
                    (v) => _run(() async {
                      await _zapret.setIpsetMode(v);
                      await _restart();
                    }),
                  ),
                  OutlinedButton(onPressed: busy ? null : () => _ports(true), child: Text('TCP: ${settings.settings.zapretGameTcp}')),
                  OutlinedButton(onPressed: busy ? null : () => _ports(false), child: Text('UDP: ${settings.settings.zapretGameUdp}')),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('launchOnBoot')),
                subtitle: Text(s.t('zapretLaunchHint')),
                value: settings.settings.launchOnBoot,
                onChanged: busy
                    ? null
                    : (v) async {
                        await settings.update((a) => a.launchOnBoot = v);
                        await VpnPlatform().setAutoStart(v, startInTray: settings.settings.startInTray);
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('startInTray')),
                subtitle: Text(s.t('startInTrayHint')),
                value: settings.settings.startInTray,
                onChanged: busy
                    ? null
                    : (v) async {
                        await settings.update((a) => a.startInTray = v);
                        await VpnPlatform().setAutoStart(settings.settings.launchOnBoot, startInTray: v);
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('zapretAutoStart')),
                subtitle: Text(s.t('zapretAutoStartHint')),
                value: settings.settings.zapretAutoStart,
                onChanged: busy || _zapret.servicePresent ? null : (v) => settings.update((a) => a.zapretAutoStart = v),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: .42),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.border),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(s.t('zTools'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                      trailing: Icon(_showTools ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                      onTap: busy ? null : () => setState(() => _showTools = !_showTools),
                    ),
                    if (_showTools)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(s.t('zAutoUpdate')),
                              value: settings.settings.zapretAutoUpdateCheck,
                              onChanged: busy
                                  ? null
                                  : (v) => _run(() async {
                                      await _zapret.setAutoUpdateCheck(v);
                                      await settings.update((a) => a.zapretAutoUpdateCheck = v);
                                    }),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _button('zIpsetUpdate', Icons.download, () async {
                                  await _zapret.updateIpsetList();
                                  await _restart();
                                }),
                                _button('zHosts', Icons.description_outlined, _hosts),
                                _button('zGovHosts', Icons.account_balance_outlined, () async {
                                  final confirmed = await confirmDialog(context, title: s.t('zGovHosts'), body: s.t('zHostsBlockWarning'), confirm: s.t('confirm'), cancel: s.t('cancel'));
                                  if (!confirmed) return;
                                  await _zapret.applyHostBlock(AppConstants.zapretGovernmentMediaHosts);
                                  if (mounted) await _text(s.t('zGovHosts'), AppConstants.zapretGovernmentMediaHosts.join('\n'));
                                }),
                                _button('zMaxHosts', Icons.forum_outlined, () async {
                                  final confirmed = await confirmDialog(context, title: s.t('zMaxHosts'), body: s.t('zHostsBlockWarning'), confirm: s.t('confirm'), cancel: s.t('cancel'));
                                  if (!confirmed) return;
                                  await _zapret.applyHostBlock(AppConstants.zapretMaxHosts);
                                  if (mounted) await _text(s.t('zMaxHosts'), AppConstants.zapretMaxHosts.join('\n'));
                                }),
                                _button('zNetworkReset', Icons.restart_alt_rounded, () async {
                                  final confirmed = await confirmDialog(context, title: s.t('zNetworkReset'), body: s.t('zNetworkResetWarning'), confirm: s.t('confirm'), cancel: s.t('cancel'));
                                  if (!confirmed) return;
                                  final report = await VpnPlatform().windowsNetworkReset();
                                  if (mounted) await _text(s.t('zNetworkReset'), report);
                                }),
                                _button('zConnectionTest', Icons.network_check_outlined, _connectionTest),
                                _button('zRestartDiscord', Icons.restart_alt_rounded, _restartDiscord),
                                _button('zDocumentation', Icons.menu_book_outlined, () async {
                                  await launchUrl(Uri.parse('https://github.com/Flowseal/zapret-discord-youtube'), mode: LaunchMode.externalApplication);
                                }),
                                _button('zDiagnostics', Icons.health_and_safety_outlined, () async {
                                  final report = await _zapret.diagnostics();
                                  if (mounted) await _text(s.t('zDiagnostics'), report);
                                }),
                                _button('zServiceStatus', Icons.info_outline, () async {
                                  await _zapret.serviceInstalled();
                                  if (mounted) {
                                    await _text(
                                      s.t('zServiceStatus'),
                                      s.t(_zapret.serviceRunning
                                          ? 'zapretOn'
                                          : _zapret.servicePresent
                                              ? 'zServiceStopped'
                                              : 'zServiceAbsent'),
                                    );
                                  }
                                }),
                                _button(
                                  _zapret.servicePresent ? 'zServiceRemove' : 'zServiceInstall',
                                  Icons.settings_suggest_outlined,
                                  () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(s.t('zServiceStatus')),
                                        content: Text(s.t('zServiceWarning')),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
                                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('confirm'))),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true) return;
                                    if (_zapret.servicePresent) {
                                      await _zapret.removeService();
                                    } else if (chosen != null) {
                                      _zapret.configure(settings.settings);
                                      await _zapret.installService(chosen);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final kind in ['discord', 'game'])
                    _dropdown(
                      kind == 'discord' ? s.t('zDiscordFake') : s.t('zGameFake'),
                      _zapret.activeFake(kind),
                      {for (final name in _zapret.fakeFiles()) name: name},
                      (name) => _run(() async {
                        final wasRunning = _zapret.isRunning;
                        if (wasRunning) await _zapret.stop();
                        await _zapret.setActiveFake(kind, name);
                        if (wasRunning && chosen != null) await _start(chosen);
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: s.t('zExtra'),
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('zAutoRestart')),
                subtitle: Text(s.t('zAutoRestartHint')),
                value: settings.settings.zapretAutoRestart,
                onChanged: busy ? null : (v) => settings.update((a) => a.zapretAutoRestart = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('zWssize')),
                subtitle: Text(s.t('zWssizeHint')),
                value: settings.settings.zapretWssize,
                onChanged: busy
                    ? null
                    : (v) => _run(() async {
                          await settings.update((a) => a.zapretWssize = v);
                          _zapret.configure(settings.settings);
                          await _restart();
                        }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('zDebugLog')),
                subtitle: Text(s.t('zDebugLogHint')),
                value: settings.settings.zapretDebugLog,
                onChanged: busy
                    ? null
                    : (v) => _run(() async {
                          await settings.update((a) => a.zapretDebugLog = v);
                          _zapret.configure(settings.settings);
                          await _restart();
                        }),
              ),
              // Free-form winws arguments: this is where DNS overrides and
              // extra flags go. They are now really passed to the process and
              // the capture restarts so the change takes effect at once.
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.t('zExtraArgs'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Tooltip(
                          message: s.t('zExtraArgsHint'),
                          child: Icon(Icons.help_outline_rounded, size: 15, color: p.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _extraArgs,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '--dns=1.1.1.1 --dns=8.8.8.8',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NukefyActionButton(
                          label: s.t('apply'),
                          icon: Icons.play_arrow_rounded,
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                    await settings.update((a) => a.zapretExtraArgs = _extraArgs.text.trim());
                                    _zapret.configure(settings.settings);
                                    await _restart();
                                    if (mounted) showNukefySnack(context, s.t('applied'));
                                  }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _button('zConnectionTest', Icons.network_check_outlined, _connectionTest),
                  _button('zRestartDiscord', Icons.restart_alt_rounded, _restartDiscord),
                  _button('zNetworkReset', Icons.restart_alt_rounded, () async {
                    final confirmed = await confirmDialog(context, title: s.t('zNetworkReset'), body: s.t('zNetworkResetWarning'), confirm: s.t('confirm'), cancel: s.t('cancel'));
                    if (!confirmed) return;
                    final report = await VpnPlatform().windowsNetworkReset();
                    if (mounted) await _text(s.t('zNetworkReset'), report);
                  }),
                  _button('zFolder', Icons.folder_open_outlined, _zapret.openFolder),
                  _button('zDocumentation', Icons.menu_book_outlined, () async {
                    await launchUrl(Uri.parse('https://github.com/Flowseal/zapret-discord-youtube'), mode: LaunchMode.externalApplication);
                  }),
                  _button('zGovHosts', Icons.account_balance_outlined, () async {
                    final confirmed = await confirmDialog(context, title: s.t('zGovHosts'), body: s.t('zHostsBlockWarning'), confirm: s.t('confirm'), cancel: s.t('cancel'));
                    if (!confirmed) return;
                    await _zapret.applyHostBlock(AppConstants.zapretGovernmentMediaHosts);
                    if (mounted) await _text(s.t('zGovHosts'), AppConstants.zapretGovernmentMediaHosts.join('\n'));
                  }),
                ],
              ),
            ],
          ),
        ),
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
    );

    final analysisPage = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: s.t('zapretAnalyze'),
          icon: Icons.analytics_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('zProbeHint'), style: context.palette.secondaryStyle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final target in _targets)
                    FilterChip(
                      avatar: ZapretTargetIcon(id: target.id),
                      label: Text(target.name),
                      selected: settings.settings.zapretCheckTargets.contains(target.id),
                      onSelected: busy
                          ? null
                          : (v) => settings.update((a) {
                                a.zapretCheckTargets = [...a.zapretCheckTargets]..remove(target.id);
                                if (v) a.zapretCheckTargets.add(target.id);
                              }),
                      deleteIcon: target.id.startsWith('custom:') ? const Icon(Icons.close_rounded, size: 16) : null,
                      onDeleted: !target.id.startsWith('custom:') || busy
                          ? null
                          : () => settings.update((a) {
                                a.probeHosts = [...a.probeHosts]..remove(target.id.substring(7));
                                a.zapretCheckTargets = [...a.zapretCheckTargets]..remove(target.id);
                              }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(s.t('zAddService')),
                    onPressed: busy ? null : _addService,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('zQuick')),
                value: _quick,
                onChanged: busy ? null : (v) => setState(() => _quick = v),
              ),
              if (vpnOn) Text(s.t('zapretAnalyzeVpnOn'), style: TextStyle(color: p.accent)),
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _analyzing
                          ? () => _cancel?.cancel()
                          : busy || _checking || _preparingAnalysis || vpnOn || !_targets.any((t) => settings.settings.zapretCheckTargets.contains(t.id))
                              ? null
                              : _analyze,
                      icon: Icon(_analyzing ? Icons.stop : Icons.play_arrow),
                      label: Text(s.t(_analyzing ? 'cancel' : 'zapretAnalyze')),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _analyzing
                            ? '$_step / ${_strategies.length}'
                            : _best != null
                                ? s.t('zapretApplied')
                                : _step > 0
                                    ? s.t('zAnalysisFinished')
                                    : '',
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(value: _analyzing ? _step / _strategies.length : 0, minHeight: 3),
            ],
          ),
        ),
        if (_failureReport != null && !_analyzing)
          SectionCard(
            title: s.t('zapretAllFailed'),
            icon: Icons.report_problem_rounded,
            description: s.t('zapretAllFailedHint'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(_failureReport!, style: AppTextStyles.monoValue.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _failureReport!)),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(s.t('zCopyReport')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final report = await _zapret.diagnostics();
                          if (mounted) await _text(s.t('zDiagnostics'), report);
                        } catch (error) {
                          if (mounted) await _text(s.t('zDiagnostics'), '$error');
                        }
                      },
                      icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                      label: Text(s.t('zDiagnostics')),
                    ),
                    OutlinedButton.icon(
                      onPressed: chosen == null
                          ? null
                          : () async {
                              try {
                                _zapret.configure(settings.settings);
                                if (_zapret.servicePresent) {
                                  // A broken binPath from an older build must
                                  // be replaceable, not "already installed".
                                  await _zapret.removeService();
                                }
                                await _zapret.installService(chosen);
                                if (mounted) showNukefySnack(context, s.t('zServiceInstalled'));
                              } catch (error) {
                                if (mounted) showNukefySnack(context, '$error');
                              }
                            },
                      icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                      label: Text(s.t(_zapret.servicePresent ? 'zServiceReinstall' : 'zServiceInstall')),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                    height: 132 * MediaQuery.textScalerOf(context).scale(1),
                    child: _tile(strategy, strategy.id == chosen?.id, busy),
                  ),
              ],
            );
          }),
        ),
      ],
    );

    final strategySummary = SectionCard(
      title: s.t('zapretStrategy'),
      icon: Icons.route_rounded,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.alt_route_rounded, color: p.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chosen?.title ?? s.t('zapretUnknown'), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(s.t(running ? 'zapretOn' : 'zapretOff'), style: p.secondaryStyle),
              ],
            ),
          ),
          if (_best == chosen?.id) Icon(Icons.verified_rounded, color: p.success),
        ],
      ),
    );

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, _) => SingleChildScrollView(
          key: const PageStorageKey('zapret-main'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text('ZAPRET', style: AppTextStyles.title)),
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: TextButton.icon(
                        onPressed: _checking || busy ? null : _checkUpdate,
                        icon: const Icon(Icons.system_update_alt),
                        label: Text(s.t(_checking ? 'zChecking' : 'zCheckUpdate')),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _error == null
                      ? Text(s.t('zapretHint'), style: context.palette.secondaryStyle)
                      : InkWell(
                          onTap: () => _text(s.t('zError'), _error!),
                          child: Text(
                            _error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                ),
              ),
              // A failed capture must not be a one-line mystery: the same
              // report the log holds (strategy, command line, last winws
              // lines) is shown and can be copied in one tap.
              if (_error != null) _ZapretFailureReport(zapret: _zapret, error: _error!),
              if (_update != null && settings.settings.zapretSkippedVersion != _update!.version)
                SectionCard(
                  title: '${s.t('zUpdateAvailable')} ${_update!.version}',
                  icon: Icons.update,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('zUpdateTrust')),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(onPressed: () => _text(_update!.version, _update!.notes), child: Text(s.t('zReleaseNotes'))),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                    await _updater.install(_update!, (progress) {
                                      if (mounted) setState(() => _download = progress.fraction);
                                    });
                                    if (mounted) {
                                      setState(() {
                                        _strategies = _zapret.strategies();
                                        _update = null;
                                        _download = null;
                                      });
                                    }
                                  }),
                            child: Text(s.t('zInstall')),
                          ),
                          TextButton(
                            onPressed: busy ? null : () => settings.update((a) => a.zapretSkippedVersion = _update!.version),
                            child: Text(s.t('zLater')),
                          ),
                        ],
                      ),
                      if (_download != null) LinearProgressIndicator(value: _download),
                    ],
                  ),
                ),
              if (!_zapret.isSupported)
                Text(s.t('zapretMissing'))
              else if (widget.settingsOnly) ...[
                domainCard,
                settingsPage,
              ] else ...[
                Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [conflictCard, activation],
                    ),
                  ),
                ),
                strategySummary,
                if (_showAnalysis) analysisPage,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String? value, Map<String, String> values, void Function(String) changed) {
    final selected = values.containsKey(value) ? value! : values.keys.first;
    return SizedBox(
      width: 240,
      child: Opacity(
        opacity: _zapret.busy ? .55 : 1,
        child: IgnorePointer(
          ignoring: _zapret.busy,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.palette.captionStyle),
            const SizedBox(height: 5),
            NukefyDropdown<String>(value: selected, items: values, onChanged: changed),
          ]),
        ),
      ),
    );
  }

  Widget _tile(ZapretStrategy strategy, bool selected, bool busy) {
    final p = context.palette;
    final results = _results[strategy.id];
    final color = _best == strategy.id ? p.success : p.accent;
    return Material(
      color: selected ? color.withValues(alpha: .12) : p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color : p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => _run(() async {
          final settings = context.read<SettingsProvider>();
          final running = _zapret.isRunning;
          if (running && !settings.settings.zapretAutoRestart) {
            final ok = await confirmDialog(
              context,
              title: s.t('zAutoRestart'),
              body: '${strategy.id}: ${s.t('zapretRestartConfirm')}',
              confirm: s.t('confirm'),
              cancel: s.t('cancel'),
            );
            if (!ok) return;
          }
          // Applying a strategy now means applying it for real: save the
          // choice and (re)start the capture immediately, so a click changes
          // what is happening on the machine rather than only the checkbox.
          _zapret.configure(settings.settings);
          if (!await _zapret.start(strategy)) throw StateError(_zapret.lastError ?? 'winws failed');
          await settings.update((a) => a.zapretStrategy = strategy.id);
          if (mounted) showNukefySnack(context, '${s.t('applied')}: ${strategy.id}');
        }),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('#${strategy.number.toString().padLeft(2, '0')}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_current == strategy.id)
                  const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                else if (_best == strategy.id)
                  Icon(Icons.verified_rounded, color: color, size: 18)
                else if (selected)
                  Icon(Icons.check_circle_rounded, color: color, size: 18),
              ]),
              const SizedBox(height: 8),
              Text(
                strategy.id == 'general' ? s.t('zapretSubMain') : strategy.id.replaceFirst('general', '').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              SizedBox(
                height: 22,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final target in _targets.where((t) => context.read<SettingsProvider>().settings.zapretCheckTargets.contains(t.id)))
                      Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: Tooltip(
                          message: '${target.name}: ${results?.where((r) => r.targetId == target.id).firstOrNull?.statusCode ?? '—'}',
                          child: Row(children: [
                            ZapretTargetIcon(id: target.id),
                            const SizedBox(width: 3),
                            Icon(
                              results == null
                                  ? Icons.remove
                                  : results.any((r) => r.targetId == target.id && r.ok) ? Icons.check : Icons.close,
                              size: 13,
                              color: results == null
                                  ? p.textSecondary
                                  : results.any((r) => r.targetId == target.id && r.ok) ? p.success : AppColors.error,
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZapretPowerButton extends StatelessWidget {
  const _ZapretPowerButton({
    required this.running,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  final bool running;
  final bool busy;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = running ? p.success : p.accent;
    final diameter = (MediaQuery.sizeOf(context).width * .46).clamp(144.0, 184.0).toDouble();
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: .26), p.accent2.withValues(alpha: .18)],
              ),
              border: Border.all(color: color.withValues(alpha: .62), width: 1.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: .18), blurRadius: 34, spreadRadius: 3),
              ],
            ),
            child: Center(
              child: busy
                  ? SizedBox(width: diameter * .23, height: diameter * .23, child: CircularProgressIndicator(color: color, strokeWidth: 3))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(running ? Icons.shield_rounded : Icons.power_settings_new_rounded, size: diameter * .28, color: color),
                        SizedBox(height: diameter * .055),
                        Text(label.toUpperCase(), style: AppTextStyles.status.copyWith(color: color, fontSize: 10, letterSpacing: 1.1)),
                      ],
                    ),
            ),
          ),
        ),
      ),
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

/// Copyable block with everything needed to explain a failed start: the exact
/// winws command line, the exit reason and the tail of winws output.
class _ZapretFailureReport extends StatelessWidget {
  const _ZapretFailureReport({required this.zapret, required this.error});

  final ZapretService zapret;
  final String error;

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsProvider>().strings;
    final p = context.palette;
    final lines = zapret.log.length <= 12 ? zapret.log : zapret.log.sublist(zapret.log.length - 12);
    final report = [
      'Nukefy Client — zapret start report',
      'error: $error',
      'strategy: ${zapret.runningStrategyId ?? '-'}',
      'command: ${zapret.lastCommandLine ?? '-'}',
      'service: ${zapret.servicePresent ? 'installed' : 'none'}${zapret.serviceRunning ? ' (running)' : ''}',
      '--- winws output ---',
      ...lines,
    ].join('\n');
    return SectionCard(
      title: s.t('zFailReport'),
      icon: Icons.report_gmailerrorred_rounded,
      trailing: IconButton(
        tooltip: s.t('copy'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: report));
          if (context.mounted) showNukefySnack(context, s.t('copied'));
        },
        icon: const Icon(Icons.copy_rounded, size: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error, style: TextStyle(color: AppColors.error, fontSize: 12.5)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: SelectableText(
              report,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
