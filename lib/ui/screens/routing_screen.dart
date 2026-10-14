import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';

/// Routing modes plus the custom "white list": domains/IPs with an action.
/// The list is laid out as wrapping cards so long values never overflow.
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            title: s.t('routing'),
            child: Column(
              children: [
                for (final item in RoutingMode.values)
                  RadioListTile<RoutingMode>(
                    value: item,
                    groupValue: mode,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_label(s, item), style: AppTextStyles.bodyRegular),
                    subtitle: Text(_desc(s, item), style: AppTextStyles.bodySecondary),
                    onChanged: (next) {
                      if (next != null) {
                        settings.update((value) => value.routingMode = next);
                      }
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('ads'), style: AppTextStyles.bodyRegular),
                  value: settings.settings.blockAds,
                  onChanged: (next) => settings.update((value) => value.blockAds = next),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(s.t('geosite'), style: AppTextStyles.bodySecondary),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          SectionCard(
            title: s.t('whitelistTitle'),
            trailing: IconButton(
              tooltip: s.t('addRule'),
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _addRule(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('whitelistHint'), style: AppTextStyles.bodySecondary),
                const SizedBox(height: 10),
                if (settings.settings.rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(s.t('rulesEmpty'), style: AppTextStyles.bodySecondary),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final rule in settings.settings.rules)
                        _RuleChip(rule: rule),
                    ],
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _addRule(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(s.t('addRule')),
                  ),
                ),
                const SizedBox(height: 6),
              ],
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

  Future<void> _addRule(BuildContext context) async {
    final s = context.read<SettingsProvider>().strings;
    final value = TextEditingController();
    var kind = 'domain_suffix';
    var action = 'proxy';
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.t('addRule')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: value,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: s.t('domain'),
                    errorText: error,
                  ),
                  style: AppTextStyles.monoValue,
                ),
                const SizedBox(height: 10),
                DropdownButton<String>(
                  value: kind,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: 'domain_suffix', child: Text(s.t('domain'))),
                    const DropdownMenuItem(value: 'ip_cidr', child: Text('IP CIDR')),
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: () {
                final text = value.text.trim();
                if (text.isEmpty || text.contains(' ')) {
                  setState(() => error = s.t('domain'));
                  return;
                }
                if (kind == 'ip_cidr' && !text.contains('/')) {
                  setState(() => error = 'IP CIDR');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(s.t('add')),
            ),
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

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.rule});

  final RoutingRule rule;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final s = settings.strings;
    final actionLabel = switch (rule.action) {
      'direct' => s.t('direct'),
      'block' => s.t('block'),
      _ => s.t('proxy'),
    };
    final actionColor = switch (rule.action) {
      'direct' => AppColors.textSecondary,
      'block' => AppColors.error,
      _ => AppColors.success,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: rule.value));
                if (context.mounted) showNukefySnack(context, s.t('copied'));
              },
              child: Text(
                rule.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.monoValue.copyWith(fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              actionLabel,
              style: AppTextStyles.bodySecondary.copyWith(color: actionColor, fontSize: 11),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 17),
            onPressed: () {
              settings.update((value) {
                value.rules =
                    value.rules.where((item) => item.id != rule.id).toList();
              });
            },
          ),
        ],
      ),
    );
  }
}
