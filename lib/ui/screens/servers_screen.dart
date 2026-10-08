import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/server_model.dart';
import '../../core/models/subscription_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/network_diagnostics.dart';
import '../../core/utils/share_link_builder.dart';
import '../dialogs/speed_test_dialog.dart';
import '../import_actions.dart';
import '../widgets/country_badge.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/ping_badge.dart';
import '../widgets/section_card.dart';
import '../widgets/responsive_sections.dart';
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          await servers.refreshAll();
          await servers.pingAll();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(s.t('servers'), style: AppTextStyles.title)),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 42,
                            child: TextField(
                              onChanged: servers.setQuery,
                              decoration: InputDecoration(
                                hintText: s.t('search'),
                                prefixIcon: const Icon(Icons.search_rounded),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
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
                                  Icon(Icons.edit_rounded, size: 18, color: context.palette.accent),
                                  const SizedBox(width: 10),
                                  Text(s.t('enterManually')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'file',
                              child: Row(
                                children: [
                                  Icon(Icons.folder_open_rounded, size: 18, color: context.palette.accent),
                                  const SizedBox(width: 10),
                                  Text(s.t('importFile')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'ping',
                              child: Row(
                                children: [
                                  Icon(Icons.speed_rounded, size: 18, color: context.palette.accent),
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
                            icon: Icons.edit_note_rounded,
                            label: s.t('enterManually'),
                            onTap: () => ImportActions.manual(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
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
                        Icon(Icons.cloud_off_rounded, size: 42, color: context.palette.textSecondary),
                        const SizedBox(height: 12),
                        Text(s.t('emptyServers'), style: AppTextStyles.headline),
                        const SizedBox(height: 6),
                        Text(s.t('emptyHint'), textAlign: TextAlign.center, style: context.palette.secondaryStyle),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              for (var i = 0; i < subs.length; i++)
                SliverToBoxAdapter(
                  child: _SubscriptionBlock(
                    key: ValueKey(subs[i].id),
                    subscription: subs[i],
                    initiallyOpen: i == _openIndex(subs, servers, settings.settings.selectedServerId),
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
              SliverToBoxAdapter(child: SizedBox(height: bottom + 100)),
            ],
          ],
        ),
      ),
    );
  }

  /// The subscription the user actually rides opens expanded; the rest stay
  /// folded so the page is not a wall of open lists.
  static int _openIndex(List<SubscriptionModel> subs, ServersProvider provider, String? selectedServerId) {
    final active = provider.byId(selectedServerId)?.subscriptionId;
    final index = subs.indexWhere((e) => e.id == active);
    if (index >= 0) return index;
    return subs.isEmpty ? -1 : 0;
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
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.accent.withValues(alpha: 0.18), p.accent2.withValues(alpha: 0.10)],
            ),
            border: Border.all(color: p.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: p.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(fontSize: 11.5, color: p.text),
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
    super.key,
    required this.subscription,
    required this.number,
    required this.servers,
    required this.antiblock,
    this.initiallyOpen = false,
  });

  final SubscriptionModel subscription;
  final int number;
  final List<ServerModel> servers;
  final bool antiblock;
  final bool initiallyOpen;

  @override
  State<_SubscriptionBlock> createState() => _SubscriptionBlockState();
}

class _SubscriptionBlockState extends State<_SubscriptionBlock> {
  late bool _open = widget.initiallyOpen;
  bool _pinging = false;

  static const _page = 40;
  int _shown = _page;

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
    final p = context.palette;
    final sub = widget.subscription;
    final shownServers = widget.servers.where((s) => !sub.hideNotices || !s.isInformational).toList();
    final updated = sub.lastUpdated == null
        ? '—'
        : FormatUtils.timeAgo(sub.lastUpdated!, ru: s.code == 'ru');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _open = !_open),
              onLongPress: () => _subscriptionMenu(context, sub),
              onSecondaryTap: () => _subscriptionMenu(context, sub),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${widget.number}', style: AppTextStyles.number.copyWith(color: p.accent, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
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
                              '${s.t('serversCount')}: ${shownServers.length} · ${s.t('updated')}: $updated',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.palette.secondaryStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: s.t('subscriptionSettings'), onPressed: () => _subscriptionMenu(context, sub),
                      icon: const Icon(Icons.settings_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: s.t('updateSub'),
                      onPressed: provider.refreshing ? null : () => provider.refreshSubscription(sub.id),
                      icon: provider.refreshing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.refresh_rounded, size: 21, color: p.accent),
                    ),
                    IconButton(
                      tooltip: s.t('checkPing'),
                      onPressed: _pinging ? null : _ping,
                      icon: _pinging
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.speed_rounded, size: 21, color: p.accent),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 220),
                      turns: _open ? 0 : -0.5,
                      child: Icon(Icons.expand_less_rounded, color: p.textSecondary),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_open ? const SizedBox(width: double.infinity) : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (sub.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    NetworkDiagnostics.textOrRaw(sub.lastError!, s.t),
                    style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                  ),
                ),
              // Big subscriptions (100+ servers) are rendered in pages so
              // opening a card never builds hundreds of tiles at once.
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${s.t('shownCount')}: ${shownServers.length.clamp(0, _shown)} / ${shownServers.length}', style: p.captionStyle),
                if (sub.receivedCount > 0) Text('${s.t('receivedCount')}: ${sub.receivedCount} · ${s.t('unparsedCount')}: ${sub.rejectedCount}', style: p.captionStyle),
                FilterChip(label: Text(s.t('hideInformation')), selected: sub.hideNotices, onSelected: (_) => provider.toggleNotices(sub)),
              ])),
              ResponsiveTiles(children: [for (final server in shownServers.take(_shown))
                RepaintBoundary(child: ServerTile(server: server, antiblock: widget.antiblock))]),
              if (shownServers.length > _shown)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _shown += _page),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text('${s.t('showMore')} (${shownServers.length - _shown})'),
                  ),
                ),
              const SizedBox(height: 8),
                ],
              ),
            ),
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
          Padding(padding: const EdgeInsets.only(left: 4), child: Text(s.t('manualServers').toUpperCase(), style: AppTextStyles.section.copyWith(color: context.palette.textSecondary))),
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
    final vpn = context.watch<VpnProvider>();
    final p = context.palette;
    final selected = vpn.activeServerId == server.id;
    final connected = selected && vpn.status == VpnStatus.connected;
    final dim = server.isTimeout;
    final label = server.isBridge
        ? s.t('bridgeWorks')
        : (antiblock && dim ? s.t('jammer') : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Tap connects straight away; long press opens the actions.
          onTap: server.isInformational ? null : () => _tapServer(context, server),
          onSecondaryTap: () => _openServerSettings(context, server),
          onLongPress: () => _actions(context, server),
          child: Opacity(
            opacity: dim ? 0.6 : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
              child: Row(
                children: [
                  CountryBadge(code: server.countryCode, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                server.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyRegular.copyWith(
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (server.isNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(s.t('newBadge'), style: AppTextStyles.tab.copyWith(color: p.accent, fontSize: 8.5)),
                              ),
                            ],
                            if (server.isBridge) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.shield_rounded, size: 14, color: p.success),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          server.isInformational ? s.t('informationEntry') : [FormatUtils.protocolLabel(server.protocol), ?label].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (connected)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.bolt_rounded, size: 18, color: p.success),
                    ),
                  if (!server.isInformational) PingBadge(pingMs: server.pingMs, compact: true),
                  IconButton(tooltip: s.t('actions'), onPressed: () => _actions(context, server), icon: const Icon(Icons.more_horiz, size: 20)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openServerSettings(BuildContext context, ServerModel server) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => ServerEditScreen(serverId: server.id)),
  );
}

