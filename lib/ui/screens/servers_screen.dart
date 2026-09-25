import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/server_model.dart';
import '../../core/models/subscription_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/share_link_builder.dart';
import '../dialogs/speed_test_dialog.dart';
import '../import_actions.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/ping_badge.dart';
import 'qr_scanner_screen.dart';
import 'server_edit_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<ServersProvider>();
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final visible = _ordered(servers, settings.settings.antiblock && settings.settings.preferBridge);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await servers.refreshAll();
          await servers.pingAll();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('servers'), style: AppTextStyles.title),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: servers.setQuery,
                      decoration: InputDecoration(
                        hintText: s.t('search'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Action(icon: Icons.content_paste_rounded, label: s.t('paste'), onTap: () => ImportActions.paste(context)),
                        _Action(icon: Icons.edit_rounded, label: s.t('manual'), onTap: () => ImportActions.manual(context)),
                        _Action(icon: Icons.qr_code_scanner_rounded, label: s.t('qr'), onTap: () async {
                          final text = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
                          if (text != null && context.mounted) await ImportActions.handleText(context, text);
                        }),
                        _Action(icon: Icons.folder_open_rounded, label: s.t('importFile'), onTap: () => ImportActions.fromFile(context)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: Text(servers.pinging ? s.t('pinging') : s.t('checkPing')),
                          selected: servers.pinging,
                          onSelected: (_) => servers.pingAll(),
                        ),
                        FilterChip(
                          label: Text(s.t('sortPing')),
                          selected: servers.sort == 'ping',
                          onSelected: (_) => servers.setSort(servers.sort == 'ping' ? 'manual' : 'ping'),
                        ),
                        FilterChip(
                          label: Text(s.t('onlyOnline')),
                          selected: servers.onlyAvailable,
                          onSelected: (v) => servers.setFilters(availableOnly: v),
                        ),
                        PopupMenuButton<String>(
                          child: Chip(label: Text(servers.protocolFilter ?? s.t('protocol'))),
                          onSelected: (value) => servers.setFilters(
                            protocol: value == '*' ? null : value,
                            clearProtocol: value == '*',
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: '*', child: Text(s.t('all'))),
                            for (final protocol in servers.protocols)
                              PopupMenuItem(value: protocol, child: Text(FormatUtils.protocolLabel(protocol))),
                          ],
                        ),
                        PopupMenuButton<String>(
                          child: Chip(label: Text(servers.countryFilter ?? s.t('country'))),
                          onSelected: (value) => servers.setFilters(
                            country: value == '*' ? null : value,
                            clearCountry: value == '*',
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: '*', child: Text(s.t('all'))),
                            for (final country in servers.countries)
                              PopupMenuItem(value: country, child: Text(country)),
                          ],
                        ),
                        FilterChip(
                          label: Text(s.t('antiblock')),
                          selected: servers.onlyAntiblock,
                          onSelected: (v) => servers.setFilters(antiblockOnly: v),
                        ),
                        if (servers.protocolFilter != null)
                          FilterChip(
                            label: Text(FormatUtils.protocolLabel(servers.protocolFilter!)),
                            selected: true,
                            onSelected: (_) => servers.setFilters(clearProtocol: true),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (servers.subscriptions.isEmpty && servers.servers.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(s.t('emptyServers'), style: AppTextStyles.headline),
                        const SizedBox(height: 6),
                        Text(s.t('emptyHint'), textAlign: TextAlign.center, style: AppTextStyles.bodySecondary),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              for (final sub in servers.orderedSubscriptions)
                SliverToBoxAdapter(
                  child: _SubscriptionBlock(
                    subscription: sub,
                    servers: visible.where((e) => e.subscriptionId == sub.id).toList(),
                    antiblock: settings.settings.antiblock,
                  ),
                ),
              SliverToBoxAdapter(
                child: _ManualBlock(
                  servers: visible.where((e) => e.subscriptionId == null).toList(),
                  antiblock: settings.settings.antiblock,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }

  List<ServerModel> _ordered(ServersProvider provider, bool bridgesFirst) {
    final list = provider.filtered;
    if (!bridgesFirst) return list;
    final bridges = list.where((s) => s.isBridge).toList();
    final rest = list.where((s) => !s.isBridge).toList();
    final timeouts = rest.where((s) => s.isTimeout).toList();
    final online = rest.where((s) => !s.isTimeout).toList();
    return [...bridges, ...online, ...timeouts];
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.cyan),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodySecondary.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionBlock extends StatelessWidget {
  const _SubscriptionBlock({
    required this.subscription,
    required this.servers,
    required this.antiblock,
  });

  final SubscriptionModel subscription;
  final List<ServerModel> servers;
  final bool antiblock;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(subscription.name, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${subscription.url}\n${s.t('updated')}: ${subscription.lastUpdated == null ? '—' : FormatUtils.timeAgo(subscription.lastUpdated!, ru: s.code == 'ru')} · ${s.t('serversCount')}: ${servers.length}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySecondary,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => _subscriptionMenu(context, subscription),
            ),
            children: [
              if (subscription.lastError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(subscription.lastError!, style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error)),
                ),
              for (final server in servers)
                ServerTile(server: server, antiblock: antiblock)
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideX(begin: 0.04),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualBlock extends StatelessWidget {
  const _ManualBlock({required this.servers, required this.antiblock});
  final List<ServerModel> servers;
  final bool antiblock;

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) return const SizedBox.shrink();
    final s = context.watch<SettingsProvider>().strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('manualServers').toUpperCase(), style: AppTextStyles.section),
          const SizedBox(height: 8),
          for (final server in servers) ServerTile(server: server, antiblock: antiblock),
        ],
      ),
    );
  }
}

