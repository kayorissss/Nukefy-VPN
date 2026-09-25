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
    final subs = servers.orderedSubscriptions;
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
                    Row(
                      children: [
                        Expanded(child: Text(s.t('servers'), style: AppTextStyles.title)),
                        // «Ввести вручную», «Импорт из файла» и «Проверить пинг»
                        // live here, the two main actions stay on the surface.
                        PopupMenuButton<String>(
                          tooltip: s.t('actions'),
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (value) async {
                            if (value == 'manual') {
                              await ImportActions.manual(context);
                            } else if (value == 'file') {
                              await ImportActions.fromFile(context);
                            } else if (value == 'ping') {
                              await context.read<ServersProvider>().pingAll();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'manual',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_rounded, size: 18, color: AppColors.cyan),
                                  const SizedBox(width: 10),
                                  Text(s.t('enterManually')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'file',
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 18, color: AppColors.cyan),
                                  const SizedBox(width: 10),
                                  Text(s.t('importFile')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'ping',
                              child: Row(
                                children: [
                                  const Icon(Icons.network_ping_rounded, size: 18, color: AppColors.cyan),
                                  const SizedBox(width: 10),
                                  Text(s.t('checkPing')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BigAction(
                            icon: Icons.content_paste_rounded,
                            label: s.t('pasteClipboard'),
                            onTap: () => ImportActions.paste(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _BigAction(
                            icon: Icons.qr_code_scanner_rounded,
                            label: s.t('qr'),
                            onTap: () async {
                              final text = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                              );
                              if (text != null && context.mounted) {
                                await ImportActions.handleText(context, text);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
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
              for (var i = 0; i < subs.length; i++)
                SliverToBoxAdapter(
                  child: _SubscriptionBlock(
                    subscription: subs[i],
                    number: i + 1,
                    servers: visible.where((e) => e.subscriptionId == subs[i].id).toList(),
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

/// One of the two primary actions on the servers tab.
class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cyan.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.cyan),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subscription row: number, name, «Обновить» and a ping icon. The URL is
/// deliberately not shown — it used to eat the whole row.
class _SubscriptionBlock extends StatefulWidget {
  const _SubscriptionBlock({
    required this.subscription,
    required this.number,
    required this.servers,
    required this.antiblock,
  });

  final SubscriptionModel subscription;
  final int number;
  final List<ServerModel> servers;
  final bool antiblock;

  @override
  State<_SubscriptionBlock> createState() => _SubscriptionBlockState();
}

class _SubscriptionBlockState extends State<_SubscriptionBlock> {
  bool _open = true;
  bool _pinging = false;

  Future<void> _ping() async {
    if (_pinging) return;
    setState(() => _pinging = true);
    await context.read<ServersProvider>().pingSubscription(widget.subscription.id);
    if (mounted) setState(() => _pinging = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final provider = context.watch<ServersProvider>();
    final sub = widget.subscription;
    final updated = sub.lastUpdated == null
        ? '—'
        : FormatUtils.timeAgo(sub.lastUpdated!, ru: s.code == 'ru');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Text(
                      '${widget.number}.',
                      style: AppTextStyles.monoValue.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    // Long press opens the subscription settings.
                    Expanded(
                      child: GestureDetector(
                        onLongPress: () => _subscriptionMenu(context, sub),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sub.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s.t('serversCount')}: ${widget.servers.length} · ${s.t('updated')}: $updated',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton(
                        onPressed: provider.refreshing ? null : () => provider.refreshSubscription(sub.id),
                        child: provider.refreshing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(s.t('updateSub'), style: const TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('checkPing'),
                      onPressed: _pinging ? null : _ping,
                      icon: _pinging
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_ping_rounded, size: 20, color: AppColors.cyan),
                    ),
                    IconButton(
                      tooltip: s.t('actions'),
                      onPressed: () => setState(() => _open = !_open),
                      icon: Icon(
                        _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_open) ...[
              if (sub.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    sub.lastError!,
                    style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                  ),
                ),
              for (final server in widget.servers)
                ServerTile(server: server, antiblock: widget.antiblock)
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideX(begin: 0.04),
              const SizedBox(height: 8),
            ],
          ],
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
            ?label,
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

/// Long-press menu of a subscription row.
Future<void> _subscriptionMenu(BuildContext context, SubscriptionModel sub) async {
  final s = context.read<SettingsProvider>().strings;
  final servers = context.read<ServersProvider>();
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 18, color: AppColors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.t('subscriptionSettings'),
                    style: AppTextStyles.headline,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward_rounded),
            title: Text(s.t('moveUp')),
            enabled: servers.canMoveSubscriptionUp(sub.id),
            onTap: () => Navigator.pop(context, 'up'),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_downward_rounded),
            title: Text(s.t('moveDown')),
            enabled: servers.canMoveSubscriptionDown(sub.id),
            onTap: () => Navigator.pop(context, 'down'),
          ),
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
  switch (action) {
    case 'up':
      await servers.moveSubscription(sub.id, up: true);
    case 'down':
      await servers.moveSubscription(sub.id, up: false);
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
