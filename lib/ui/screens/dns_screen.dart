import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';
import '../widgets/section_card.dart';

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});

  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  late final TextEditingController _proxy;
  late final TextEditingController _direct;
  bool _flushing = false;
  String? _flushResult;

  static const _presets = <String, ({String labelKey, String proxy, String direct, IconData icon})>{
    'dhcp': (labelKey: 'dnsDhcp', proxy: 'system', direct: 'system', icon: Icons.router_outlined),
    'cloudflare': (labelKey: 'dnsCloudflare', proxy: 'https://cloudflare-dns.com/dns-query', direct: '1.1.1.1', icon: Icons.shield_outlined),
    'google': (labelKey: 'dnsGoogle', proxy: 'https://dns.google/dns-query', direct: '8.8.8.8', icon: Icons.search_rounded),
    'dnsSb': (labelKey: 'dnsDnsSb', proxy: 'https://doh.dns.sb/dns-query', direct: '185.222.222.222', icon: Icons.public_rounded),
    'quad9': (labelKey: 'dnsQuad9', proxy: 'https://dns.quad9.net/dns-query', direct: '9.9.9.9', icon: Icons.security_rounded),
    'adguard': (labelKey: 'dnsAdGuard', proxy: 'https://dns.adguard-dns.com/dns-query', direct: '94.140.14.14', icon: Icons.remove_circle_outline_rounded),
    'opendns': (labelKey: 'dnsOpenDns', proxy: 'https://doh.opendns.com/dns-query', direct: '208.67.222.222', icon: Icons.dns_rounded),
    'dnsdoh': (labelKey: 'dnsDohArt', proxy: 'https://dnsdoh.art/dns-query', direct: 'dnsdoh.art', icon: Icons.auto_awesome_rounded),
    'custom': (labelKey: 'dnsCustom', proxy: '', direct: '', icon: Icons.tune_rounded),
  };

  @override
  void initState() {
    super.initState();
    final value = context.read<SettingsProvider>().settings;
    _proxy = TextEditingController(text: value.proxyDns);
    _direct = TextEditingController(text: value.directDns);
  }

  @override
  void dispose() {
    _proxy.dispose();
    _direct.dispose();
    super.dispose();
  }

  Future<void> _select(String id) async {
    final preset = _presets[id];
    if (preset == null) return;
    final settings = context.read<SettingsProvider>();
    await settings.update((value) {
      value.dnsPreset = id;
      if (id != 'custom') {
        value.proxyDns = preset.proxy;
        value.directDns = preset.direct;
      }
    });
    if (!mounted) return;
    _proxy.text = settings.settings.proxyDns;
    _direct.text = settings.settings.directDns;
    setState(() {});
  }

  Future<void> _saveCustom() async {
    final proxy = _proxy.text.trim();
    final direct = _direct.text.trim();
    await context.read<SettingsProvider>().update((value) {
      value.dnsPreset = 'custom';
      value.proxyDns = proxy;
      value.directDns = direct;
    });
    if (mounted) showNukefySnack(context, context.read<SettingsProvider>().strings.t('saved'));
  }

  Future<void> _flush() async {
    if (_flushing) return;
    setState(() {
      _flushing = true;
      _flushResult = null;
    });
    try {
      final result = await VpnPlatform().flushDnsCache();
      if (mounted) setState(() => _flushResult = result.isEmpty ? context.read<SettingsProvider>().strings.t('dnsCacheResetDone') : result);
    } catch (error) {
      if (mounted) setState(() => _flushResult = '$error');
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  Future<void> _reset() async {
    final s = context.read<SettingsProvider>().strings;
    final ok = await confirmDialog(
      context,
      title: s.t('dnsResetTitle'),
      body: s.t('dnsResetBody'),
      confirm: s.t('reset'),
      cancel: s.t('cancel'),
    );
    if (!ok || !mounted) return;
    await _select('cloudflare');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final value = settings.settings;
    final s = settings.strings;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final selected = _presets.containsKey(value.dnsPreset) ? value.dnsPreset : 'custom';
    return SafeArea(
      bottom: false,
      child: ResponsiveSections(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          SectionCard(
            title: s.t('dnsTitle'),
            icon: Icons.dns_rounded,
            trailing: IconButton(onPressed: _reset, tooltip: s.t('reset'), icon: const Icon(Icons.restore_rounded)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('dnsHint'), style: context.palette.secondaryStyle),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final entry in _presets.entries)
                        _DnsPreset(
                          width: constraints.maxWidth < 500 ? (constraints.maxWidth - 10) / 2 : 164,
                          label: s.t(entry.value.labelKey),
                          icon: entry.value.icon,
                          selected: selected == entry.key,
                          onTap: () => _select(entry.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected == 'custom')
            SectionCard(
              title: s.t('dnsCustom'),
              icon: Icons.tune_rounded,
              child: Column(
                children: [
                  TextField(controller: _proxy, decoration: InputDecoration(labelText: s.t('proxyDns'), helperText: s.t('proxyDnsHint'))),
                  const SizedBox(height: 12),
                  TextField(controller: _direct, decoration: InputDecoration(labelText: s.t('directDns'), helperText: s.t('directDnsHint'))),
                  const SizedBox(height: 12),
                  Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(onPressed: _saveCustom, icon: const Icon(Icons.save_outlined), label: Text(s.t('save')))),
                ],
              ),
            ),
          SectionCard(
            title: s.t('dnsCache'),
            icon: Icons.cleaning_services_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('dnsCacheHint'), style: context.palette.secondaryStyle),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _flushing ? null : _flush, icon: _flushing ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded), label: Text(s.t('dnsResetCache'))),
                if (_flushResult != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_flushResult!, style: AppTextStyles.monoValue.copyWith(fontSize: 12)),
                  Align(alignment: AlignmentDirectional.centerEnd, child: IconButton(onPressed: () => Clipboard.setData(ClipboardData(text: _flushResult!)), tooltip: s.t('copy'), icon: const Icon(Icons.copy_rounded))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DnsPreset extends StatelessWidget {
  const _DnsPreset({required this.width, required this.label, required this.icon, required this.selected, required this.onTap});

  final double width;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: .14) : p.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: selected ? p.accent.withValues(alpha: .65) : p.border, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? p.accent : p.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySecondary.copyWith(color: selected ? p.text : p.textSecondary, fontWeight: FontWeight.w700))),
              if (selected) Icon(Icons.check_rounded, size: 17, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}