Future<void> _tapServer(BuildContext context, ServerModel server) async {
  if (server.isInformational) return;
  final vpn = context.read<VpnProvider>();
  if (vpn.activeServerId == server.id && vpn.status == VpnStatus.connected) {
    // Already on this server — nothing to do; show the actions instead.
    await _actions(context, server);
    return;
  }
  HapticFeedback.selectionClick();
  await vpn.connect(server);
  if (context.mounted) context.read<NavProvider>().go(NavDestination.home);
}

Future<void> _actions(BuildContext context, ServerModel server) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  final p = context.palette;
  final manual = server.subscriptionId == null;
  final connected = vpn.activeServerId == server.id && vpn.status == VpnStatus.connected;
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              CountryBadge(code: server.countryCode, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headline.copyWith(fontSize: 15)),
                    Text('${FormatUtils.protocolLabel(server.protocol)} · ${server.address}:${server.port}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!server.isInformational) ListTile(
          leading: Icon(connected ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded, color: connected ? AppColors.error : p.accent),
          title: Text(connected ? s.t('disconnect') : s.t('connect')),
          onTap: () => Navigator.pop(context, connected ? 'disconnect' : 'connect'),
        ),
        if (!server.isInformational) ListTile(leading: const Icon(Icons.speed_rounded), title: Text(s.t('speedTest')), onTap: () => Navigator.pop(context, 'speed')),
        ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(server.isPinned ? s.t('unpin') : s.t('pin')), onTap: () => Navigator.pop(context, 'pin')),
        ListTile(leading: const Icon(Icons.copy_rounded), title: Text(s.t('copyLink')), onTap: () => Navigator.pop(context, 'copy')),
        ListTile(leading: const Icon(Icons.info_outline), title: Text(s.t(server.isInformational ? 'allowConnection' : 'markInformation')), onTap: () => Navigator.pop(context, 'information')),
        // Raw editing only makes sense for a manual entry.  Deletion is
        // available for both kinds: subscription entries are persisted as
        // suppressed fingerprints and therefore do not come back on refresh.
        if (manual) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(s.t('edit')), onTap: () => Navigator.pop(context, 'edit')),
        ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error), title: Text(s.t('delete')), onTap: () => Navigator.pop(context, 'delete')),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  final servers = context.read<ServersProvider>();
  switch (action) {
    case 'information':
      await servers.setInformational(server, !server.isInformational);
    case 'connect':
      await vpn.connect(server);
      if (context.mounted) context.read<NavProvider>().go(NavDestination.home);
    case 'disconnect':
      await vpn.disconnect();
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
      if (ok) await vpn.deleteServer(server.id);
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
                Icon(Icons.link_rounded, size: 18, color: context.palette.accent),
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
          ListTile(leading: Icon(sub.hideNotices ? Icons.visibility_rounded : Icons.visibility_off_rounded), title: Text(s.t('hideInformation')), onTap: () => Navigator.pop(context, 'hide')),
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
    case 'hide':
      await servers.toggleNotices(sub);
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
      if (ok) await context.read<VpnProvider>().deleteSubscription(sub.id);
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
              Row(
                children: [
                  Expanded(child: Text(s.t('interval'), style: context.palette.secondaryStyle)),
                  NukefyDropdown<UpdateInterval>(
                    value: interval,
                    items: {for (final e in UpdateInterval.values) e: _intervalLabel(s, e)},
                    onChanged: (value) => setState(() => interval = value),
                  ),
                ],
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
