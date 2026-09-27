import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/zapret_probe.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';

/// Desktop tab: DPI bypass (zapret / winws) without a VPN — one button,
/// pretty strategy cards, a "does it actually work" analysis and your own
/// domain list. Nothing that looks like a console.
class ZapretScreen extends StatefulWidget {
  const ZapretScreen({super.key});

  @override
  State<ZapretScreen> createState() => _ZapretScreenState();
}

class _ZapretScreenState extends State<ZapretScreen> with SingleTickerProviderStateMixin {
  final _zapret = ZapretService.instance;

  bool _busy = false;
  bool _showLog = false;

  // Analysis state.
  bool _analyzing = false;
  bool _cancel = false;
  int _step = 0;
  int _total = 0;
  String? _currentId;
  String? _bestId;
  final Map<String, List<ZapretProbeResult>> _results = {};

  List<ZapretStrategy> _strategies = const [];
  List<String> _domains = const [];

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _zapret.addListener(_onChange);
    _reload();
  }

  @override
  void dispose() {
    _zapret.removeListener(_onChange);
    _pulse.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _reload() {
    _strategies = _zapret.strategies();
    _domains = _zapret.loadDomains();
  }

  Future<void> _toggle() async {
    if (_busy || _analyzing) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final settings = context.read<SettingsProvider>();
    if (_zapret.isRunning) {
      await _zapret.stop();
    } else {
      final chosen = _strategies.where((s) => s.id == settings.settings.zapretStrategy).firstOrNull ?? _strategies.firstOrNull;
      if (chosen != null) {
        _zapret.gameFilter = settings.settings.zapretGameFilter;
        await _zapret.start(chosen);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Runs every strategy in turn and checks YouTube and Discord after each
  /// start, then keeps the one that opened most of them.
  Future<void> _analyze() async {
    if (_analyzing || _strategies.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    final s = settings.strings;
    final wasRunning = _zapret.isRunning;
    HapticFeedback.selectionClick();

    setState(() {
      _analyzing = true;
      _cancel = false;
      _step = 0;
      _total = _strategies.length;
      _currentId = null;
      _bestId = null;
      _results.clear();
    });

    String? best;
    var bestScore = -1;
    for (final strategy in _strategies) {
      if (_cancel || !mounted) break;
      setState(() {
        _step++;
        _currentId = strategy.id;
      });

      // start() already kills a stray winws, so no sweep is needed here —
      // it would only add a process spawn to every iteration.
      await _zapret.stop(sweep: false);
      _zapret.gameFilter = settings.settings.zapretGameFilter;
      final started = await _zapret.start(strategy);
      if (!started) {
        _results[strategy.id] = [
          for (final target in ZapretProbe.defaults) ZapretProbeResult(targetId: target.id, ok: false),
        ];
        if (mounted) setState(() {});
        continue;
      }
      // WinDivert needs a moment to install the filter before the checks
      // mean anything.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (_cancel || !mounted) break;

      final probe = await ZapretProbe.instance.check();
      _results[strategy.id] = probe;
      final score = probe.where((e) => e.ok).length;
      if (score > bestScore) {
        bestScore = score;
        best = strategy.id;
      }
      if (mounted) setState(() {});
    }

    await _zapret.stop();
    if (!mounted) return;
    setState(() {
      _analyzing = false;
      _currentId = null;
      _bestId = bestScore > 0 ? best : null;
    });

    if (best != null && bestScore > 0) {
      await settings.update((value) => value.zapretStrategy = best!);
      if (!mounted) return;
      if (wasRunning) {
        final chosen = _strategies.where((e) => e.id == best).firstOrNull;
        if (chosen != null) {
          _zapret.gameFilter = settings.settings.zapretGameFilter;
          await _zapret.start(chosen);
        }
      }
      if (mounted) showNukefySnack(context, s.t('zapretApplied'));
    }
  }

  Future<void> _selectStrategy(ZapretStrategy strategy) async {
    if (_analyzing) return;
    final settings = context.read<SettingsProvider>();
    HapticFeedback.selectionClick();
    await settings.update((value) => value.zapretStrategy = strategy.id);
    if (!mounted) return;
    if (_zapret.isRunning && _zapret.runningStrategyId != strategy.id) {
      _zapret.gameFilter = settings.settings.zapretGameFilter;
      await _zapret.start(strategy);
    }
  }

  Future<void> _addDomain() async {
    final s = context.read<SettingsProvider>().strings;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(s.t('zapretAddDomain'), style: AppTextStyles.headline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (text) => Navigator.pop(context, text),
                decoration: InputDecoration(
                  hintText: s.t('zapretDomainPlaceholder'),
                  helperText: s.t('zapretDomainOnePerLine'),
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(s.t('add'))),
          ],
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        );
      },
    );
    if (!mounted || value == null) return;

    final pieces = value
        .split(RegExp(r'[\s,;]+'))
        .map(ZapretService.normalizeDomain)
        .where((e) => e.isNotEmpty)
        .toList();
    if (pieces.isEmpty) return;

    final invalid = pieces.where((e) => !ZapretService.looksLikeDomain(e)).toList();
    if (invalid.isNotEmpty) {
      showNukefySnack(context, '${s.t('zapretDomainInvalid')}: ${invalid.join(', ')}', error: true);
      return;
    }

    final next = <String>[..._domains];
    var added = 0;
    for (final piece in pieces) {
      if (next.contains(piece)) continue;
      next.add(piece);
      added++;
    }
    if (added == 0) {
      showNukefySnack(context, s.t('zapretDomainExists'), error: true);
      return;
    }
    await _zapret.saveDomains(next);
    if (!mounted) return;
    setState(() => _domains = next);
    showNukefySnack(context, s.t('zapretDomainAdded'));
    await _restartIfRunning();
  }

  Future<void> _removeDomain(String domain) async {
    final s = context.read<SettingsProvider>().strings;
    final next = [..._domains]..remove(domain);
    await _zapret.saveDomains(next);
    if (!mounted) return;
    setState(() => _domains = next);
    showNukefySnack(context, s.t('zapretDomainRemoved'));
    await _restartIfRunning();
  }

  /// Domains only reach winws when it starts, so a running instance has to be
  /// restarted for the change to matter.
  Future<void> _restartIfRunning() async {
    if (!_zapret.isRunning) return;
    final settings = context.read<SettingsProvider>();
    final chosen = _strategies.where((e) => e.id == _zapret.runningStrategyId).firstOrNull;
    if (chosen == null) return;
    _zapret.gameFilter = settings.settings.zapretGameFilter;
    await _zapret.start(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final supported = _zapret.isSupported;
    final running = _zapret.isRunning;
    final vpnOn = context.watch<VpnProvider>().status == VpnStatus.connected;
    final selectedId = _strategies.any((e) => e.id == settings.settings.zapretStrategy)
        ? settings.settings.zapretStrategy
        : (_strategies.firstOrNull?.id ?? '');

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 100),
        children: [
          Row(
            children: [
              Expanded(child: Text(s.t('zapret'), style: AppTextStyles.title.copyWith(color: p.text))),
              if (supported)
                IconButton(
                  tooltip: s.t('logs'),
                  onPressed: () => setState(() => _showLog = !_showLog),
                  icon: Icon(Icons.terminal_rounded, color: _showLog ? p.accent : p.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.t('zapretHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
          const SizedBox(height: 22),
          if (!supported)
            _Notice(icon: Icons.info_outline_rounded, text: s.t('zapretMissing'))
          else ...[
            // Big toggle.
            Center(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final glow = running ? 0.25 + _pulse.value * 0.35 : 0.0;
                  return GestureDetector(
                    onTap: _analyzing ? null : _toggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: running
                              ? [p.success, const Color(0xFF0FA3B1)]
                              : (p.isDark ? const [Color(0xFF232A36), Color(0xFF12161E)] : const [Colors.white, Color(0xFFE3E8F0)]),
                        ),
                        border: Border.all(color: running ? Colors.white.withValues(alpha: 0.18) : p.border, width: 1.2),
                        boxShadow: [
                          BoxShadow(color: p.success.withValues(alpha: glow * 0.6), blurRadius: 40, spreadRadius: 2),
                          BoxShadow(color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.1), blurRadius: 24, offset: const Offset(0, 12)),
                        ],
                      ),
                      child: Center(
                        child: _busy
                            ? SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: running ? const Color(0xFF07131A) : p.accent))
                            : Icon(
                                Icons.shield_rounded,
                                size: 58,
                                color: running ? const Color(0xFF07131A) : p.textSecondary,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                (running ? s.t('zapretOn') : s.t('zapretOff')).toUpperCase(),
                style: AppTextStyles.status.copyWith(color: running ? p.success : p.textSecondary),
              ),
            ),
            if (running && _zapret.runningStrategyId != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _titleOf(_zapret.runningStrategyId!),
                  style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary),
                ),
              ),
            ],
            if (_zapret.lastError != null) ...[
              const SizedBox(height: 14),
              _Notice(icon: Icons.error_outline_rounded, text: _friendly(s, _zapret.lastError!), error: true),
            ],
            const SizedBox(height: 22),

            // ── Analysis ────────────────────────────────────────────────
            _AnalysisCard(
              strings: s,
              analyzing: _analyzing,
              step: _step,
              total: _total,
              currentTitle: _currentId == null ? null : _titleOf(_currentId!),
              vpnOn: vpnOn,
              onStart: _analyze,
              onCancel: () => setState(() => _cancel = true),
            ),

            // ── Strategies ──────────────────────────────────────────────
            SectionCard(
              title: s.t('zapretStrategy'),
              icon: Icons.tune_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(s.t('zapretStrategyHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                  ),
                  for (final strategy in _strategies)
                    _StrategyCard(
                      title: _titleOf(strategy.id),
                      subtitle: _subtitleOf(s, strategy.id),
                      selected: strategy.id == selectedId,
                      active: running && strategy.id == _zapret.runningStrategyId,
                      testing: _analyzing && _currentId == strategy.id,
                      best: _bestId == strategy.id,
                      results: _results[strategy.id],
                      onTap: () => _selectStrategy(strategy),
                    ),
                ],
              ),
            ),

            // ── Your domains ────────────────────────────────────────────
            _DomainsCard(
              strings: s,
              domains: _domains,
              onAdd: _addDomain,
              onRemove: _removeDomain,
            ),

            SectionCard(
              title: s.t('general'),
              icon: Icons.settings_outlined,
              child: Column(
                children: [
                  SwitchTile(
                    icon: Icons.sports_esports_outlined,
                    title: s.t('zapretGameFilter'),
                    subtitle: s.t('zapretGameFilterHint'),
                    value: settings.settings.zapretGameFilter,
                    onChanged: (v) async {
                      await settings.update((item) => item.zapretGameFilter = v);
                      if (_zapret.isRunning) await _restartIfRunning();
                    },
                  ),
                  SwitchTile(
                    icon: Icons.power_settings_new_rounded,
                    title: s.t('zapretAutoStart'),
                    subtitle: s.t('zapretAutoStartHint'),
                    value: settings.settings.zapretAutoStart,
                    onChanged: (v) => settings.update((item) => item.zapretAutoStart = v),
                  ),
                ],
              ),
            ),
            if (_showLog)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.border),
                ),
                child: SelectableText(
                  _zapret.log.isEmpty ? '—' : _zapret.log.join('\n'),
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _titleOf(String id) {
    final found = _strategies.where((e) => e.id == id).firstOrNull;
    if (found != null) return found.title;
    return ZapretService.instance.strategies().where((e) => e.id == id).firstOrNull?.title ?? id;
  }

  /// Short, human note under a strategy title.
  String _subtitleOf(S s, String id) {
    final lower = id.toLowerCase();
    if (lower == 'general') return s.t('zapretSubMain');
    final alt = RegExp(r'alt\s*(\d*)').firstMatch(lower);
    if (alt != null && lower.contains('alt')) {
      final n = alt.group(1) ?? '';
      return n.isEmpty ? s.t('zapretSubAlt') : '${s.t('zapretSubAlt')} $n';
    }
    if (lower.contains('fake tls auto') || lower.contains('faketlsauto')) return s.t('zapretSubFakeAuto');
    if (lower.contains('simple fake') || lower.contains('simplefake')) return s.t('zapretSubSimpleFake');
    if (lower.contains('exp')) return s.t('zapretSubExp');
    if (lower.contains('discord')) return s.t('zapretSubDiscord');
    if (lower.contains('youtube')) return s.t('zapretSubYoutube');
    return '';
  }

  String _friendly(S s, String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('windivert') || lower.contains('driver') || lower.contains('access is denied') || lower.contains('1275')) {
      return s.t('zapretNeedAdmin');
    }
    return raw;
  }
}

/// "Analyze" card: one button, live progress while the strategies are tried.
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.strings,
    required this.analyzing,
    required this.step,
    required this.total,
    required this.currentTitle,
    required this.vpnOn,
    required this.onStart,
    required this.onCancel,
  });

  final S strings;
  final bool analyzing;
  final int step;
  final int total;
  final String? currentTitle;
  final bool vpnOn;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = strings;
    final ratio = total == 0 ? 0.0 : (step / total).clamp(0.0, 1.0);
    return SectionCard(
      title: s.t('zapretAnalyze'),
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('zapretAnalysisHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
          // Which services are checked.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final target in ZapretProbe.defaults)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BrandMark(target: target, size: 16),
                      const SizedBox(width: 7),
                      Text(target.name, style: AppTextStyles.bodyRegular.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
                    ],
                  ),
                ),
            ],
          ),
          if (vpnOn) ...[
            const SizedBox(height: 12),
            _Notice(icon: Icons.vpn_lock_rounded, text: s.t('zapretAnalyzeVpnOn')),
          ],
          const SizedBox(height: 14),
          if (!analyzing)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(s.t('zapretAnalyze')),
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: p.surface,
                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.t('zapretAnalyzing')} · $step ${s.t('of')} $total'
                    '${currentTitle == null ? '' : ' · $currentTitle'}',
                    style: AppTextStyles.bodySecondary.copyWith(color: p.text, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: Text(s.t('cancel')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One strategy: title, note, live result badges and a "best" marker.
class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.active,
    required this.testing,
    required this.best,
    required this.results,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool active;
  final bool testing;
  final bool best;
  final List<ZapretProbeResult>? results;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final color = best ? p.success : (active ? p.success : p.accent);
    final borderColor = selected ? color.withValues(alpha: 0.7) : p.border;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.1) : p.surface.withValues(alpha: p.isDark ? 0.6 : 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            ),
            child: Row(
              children: [
                // Selection dot.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? color : p.textDisabled, width: selected ? 6 : 1.6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: p.text),
                            ),
                          ),
                          if (best) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.success.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s.t('zapretBest').toUpperCase(),
                                style: AppTextStyles.tab.copyWith(fontSize: 8, letterSpacing: 1, color: p.success),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (testing)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                else if (results != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final target in ZapretProbe.defaults)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _BrandMark(
                            target: target,
                            size: 22,
                            state: results!.any((r) => r.targetId == target.id && r.ok)
                                ? _MarkState.ok
                                : _MarkState.fail,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _MarkState { none, ok, fail }

/// Brand logo with a small status dot. Uses the bundled marks, falls back to
/// an icon if an asset is missing.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.target, this.size = 22, this.state = _MarkState.none});

  final ZapretProbeTarget target;
  final double size;
  final _MarkState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dotColor = switch (state) {
      _MarkState.ok => p.success,
      _MarkState.fail => AppColors.error,
      _MarkState.none => Colors.transparent,
    };
    final fallbackIcon = target.id == 'youtube' ? Icons.play_circle_fill_rounded : Icons.forum_rounded;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/brands/${target.id}.png',
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Icon(fallbackIcon, size: size, color: AppColors.error),
            ),
          ),
          if (state != _MarkState.none)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.card, width: 1.6),
                ),
                child: Icon(
                  state == _MarkState.ok ? Icons.check_rounded : Icons.close_rounded,
                  size: 7,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "My domains" card: what the user asked to unblock.
class _DomainsCard extends StatelessWidget {
  const _DomainsCard({
    required this.strings,
    required this.domains,
    required this.onAdd,
    required this.onRemove,
  });

  final S strings;
  final List<String> domains;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = strings;
    return SectionCard(
      title: s.t('zapretDomains'),
      icon: Icons.add_link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('zapretDomainsHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
          if (domains.isEmpty)
            Text(s.t('zapretDomainsEmpty'), style: AppTextStyles.bodySecondary.copyWith(color: p.textDisabled))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final domain in domains)
                  _DomainChip(
                    domain: domain,
                    onDelete: () => onRemove(domain),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(s.t('zapretAddDomain')),
            ),
          ),
          const SizedBox(height: 8),
          Text(s.t('zapretApplyHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textDisabled, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _DomainChip extends StatelessWidget {
  const _DomainChip({required this.domain, required this.onDelete});
  final String domain;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language_rounded, size: 15, color: p.accent),
          const SizedBox(width: 7),
          Text(domain, style: AppTextStyles.bodyRegular.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 14, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.error = false});
  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = error ? AppColors.error : p.accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySecondary.copyWith(color: error ? color : p.text, fontSize: 12.5))),
        ],
      ),
    );
  }
}