class ServerTile extends StatelessWidget {
  const ServerTile({super.key, required this.server, required this.antiblock});

  final ServerModel server;
  final bool antiblock;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final selected = context.watch<VpnProvider>().activeServerId == server.id;
    final dim = server.isTimeout;
    final label = server.isBridge
        ? s.t('bridgeWorks')
        : (antiblock && dim ? s.t('jammer') : null);
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: ListTile(
        onTap: () => _actions(context, server),
        onLongPress: () => _actions(context, server),
        leading: Text(GeoUtils.flagEmoji(server.countryCode), style: const TextStyle(fontSize: 22)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyRegular.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (server.isNew)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s.t('newBadge'), style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan, fontSize: 10)),
              ),
            if (server.isBridge)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('🛡️', style: TextStyle(fontSize: 14)),
              ),
          ],
        ),
        subtitle: Text(
          [
            FormatUtils.protocolLabel(server.protocol),
            if (label != null) label,
          ].join(' · '),
          style: AppTextStyles.bodySecondary,
        ),
        trailing: PingBadge(pingMs: server.pingMs, compact: true),
      ),
    );
  }
}

Future<void> _actions(BuildContext context, ServerModel server) async {
  final s = context.read<SettingsProvider>().strings;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.play_arrow_rounded, color: AppColors.cyan), title: Text(s.t('connect')), onTap: () => Navigator.pop(context, 'connect')),
          ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(server.isPinned ? s.t('unpin') : s.t('pin')), onTap: () => Navigator.pop(context, 'pin')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: Text(s.t('edit')), onTap: () => Navigator.pop(context, 'edit')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(s.t('copyLink')), onTap: () => Navigator.pop(context, 'copy')),
          ListTile(leading: const Icon(Icons.speed_rounded), title: Text(s.t('speedTest')), onTap: () => Navigator.pop(context, 'speed')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error), title: Text(s.t('delete')), onTap: () => Navigator.pop(context, 'delete')),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final servers = context.read<ServersProvider>();
  switch (action) {
    case 'connect':
      await context.read<VpnProvider>().connect(server);
    case 'pin':
      await servers.togglePin(server.id);
    case 'edit':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ServerEditScreen(serverId: server.id)));
    case 'copy':
      final link = ShareLinkBuilder.build(server);
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) showNukefySnack(context, s.t('copied'));
    case 'speed':
      await showSpeedTest(context, server);
    case 'delete':
      final ok = await confirmDialog(
        context,
        title: s.t('delete'),
        body: s.t('deleteServer'),
        confirm: s.t('delete'),
        cancel: s.t('cancel'),
      );
      if (ok) await servers.deleteServer(server.id);
  }
}

