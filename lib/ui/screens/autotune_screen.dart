import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/karing_service.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/services/system_diagnostic_service.dart';
import '../../core/services/whitelist_mirrors.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_logo.dart';
import '../widgets/section_card.dart';

enum _Stage { intro, purpose, analysis, plan, done }

enum _Purpose { games, media, vpn, balanced }

class _PlanItem {
  _PlanItem({required this.id, required this.label, this.detail, this.checked = true, this.destructive = false});

  final String id;
  final String label;
  final String? detail;
  bool checked;

  /// Touches system settings instead of app settings; never checked by default.
  final bool destructive;
}

/// Staged auto-setup wizard: purpose → analysis → plan → apply. Every change
/// is shown before it happens and nothing system-level is touched unless the
/// user explicitly keeps the corresponding checkbox.
class AutoTuneScreen extends StatefulWidget {
  const AutoTuneScreen({super.key});

  @override
  State<AutoTuneScreen> createState() => _AutoTuneScreenState();
}

class _AutoTuneScreenState extends State<AutoTuneScreen> {
  final _diag = SystemDiagnosticService();
  _Stage _stage = _Stage.intro;
  _Purpose _purpose = _Purpose.balanced;
  List<DiagFinding> _findings = [];
  List<_PlanItem> _plan = [];
  bool _busy = false;
  bool _restartNeeded = false;

  S get s => context.read<SettingsProvider>().strings;

  Future<void> _goto(_Stage next) async {
    setState(() => _stage = next);
    if (next == _Stage.analysis) await _analyze();
    if (next == _Stage.plan) _buildPlan();
  }

