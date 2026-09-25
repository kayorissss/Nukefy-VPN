import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_text_styles.dart';

class RoutingScreen extends StatelessWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final mode = settings.settings.routingMode;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('routing'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('geosite'), style: AppTextStyles.bodySecondary),
          const SizedBox(height: 8),
          ...RoutingMode.values.map((item) {
            return RadioListTile<RoutingMode>(
              value: item,
              groupValue: mode,
              title: Text(_label(s, item), style: AppTextStyles.bodyRegular),
              subtitle: Text(_desc(s, item), style: AppTextStyles.bodySecondary),
              onChanged: (next) {
                if (next != null) settings.update((value) => value.routingMode = next);
              },
            );
          }),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('ads'), style: AppTextStyles.bodyRegular),
            value: settings.settings.blockAds,
            onChanged: (next) => settings.update((value) => value.blockAds = next),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(s.t('routingRules'), style: AppTextStyles.bodyRegular),
              const Spacer(),
              TextButton(onPressed: () => _addRule(context), child: Text(s.t('addRule'))),
            ],
          ),
          for (final rule in settings.settings.rules)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(rule.value, style: AppTextStyles.monoValue),
              subtitle: Text('${rule.kind} · ${_action(s, rule.action)}', style: AppTextStyles.bodySecondary),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  settings.update((value) {
                    value.rules = value.rules.where((item) => item.id != rule.id).toList();
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  String _label(dynamic s, RoutingMode mode) {
    return switch (mode) {
      RoutingMode.global => s.t('modeGlobal'),
      RoutingMode.blockedOnly => s.t('modeBlocked'),
      RoutingMode.bypassRu => s.t('modeBypass'),
      RoutingMode.custom => s.t('modeCustom'),
    };
  }

  String _desc(dynamic s, RoutingMode mode) {
    return switch (mode) {
      RoutingMode.global => s.t('modeGlobalDesc'),
      RoutingMode.blockedOnly => s.t('modeBlockedDesc'),
      RoutingMode.bypassRu => s.t('modeBypassDesc'),
      RoutingMode.custom => s.t('modeCustomDesc'),
    };
  }

  String _action(dynamic s, String action) {
    return switch (action) {
      'direct' => s.t('direct'),
      'block' => s.t('block'),
      _ => s.t('proxy'),
    };
  }

  Future<void> _addRule(BuildContext context) async {
    final s = context.read<SettingsProvider>().strings;
    final value = TextEditingController();
    var kind = 'domain_suffix';
    var action = 'proxy';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.t('addRule')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: value,
                decoration: InputDecoration(labelText: s.t('domain')),
                style: AppTextStyles.monoValue,
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: kind,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'domain_suffix', child: Text(s.t('domain'))),
                  DropdownMenuItem(value: 'ip_cidr', child: Text('IP CIDR')),
                ],
                onChanged: (next) => setState(() => kind = next ?? kind),
              ),
              DropdownButton<String>(
                value: action,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'proxy', child: Text(s.t('proxy'))),
                  DropdownMenuItem(value: 'direct', child: Text(s.t('direct'))),
                  DropdownMenuItem(value: 'block', child: Text(s.t('block'))),
                ],
                onChanged: (next) => setState(() => action = next ?? action),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('add'))),
          ],
        ),
      ),
    );
    final text = value.text.trim();
    value.dispose();
    if (saved != true || text.isEmpty || !context.mounted) return;
    await context.read<SettingsProvider>().update((settings) {
      settings.rules = [
        ...settings.rules,
        RoutingRule(id: const Uuid().v4(), value: text, kind: kind, action: action),
      ];
    });
  }
}