Future<void> _subscriptionMenu(BuildContext context, SubscriptionModel sub) async {
  final s = context.read<SettingsProvider>().strings;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.refresh_rounded), title: Text(s.t('refresh')), onTap: () => Navigator.pop(context, 'refresh')),
          ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(sub.isPinned ? s.t('unpin') : s.t('pin')), onTap: () => Navigator.pop(context, 'pin')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: Text(s.t('edit')), onTap: () => Navigator.pop(context, 'edit')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(s.t('copyLink')), onTap: () => Navigator.pop(context, 'copy')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error), title: Text(s.t('delete')), onTap: () => Navigator.pop(context, 'delete')),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final servers = context.read<ServersProvider>();
  switch (action) {
    case 'refresh':
      await servers.refreshSubscription(sub.id);
    case 'pin':
      await servers.updateSubscription(sub.id, pinned: !sub.isPinned);
    case 'edit':
      await _editSubscription(context, sub);
    case 'copy':
      await Clipboard.setData(ClipboardData(text: sub.url));
      await SharePlus.instance.share(ShareParams(text: sub.url));
      if (context.mounted) showNukefySnack(context, s.t('copied'));
    case 'delete':
      final ok = await confirmDialog(
        context,
        title: s.t('delete'),
        body: s.t('deleteSub'),
        confirm: s.t('delete'),
        cancel: s.t('cancel'),
      );
      if (ok) {
        final vpn = context.read<VpnProvider>();
        if (vpn.activeServer?.subscriptionId == sub.id && vpn.status == VpnStatus.connected) {
          await vpn.disconnect();
        }
        await servers.deleteSubscription(sub.id);
      }
  }
}

Future<void> _editSubscription(BuildContext context, SubscriptionModel sub) async {
  final s = context.read<SettingsProvider>().strings;
  final name = TextEditingController(text: sub.name);
  final url = TextEditingController(text: sub.url);
  final ua = TextEditingController(text: sub.userAgent ?? '');
  var interval = sub.autoUpdateInterval;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(s.t('edit')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
              const SizedBox(height: 8),
              TextField(controller: url, decoration: InputDecoration(labelText: s.t('url'))),
              const SizedBox(height: 8),
              TextField(controller: ua, decoration: InputDecoration(labelText: s.t('userAgent'))),
              const SizedBox(height: 8),
              DropdownButton<UpdateInterval>(
                value: interval,
                isExpanded: true,
                items: UpdateInterval.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(_intervalLabel(s, e))))
                    .toList(),
                onChanged: (value) => setState(() => interval = value ?? interval),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('save'))),
        ],
      ),
    ),
  );
  if (saved == true && context.mounted) {
    await context.read<ServersProvider>().updateSubscription(
          sub.id,
          name: name.text.trim(),
          url: url.text.trim(),
          interval: interval,
          userAgent: ua.text.trim(),
        );
  }
  name.dispose();
  url.dispose();
  ua.dispose();
}

String _intervalLabel(dynamic s, UpdateInterval interval) {
  return switch (interval) {
    UpdateInterval.manual => s.t('manualInterval'),
    UpdateInterval.min30 => s.t('min30'),
    UpdateInterval.hour1 => s.t('hour1'),
    UpdateInterval.hour6 => s.t('hour6'),
    UpdateInterval.hour12 => s.t('hour12'),
  };
}
