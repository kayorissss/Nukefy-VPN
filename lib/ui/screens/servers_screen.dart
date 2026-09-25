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
    final subscriptions = servers.orderedSubscriptions;
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: servers.setQuery,
                            decoration: InputDecoration(
                              hintText: s.t('search'),
                              prefixIcon: const Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Ввести вручную, импорт из файла и проверка пинга
                        // живут в этом меню, а не на виду.
                        PopupMenuButton<String>(
                          tooltip: s.t('actions'),
                          icon: const Icon(Icons.more_vert_rounded),
                          color: Theme.of(context).cardColor,
                          onSelected: (value) => _menuAction(context, value),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'manual',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.edit_rounded, color: AppColors.cyan),
                                title: Text(s.t('enterManually')),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'file',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.folder_open_rounded, color: AppColors.cyan),
                                title: Text(s.t('importFile')),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'ping',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.network_check_rounded, color: AppColors.cyan),
                                title: Text(s.t('checkPing')),
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
                              if (text != null && context.mounted) await ImportActions.handleText(context, text);
                            },
                          ),
                        ),
                      ],
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
              for (var i = 0; i < subscriptions.length; i++)
                SliverToBoxAdapter(
                  child: _SubscriptionBlock(
                    subscription: subscriptions[i],
                    servers: visible.where((e) => e.subscriptionId == subscriptions[i].id).toList(),
                    antiblock: settings.settings.antiblock,
                    index: i + 1,
                    canMoveUp: i > 0,
                    canMoveDown: i < subscriptions.length - 1,
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

  Future<void> _menuAction(BuildContext context, String value) async {
    switch (value) {
      case 'manual':
        await ImportActions.manual(context);
      case 'file':
        await ImportActions.fromFile(context);
      case 'ping':
        await context.read<ServersProvider>().pingAll();
    }
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

/// One of the two large actions at the top of the Servers tab.
class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.cyan, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
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
    required this.index,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final SubscriptionModel subscription;
  final List<ServerModel> servers;
  final bool antiblock;
  final int index;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final provider = context.watch<ServersProvider>();
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
          // Долгое нажатие открывает настройки подписки.
          child: GestureDetector(
            onLongPress: () => _editSubscription(context, subscription),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Row(
                children: [
                  _NumberBadge(index: index),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subscription.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _SubscriptionPing(
                    pingMs: provider.subscriptionPing(subscription.id),
                    busy: provider.subscriptionPinging(subscription.id),
                    onTap: () => provider.pingSubscription(subscription.id),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: s.t('refresh'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
                    onPressed: () => provider.refreshSubscription(subscription.id),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.t('updated')}: ${subscription.lastUpdated == null ? '—' : FormatUtils.timeAgo(subscription.lastUpdated!, ru: s.code == 'ru')} · ${s.t('serversCount')}: ${servers.length}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySecondary,
                    ),
                    if (subscription.lastError != null)
                      Text(
                        subscription.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                      ),
                    Row(
                      children: [
                        _MoveButton(
                          icon: Icons.arrow_upward_rounded,
                          label: s.t('moveUp'),
                          enabled: canMoveUp,
                          onPressed: () => provider.moveSubscription(subscription.id, -1),
                        ),
                        const SizedBox(width: 4),
                        _MoveButton(
                          icon: Icons.arrow_downward_rounded,
                          label: s.t('moveDown'),
                          enabled: canMoveDown,
                          onPressed: () => provider.moveSubscription(subscription.id, 1),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: s.t('actions'),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.more_horiz_rounded),
                          onPressed: () => _subscriptionMenu(context, subscription),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              children: [
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
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$index',
        style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan, fontSize: 12),
      ),
    );
  }
}

/// Ping of the best server in the subscription; tapping re-pings them all.
class _SubscriptionPing extends StatelessWidget {
  const _SubscriptionPing({
    required this.pingMs,
    required this.busy,
    required this.onTap,
  });

  final int? pingMs;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.pingColor(pingMs);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: busy
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                pingMs == null ? '—' : pingMs! < 0 ? '✕' : '${pingMs}ms',
                style: AppTextStyles.monoValue.copyWith(color: color, fontSize: 12),
              ),
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16, color: AppColors.cyan),
      label: Text(
        label,
        style: AppTextStyles.bodySecondary.copyWith(color: AppColors.cyan),
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
