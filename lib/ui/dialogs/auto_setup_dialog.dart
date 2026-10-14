import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/server_model.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

Future<void> showAutoSetupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AutoSetupDialog(),
  );
}

enum _StepState { pending, running, done, skipped, error }

class _Step {
  _Step(this.title);
  final String title;
  _StepState state = _StepState.pending;
  String? note;
}

/// One-tap setup: downloads the missing cores, checks every server with a
/// real TCP ping and selects the fastest working one. Nothing is faked —
/// each step reports what actually happened.
class _AutoSetupDialog extends StatefulWidget {
  const _AutoSetupDialog();

  @override
  State<_AutoSetupDialog> createState() => _AutoSetupDialogState();
}

class _AutoSetupDialogState extends State<_AutoSetupDialog> {
  late final List<_Step> _steps;
  bool _running = true;
  ServerModel? _best;
  String? _fatal;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>().strings;
    _steps = [
      _Step(s.t('stepCore')),
      _Step(s.t('stepXray')),
      _Step(s.t('stepPing')),
      _Step(s.t('stepPick')),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final vpn = context.read<VpnProvider>();
    final servers = context.read<ServersProvider>();
    final settings = context.read<SettingsProvider>();
    final s = settings.strings;
    try {
      // 1. sing-box core.
      _set(0, _StepState.running);
      await vpn.refreshCore();
      if (vpn.core?.available ?? false) {
        _set(0, _StepState.done, note: vpn.core?.version);
      } else {
        await vpn.downloadCore((_) {});
        _set(0, _StepState.done, note: vpn.core?.version);
      }

      // 2. Xray core, only when an XHTTP server actually needs it.
      _set(1, _StepState.running);
      final needsXray = servers.servers.any((e) => e.isXhttp);
      if (!needsXray) {
        _set(1, _StepState.skipped, note: 'XHTTP: 0');
      } else if (vpn.core?.xray ?? false) {
        _set(1, _StepState.done);
      } else {
        await vpn.downloadXray((_) {});
        _set(1, _StepState.done);
      }

      // 3. Real ping of every server.
      _set(2, _StepState.running);
      if (servers.servers.isEmpty) {
        _set(2, _StepState.skipped, note: s.t('autoSetupNoServers'));
        _set(3, _StepState.skipped);
        setState(() => _running = false);
        return;
      }
      await servers.pingAll();
      final online = servers.servers.where((e) => e.isAvailable).length;
      _set(2, _StepState.done, note: '$online / ${servers.servers.length}');

      // 4. Fastest reachable server wins (sing-box ones preferred: they
      // support TUN, Xray ones are proxy-only).
      _set(3, _StepState.running);
      final candidates = servers.servers.where((e) => e.isAvailable).toList()
        ..sort((a, b) {
          if (a.isXhttp != b.isXhttp) return a.isXhttp ? 1 : -1;
          return (a.pingMs ?? 1 << 30).compareTo(b.pingMs ?? 1 << 30);
        });
      if (candidates.isEmpty) {
        _set(3, _StepState.error, note: s.t('unavailable'));
      } else {
        _best = candidates.first;
        await settings.update((value) => value.selectedServerId = _best!.id);
        vpn.activeServerId = _best!.id;
        _set(3, _StepState.done, note: '${_best!.name} · ${_best!.pingMs} ${s.t('msUnit')}');
      }
    } catch (error) {
      _fatal = '$error';
      for (final step in _steps) {
        if (step.state == _StepState.running) step.state = _StepState.error;
      }
    }
    if (mounted) setState(() => _running = false);
  }

  void _set(int index, _StepState state, {String? note}) {
    if (!mounted) return;
    setState(() {
      _steps[index].state = state;
      if (note != null) _steps[index].note = note;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return AlertDialog(
      title: Text(s.t('autoSetup')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('autoSetupBody'), style: AppTextStyles.bodySecondary),
            const SizedBox(height: 14),
            for (final step in _steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepIcon(state: step.state),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title, style: AppTextStyles.bodyRegular),
                          if (step.note != null)
                            Text(
                              step.note!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySecondary,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_fatal != null)
              Text(_fatal!, style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error)),
            if (!_running && _best != null)
              Text(
                '${s.t('bestServer')}: ${_best!.name}',
                style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(s.t('close')),
        ),
        if (!_running && _best != null)
          FilledButton(
            onPressed: () async {
              final vpn = context.read<VpnProvider>();
              final best = _best!;
              Navigator.pop(context);
              context.read<NavProvider>().goHome();
              await vpn.connect(best);
            },
            child: Text(s.t('connect')),
          ),
        if (!_running && _best == null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<NavProvider>().goServers();
            },
            child: Text(s.t('openServers')),
          ),
      ],
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _StepState.running => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _StepState.done =>
        const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
      _StepState.error =>
        const Icon(Icons.error_rounded, size: 20, color: AppColors.error),
      _StepState.skipped =>
        const Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.textSecondary),
      _StepState.pending =>
        const Icon(Icons.circle_outlined, size: 20, color: AppColors.textSecondary),
    };
  }
}
