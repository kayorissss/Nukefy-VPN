import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class PerAppScreen extends StatefulWidget {
  const PerAppScreen({super.key});

  @override
  State<PerAppScreen> createState() => _PerAppScreenState();
}

class _PerAppScreenState extends State<PerAppScreen> {
  List<InstalledApp> _apps = const [];
  bool _loading = true;

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
    final mode = settings.settings.perAppMode;
    final selected = settings.settings.perAppPackages.toSet();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('perApp'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.palette.accent.withValues(alpha: 0.25)),
              ),
              child: Text(
                switch (mode) {
                  PerAppMode.off => s.t('perAppExplainOff'),
                  PerAppMode.include => s.t('perAppExplainInclude'),
                  PerAppMode.exclude => s.t('perAppExplainExclude'),
                },
                style: AppTextStyles.bodySecondary.copyWith(color: context.palette.text),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<PerAppMode>(
              segments: [
                ButtonSegment(value: PerAppMode.off, label: Text(s.t('perAppOff'))),
                ButtonSegment(value: PerAppMode.include, label: Text(s.t('perAppInclude'))),
                ButtonSegment(value: PerAppMode.exclude, label: Text(s.t('perAppExclude'))),
              ],
              selected: {mode},
              onSelectionChanged: (next) => settings.update((value) => value.perAppMode = next.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _apps.length,
                    itemBuilder: (context, index) {
                      final app = _apps[index];
                      return CheckboxListTile(
                        value: selected.contains(app.packageName),
                        title: Text(app.label, style: AppTextStyles.bodyRegular),
                        subtitle: Text(app.packageName, style: AppTextStyles.monoValue),
                        onChanged: mode == PerAppMode.off
                            ? null
                            : (checked) {
                                final next = [...settings.settings.perAppPackages];
                                if (checked == true) {
                                  next.add(app.packageName);
                                } else {
                                  next.remove(app.packageName);
                                }
                                settings.update((value) => value.perAppPackages = next.toSet().toList());
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