  Future<void> _analyze() async {
    setState(() => _busy = true);
    try {
      final findings = await _diag.analyze();
      if (mounted) setState(() => _findings = findings);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _buildPlan() {
    final s = this.s;
    final items = <_PlanItem>[];
    switch (_purpose) {
      case _Purpose.games:
        items.add(_PlanItem(id: 'zapret', label: s.t('zapretAutoStart'), detail: s.t('zapretAutoStartHint')));
        items.add(_PlanItem(id: 'gamefilter', label: s.t('zapretGameFilter'), detail: 'TCP + UDP'));
        items.add(_PlanItem(id: 'dns', label: s.t('dnsCloudflare'), detail: s.t('dnsHint')));
        items.add(_PlanItem(id: 'boot', label: s.t('launchOnBoot'), detail: s.t('startInTrayHint')));
      case _Purpose.media:
        items.add(_PlanItem(id: 'karing', label: s.t('karingEnable'), detail: s.t('karingEnableHint')));
        items.add(_PlanItem(id: 'whitelist', label: s.t('karingAddSub'), detail: WhitelistCatalog.defaultName));
        items.add(_PlanItem(id: 'balancer', label: s.t('karingBalancer'), detail: s.t('karingBalancerHint')));
      case _Purpose.vpn:
        items.add(_PlanItem(id: 'tun', label: s.t('tun'), detail: s.t('tunHint')));
        items.add(_PlanItem(id: 'balancer', label: s.t('karingBalancer'), detail: s.t('karingBalancerHint')));
        items.add(_PlanItem(id: 'autoconnect', label: s.t('autoConnect'), detail: s.t('autoConnectHint')));
      case _Purpose.balanced:
        items.add(_PlanItem(id: 'dns', label: s.t('dnsCloudflare'), detail: s.t('dnsHint')));
        items.add(_PlanItem(id: 'boot', label: s.t('launchOnBoot'), detail: s.t('startInTrayHint')));
        items.add(_PlanItem(id: 'tray', label: s.t('minimizeToTray')));
    }
    // Conflict-driven remedies.
    for (final finding in _findings) {
      if (finding.id == 'warp' && _purpose == _Purpose.vpn) {
        items.add(_PlanItem(
          id: 'warp-coexist',
          label: s.t('diagWarp'),
          detail: s.t('diagWarpHint'),
        ));
      }
      if (finding.id == 'proxy') {
        items.add(_PlanItem(
          id: 'proxy-off',
          label: s.t('diagProxy'),
          detail: s.t('diagProxyHint'),
          checked: false,
          destructive: true,
        ));
      }
    }
    _plan = items;
  }

  Future<void> _apply() async {
    final settings = context.read<SettingsProvider>();
    final servers = context.read<ServersProvider>();
    final vpn = context.read<VpnProvider>();
    setState(() => _busy = true);
    final chosen = _plan.where((item) => item.checked).map((item) => item.id).toSet();
    try {
      await settings.update((value) {
        if (chosen.contains('zapret')) value.zapretAutoStart = true;
        if (chosen.contains('gamefilter')) {
          value.zapretGameFilter = true;
          value.zapretGameMode = 'all';
        }
        if (chosen.contains('dns')) {
          value.dnsPreset = 'cloudflare';
          value.proxyDns = 'https://cloudflare-dns.com/dns-query';
          value.directDns = '1.1.1.1';
        }
        if (chosen.contains('boot')) value.launchOnBoot = true;
        if (chosen.contains('tray')) {
          value.minimizeToTray = true;
          value.startInTray = true;
        }
        if (chosen.contains('karing')) {
          value.karingEnabled = true;
          value.routingMode = RoutingMode.global;
        }
        if (chosen.contains('balancer')) value.karingBalancer = true;
        if (chosen.contains('tun')) value.tunEnabled = true;
        if (chosen.contains('autoconnect')) value.autoConnect = true;
        if (chosen.contains('warp-coexist')) {
          // WARP owns a TUN device; Nukefy steps back to local proxy mode so
          // both stay usable instead of fighting over the adapter.
          value.tunEnabled = false;
          value.localProxyEnabled = true;
        }
      });
      if (chosen.contains('boot') || chosen.contains('tray')) {
        await VpnPlatform().setAutoStart(
          settings.settings.launchOnBoot,
          startInTray: settings.settings.startInTray,
        );
        _restartNeeded = true;
      }
      if (chosen.contains('whitelist')) {
        final existing = servers.subscriptions.where((sub) => WhitelistCatalog.isWhitelistUrl(sub.url)).firstOrNull;
        if (existing == null) {
          final mirror = await KaringService.instance.firstReachable();
          await servers.addSubscription(mirror?.url ?? WhitelistCatalog.mirrors.first.url, name: WhitelistCatalog.defaultName);
        }
      }
      if (chosen.contains('proxy-off')) {
        await _diag.disableSystemProxy();
      }
      if (chosen.contains('zapret') || chosen.contains('gamefilter')) {
        final zapret = ZapretService.instance;
        if (zapret.isSupported && !zapret.isRunning) {
          final strategies = zapret.strategies();
          final strategy = strategies.where((item) => item.id == settings.settings.zapretStrategy).firstOrNull ?? strategies.firstOrNull;
          if (strategy != null) {
            zapret.configure(settings.settings);
            await zapret.start(strategy);
          }
        }
      }
      if (vpn.status == VpnStatus.connected) _restartNeeded = true;
      if (mounted) setState(() => _stage = _Stage.done);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    return SafeArea(
      bottom: false,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: SingleChildScrollView(
          key: ValueKey(_stage),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: switch (_stage) {
                _Stage.intro => _intro(s, p),
                _Stage.purpose => _purposeView(s, p),
                _Stage.analysis => _analysisView(s, p),
                _Stage.plan => _planView(s, p),
                _Stage.done => _doneView(s, p),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(S s, NukefyPalette p, String stageKey) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final stage in _Stage.values)
                Container(
                  width: 26,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: stage.index <= _stage.index ? p.accent : p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.t(stageKey), style: AppTextStyles.headline, textAlign: TextAlign.center),
          const SizedBox(height: 18),
        ],
      );

  Widget _intro(S s, NukefyPalette p) => Column(
        children: [
          const NukefyLogo(size: 84),
          const SizedBox(height: 18),
          Text(s.t('autoTitle'), style: AppTextStyles.title, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(s.t('autoHint'), style: p.secondaryStyle, textAlign: TextAlign.center),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: () => _goto(_Stage.purpose),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(s.t('autoStart')),
          ),
        ],
      );

  Widget _purposeView(S s, NukefyPalette p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, p, 'autoStagePurpose'),
          for (final purpose in _Purpose.values)
            _ChoiceTile(
              title: s.t(switch (purpose) {
                _Purpose.games => 'autoPurposeGames',
                _Purpose.media => 'autoPurposeMedia',
                _Purpose.vpn => 'autoPurposeVpn',
                _Purpose.balanced => 'autoPurposeBalanced',
              }),
              subtitle: s.t(switch (purpose) {
                _Purpose.games => 'autoPurposeGamesHint',
                _Purpose.media => 'autoPurposeMediaHint',
                _Purpose.vpn => 'autoPurposeVpnHint',
                _Purpose.balanced => 'autoPurposeBalancedHint',
              }),
              icon: switch (purpose) {
                _Purpose.games => Icons.sports_esports_rounded,
                _Purpose.media => Icons.play_circle_outline_rounded,
                _Purpose.vpn => Icons.vpn_key_outlined,
                _Purpose.balanced => Icons.balance_rounded,
              },
              selected: _purpose == purpose,
              onTap: () => setState(() => _purpose = purpose),
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: () => _goto(_Stage.intro), child: Text(s.t('autoBack'))),
              FilledButton(onPressed: () => _goto(_Stage.analysis), child: Text(s.t('autoNext'))),
            ],
          ),
        ],
      );

