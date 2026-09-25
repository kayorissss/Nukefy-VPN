import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_background.dart';

/// Per-app routing: pick which apps bypass the VPN (or are the only ones
/// tunnelled). Search on top, app icons, one-tap toggles.
class PerAppScreen extends StatefulWidget {
  const PerAppScreen({super.key});

  @override
  State<PerAppScreen> createState() => _PerAppScreenState();
}

class _PerAppScreenState extends State<PerAppScreen> {
  List<InstalledApp> _apps = const [];
  bool _loading = true;
  bool _showSystem = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await VpnPlatform().listApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final p = context.palette;
    final mode = settings.settings.perAppMode;
    final selected = settings.settings.perAppPackages.toSet();
    final q = _query.trim().toLowerCase();
    final visible = _apps.where((app) {
      if (!_showSystem && app.system && !selected.contains(app.packageName)) return false;
      if (q.isEmpty) return true;
      return app.label.toLowerCase().contains(q) || app.packageName.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final sa = selected.contains(a.packageName), sb = selected.contains(b.packageName);
        if (sa != sb) return sa ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    final off = mode == PerAppMode.off;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(s.t('perApp')),
        actions: [
          IconButton(
            tooltip: s.t('showSystemApps'),
            onPressed: () => setState(() => _showSystem = !_showSystem),
            icon: Icon(
              _showSystem ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              color: _showSystem ? p.accent : p.textSecondary,
            ),
          ),
        ],
      ),
      body: NukefyBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ModeSwitch(
                      value: mode,
                      onChanged: (next) => settings.update((v) => v.perAppMode = next),
                      labels: {
                        PerAppMode.off: s.t('perAppOff'),
                        PerAppMode.exclude: s.t('perAppExcludeShort'),
                        PerAppMode.include: s.t('perAppIncludeShort'),
                      },
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        switch (mode) {
                          PerAppMode.off => s.t('perAppOffHint'),
                          PerAppMode.exclude => s.t('perAppExcludeHint'),
                          PerAppMode.include => s.t('perAppIncludeHint'),
                        },
                        key: ValueKey(mode),
                        style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: s.t('searchApps'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: off ? 0.4 : 1,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                          itemCount: visible.length,
                          itemExtent: 64,
                          itemBuilder: (context, index) {
                            final app = visible[index];
                            final on = selected.contains(app.packageName);
                            return _AppRow(
                              app: app,
                              on: on,
                              enabled: !off,
                              onTap: () {
                                final next = {...settings.settings.perAppPackages};
                                on ? next.remove(app.packageName) : next.add(app.packageName);
                                settings.update((v) => v.perAppPackages = next.toList());
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control in the app's own style: pill track, sliding thumb.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.value, required this.onChanged, required this.labels});

  final PerAppMode value;
  final ValueChanged<PerAppMode> onChanged;
  final Map<PerAppMode, String> labels;

  static const _order = [PerAppMode.off, PerAppMode.exclude, PerAppMode.include];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = _order.indexOf(value);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: p.isDark ? 0.9 : 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / _order.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.accent.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in _order)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(mode),
                        child: Center(
                          child: Text(
                            labels[mode]!.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.tab.copyWith(
                              fontSize: 10,
                              color: mode == value ? p.accent : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.on, required this.enabled, required this.onTap});

  final InstalledApp app;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? p.accent.withValues(alpha: 0.10) : p.card.withValues(alpha: p.isDark ? 0.85 : 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? p.accent.withValues(alpha: 0.45) : p.border),
          ),
          child: Row(
            children: [
              _AppIcon(package: app.packageName, label: app.label),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyRegular.copyWith(color: p.text, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  on ? Icons.check_circle_rounded : Icons.circle_outlined,
                  key: ValueKey(on),
                  color: on ? p.accent : p.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.package, required this.label});
  final String package;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 40,
        height: 40,
        child: FutureBuilder<Uint8List?>(
          future: VpnPlatform().appIcon(package),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(bytes, gaplessPlayback: true, filterQuality: FilterQuality.medium);
            }
            return Container(
              color: p.surface,
              alignment: Alignment.center,
              child: Text(
                label.isEmpty ? '?' : label.characters.first.toUpperCase(),
                style: AppTextStyles.headline.copyWith(color: p.accent, fontSize: 15),
              ),
            );
          },
        ),
      ),
    );
  }
}
