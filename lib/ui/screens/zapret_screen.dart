import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/section_card.dart';

/// Desktop tab: DPI bypass (zapret / winws) without a VPN — one button,
/// a strategy picker and nothing that looks like a console.
class ZapretScreen extends StatefulWidget {
  const ZapretScreen({super.key});

  @override
  State<ZapretScreen> createState() => _ZapretScreenState();
}

class _ZapretScreenState extends State<ZapretScreen> with SingleTickerProviderStateMixin {
  final _zapret = ZapretService.instance;
  bool _busy = false;
  bool _showLog = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _zapret.addListener(_onChange);
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

  Future<void> _toggle() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final settings = context.read<SettingsProvider>();
    if (_zapret.isRunning) {
      await _zapret.stop();
    } else {
      final list = _zapret.strategies();
      final chosen = list.where((s) => s.id == settings.settings.zapretStrategy).firstOrNull ?? list.firstOrNull;
      if (chosen != null) {
        _zapret.gameFilter = settings.settings.zapretGameFilter;
        await _zapret.start(chosen);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final supported = _zapret.isSupported;
    final running = _zapret.isRunning;
    final strategies = supported ? _zapret.strategies() : const <ZapretStrategy>[];
    final selectedId = strategies.any((e) => e.id == settings.settings.zapretStrategy)
        ? settings.settings.zapretStrategy
        : (strategies.firstOrNull?.id ?? '');

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 100),
        children: [
          Row(
            children: [
              Expanded(child: Text(s.t('zapret'), style: AppTextStyles.title)),
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
                    onTap: _toggle,
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
                  ZapretService.instance.strategies().where((e) => e.id == _zapret.runningStrategyId).firstOrNull?.title ?? '',
                  style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary),
                ),
              ),
            ],
            if (_zapret.lastError != null) ...[
              const SizedBox(height: 14),
              _Notice(icon: Icons.error_outline_rounded, text: _friendly(s, _zapret.lastError!), error: true),
            ],
            const SizedBox(height: 22),
            SectionCard(
              title: s.t('zapretStrategy'),
              icon: Icons.tune_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(s.t('zapretStrategyHint'), style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final st in strategies)
                        _StrategyChip(
                          label: st.title,
                          selected: st.id == selectedId,
                          active: running && st.id == _zapret.runningStrategyId,
                          onTap: () async {
                            await settings.update((v) => v.zapretStrategy = st.id);
                            if (_zapret.isRunning) {
                              _zapret.gameFilter = settings.settings.zapretGameFilter;
                              await _zapret.start(st);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
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
                      if (_zapret.isRunning) await _toggle().then((_) => _toggle());
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

  String _friendly(S s, String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('windivert') || lower.contains('driver') || lower.contains('access is denied') || lower.contains('1275')) {
      return s.t('zapretNeedAdmin');
    }
    return raw;
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({required this.label, required this.selected, required this.active, required this.onTap});
  final String label;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = active ? p.success : p.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color.withValues(alpha: 0.6) : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Container(width: 7, height: 7, decoration: BoxDecoration(color: p.success, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Text(label, style: AppTextStyles.bodyRegular.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? color : p.text)),
          ],
        ),
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