  Widget _analysisView(S s, NukefyPalette p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, p, 'autoStageAnalysis'),
          if (_busy) ...[
            const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())),
            const SizedBox(height: 8),
            Center(child: Text(s.t('autoAnalyzing'), style: p.secondaryStyle)),
          ] else ...[
            if (_findings.isEmpty)
              Center(child: Text(s.t('autoNoIssues'), style: AppTextStyles.bodyRegular))
            else
              for (final finding in _findings)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: finding.severity == DiagSeverity.conflict ? p.error.withValues(alpha: .6) : p.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t(finding.titleKey), style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(s.t(finding.hintKey), style: p.secondaryStyle),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: () => _goto(_Stage.purpose), child: Text(s.t('autoBack'))),
                FilledButton(onPressed: () => _goto(_Stage.plan), child: Text(s.t('autoNext'))),
              ],
            ),
          ],
        ],
      );

  Widget _planView(S s, NukefyPalette p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, p, 'autoStagePlan'),
          SectionCard(
            title: s.t('autoPlan'),
            icon: Icons.checklist_rounded,
            child: Column(
              children: [
                for (final item in _plan)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: item.checked,
                    title: Text(item.label),
                    subtitle: item.detail == null ? null : Text(item.detail!),
                    onChanged: (value) => setState(() => item.checked = value ?? false),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: () => _goto(_Stage.analysis), child: Text(s.t('autoBack'))),
              FilledButton(onPressed: _busy ? null : _apply, child: Text(s.t('autoApply'))),
            ],
          ),
        ],
      );

  Widget _doneView(S s, NukefyPalette p) => Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 64, color: p.success),
          const SizedBox(height: 14),
          Text(s.t('autoApplied'), style: AppTextStyles.title),
          if (_restartNeeded) ...[
            const SizedBox(height: 10),
            Text(s.t('autoRestartNeeded'), style: p.secondaryStyle, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.read<NavProvider>().go(NavDestination.settings),
                icon: const Icon(Icons.settings_outlined, size: 17),
                label: Text(s.t('settings')),
              ),
              FilledButton(onPressed: () => _goto(_Stage.intro), child: Text(s.t('autoStart'))),
            ],
          ),
        ],
      );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: .12) : p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? p.accent : p.border, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? p.accent : p.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: p.secondaryStyle),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: p.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
