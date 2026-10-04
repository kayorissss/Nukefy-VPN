import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/server_model.dart';
import '../../core/models/subscription_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/karing_service.dart';
import '../../core/services/whitelist_mirrors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/connect_button.dart';
import '../widgets/responsive_sections.dart';
import 'servers_screen.dart';
import '../widgets/section_card.dart';

/// Karing-style whitelist bypass page: subscription mirrors, latency
/// balancer and the routing switches the method relies on.
class KaringScreen extends StatefulWidget {
  const KaringScreen({super.key, this.active = true});

  final bool active;

  @override
  State<KaringScreen> createState() => _KaringScreenState();
}

class _KaringScreenState extends State<KaringScreen> {
  final _karing = KaringService.instance;
  bool _adding = false;

  S get s => context.read<SettingsProvider>().strings;

  @override
  void initState() {
    super.initState();
    _karing.addListener(_changed);
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _karing.reachability.isEmpty && !_karing.checking) {
          _karing.checkMirrors();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant KaringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _karing.reachability.isEmpty && !_karing.checking) {
      _karing.checkMirrors();
    }
  }

  @override
  void dispose() {
    _karing.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  SubscriptionModel? _whitelistSubscription(ServersProvider servers) {
    for (final subscription in servers.subscriptions) {
      if (WhitelistCatalog.isWhitelistUrl(subscription.url)) return subscription;
    }
    return null;
  }

  Future<void> _addSubscription(String url) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final servers = context.read<ServersProvider>();
      final existing = _whitelistSubscription(servers);
      if (existing != null) {
        if (existing.url != url) {
          await servers.updateSubscription(existing.id, url: url);
          await servers.refreshSubscription(existing.id);
        } else {
          if (mounted) showNukefySnack(context, s.t('karingAlready'));
        }
      } else {
        await servers.addSubscription(url, name: WhitelistCatalog.defaultName);
        if (mounted) showNukefySnack(context, s.t('karingAdded'));
      }
      await _syncHourly();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// The mirror refreshes hourly; keep the stored subscription in step while
  /// the bypass mode is on and the user asked for hourly updates.
  Future<void> _syncHourly() async {
    final settings = context.read<SettingsProvider>();
    final servers = context.read<ServersProvider>();
    final subscription = _whitelistSubscription(servers);
    if (subscription == null) return;
    final wanted = settings.settings.karingEnabled && settings.settings.karingHourly
        ? UpdateInterval.hour1
        : null;
    if (wanted != null && subscription.autoUpdateInterval != wanted) {
      await servers.updateSubscription(subscription.id, interval: wanted);
    }
  }

  Future<void> _setEnabled(bool value) async {
    final settings = context.read<SettingsProvider>();
    await settings.update((item) {
      item.karingEnabled = value;
      // Whitelists break when RU traffic is sent direct: the whole point is
      // that unlisted Russian sites must also go through the tunnel.
      if (value) item.routingMode = RoutingMode.global;
    });
    await _syncHourly();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final servers = context.watch<ServersProvider>();
    final vpn = context.watch<VpnProvider>();
    final value = settings.settings;
    final s = settings.strings;
    final p = context.palette;
    final subscription = _whitelistSubscription(servers);
    final pool = subscription == null
        ? const <ServerModel>[]
        : servers.serversOf(subscription.id).where((e) => !e.isInformational).toList();
    final activeSrv = vpn.activeServer;
    final connectedHere = activeSrv != null && pool.any((e) => e.id == activeSrv.id);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> toggle() async {
      if (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting) {
        await vpn.disconnect();
        return;
      }
      if (connectedHere) {
        await vpn.connect(activeSrv);
        return;
      }
      if (pool.isEmpty) {
        if (mounted) showNukefySnack(context, s.t('wlNoSubscription'));
        return;
      }
      await vpn.connect(pool.first);
    }

    final powerCard = SectionCard(
      title: s.t('karingTitle'),
      icon: Icons.route_rounded,
      trailing: PopupMenuButton<String>(
        tooltip: s.t('zSettings'),
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (id) async {
          switch (id) {
            case 'enable':
              await _setEnabled(!value.karingEnabled);
            case 'add':
              final mirror = await _karing.firstReachable();
              if (!mounted) return;
              await _addSubscription(mirror?.url ?? WhitelistCatalog.mirrors.first.url);
            case 'refresh':
              if (subscription != null) await servers.refreshSubscription(subscription.id);
            case 'ping':
              if (subscription != null) await servers.pingSubscription(subscription.id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'enable', child: Text(value.karingEnabled ? s.t('wlModeOff') : s.t('wlModeOn'))),
          PopupMenuItem(value: 'add', child: Text(s.t('karingAddSub'))),
          PopupMenuItem(value: 'refresh', child: Text(s.t('refresh'))),
          PopupMenuItem(value: 'ping', child: Text(s.t('checkPing'))),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: ConnectButton(
              status: vpn.status,
              onPressed: toggle,
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Text(
              connectedHere ? activeSrv.displayName : s.t('wlNotConnected'),
              key: ValueKey(connectedHere ? activeSrv.id : 'none'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.karingEnabled ? s.t('wlModeOn') : s.t('wlModeOff'),
            textAlign: TextAlign.center,
            style: p.captionStyle,
          ),
          const SizedBox(height: 14),
          if (pool.isNotEmpty && subscription != null)
            Row(
              children: [
                Expanded(
                  child: NukefyDropdown<String>(
                    value: connectedHere ? activeSrv.id : pool.first.id,
                    items: {for (final e in pool) e.id: e.name},
                    onChanged: (id) => vpn.selectServer(id),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: s.t('checkPing'),
                  onPressed: servers.pinging ? null : () => servers.pingSubscription(subscription.id),
                  icon: const Icon(Icons.speed_rounded, size: 19),
                ),
                IconButton(
                  tooltip: s.t('refresh'),
                  onPressed: servers.refreshing ? null : () => servers.refreshSubscription(subscription.id),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _adding
                  ? null
                  : () async {
                      final mirror = await _karing.firstReachable();
                      if (!mounted) return;
                      await _addSubscription(mirror?.url ?? WhitelistCatalog.mirrors.first.url);
                    },
              icon: _adding
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_rounded, size: 18),
              label: Text(s.t('karingAddSub')),
            ),
          ),
        ],
      ),
    );

    final serversCard = SectionCard(
      title: subscription?.name ?? s.t('karingSub'),
      icon: Icons.dns_rounded,
      trailing: subscription == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s.t('checkPing'),
                  onPressed: servers.refreshing ? null : () => servers.pingSubscription(subscription.id),
                  icon: const Icon(Icons.speed_rounded, size: 19),
                ),
                IconButton(
                  tooltip: s.t('refresh'),
                  onPressed: servers.refreshing ? null : () => servers.refreshSubscription(subscription.id),
                  icon: servers.refreshing
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
      child: subscription == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('karingSubHint'), style: p.secondaryStyle),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _adding ? null : () async {
                      final mirror = await _karing.firstReachable();
                      if (!mounted) return;
                      await _addSubscription(mirror?.url ?? WhitelistCatalog.mirrors.first.url);
                    },
                    icon: _adding
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(s.t('karingAddSub')),
                  ),
                ),
              ],
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final server in pool.take(60))
                    ServerTile(server: server, antiblock: value.antiblock),
                  if (pool.length > 60)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('${s.t('shownCount')}: 60 / ${pool.length}', style: p.captionStyle),
                    ),
                ],
              ),
            ),
    );

    return SafeArea(
      bottom: false,
      child: ResponsiveSections(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 860
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: powerCard),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: serversCard),
                      ],
                    ),
                  )
                : Column(
                    children: [powerCard, const SizedBox(height: 16), serversCard],
                  ),
          ),
          // The tuning switches and mirrors live below the fold: the first
          // screen is the connect button and the server list, nothing else.
          const SizedBox(height: 140),
          SectionCard(
            title: s.t('wlSettingsTitle'),
            icon: Icons.tune_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchTile(
                  icon: Icons.speed_rounded,
                  title: s.t('karingBalancer'),
                  subtitle: s.t('karingBalancerHint'),
                  value: value.karingBalancer,
                  onChanged: (next) => settings.update((item) => item.karingBalancer = next),
                ),
                SwitchTile(
                  icon: Icons.public_off_rounded,
                  title: s.t('karingExcludeRu'),
                  subtitle: s.t('karingExcludeRuHint'),
                  value: value.karingExcludeRu,
                  onChanged: (next) => settings.update((item) => item.karingExcludeRu = next),
                ),
                SwitchTile(
                  icon: Icons.lock_open_rounded,
                  title: s.t('karingInsecure'),
                  subtitle: s.t('karingInsecureHint'),
                  value: value.karingAllowInsecure,
                  onChanged: (next) => settings.update((item) => item.karingAllowInsecure = next),
                ),
                SwitchTile(
                  icon: Icons.update_rounded,
                  title: s.t('karingHourly'),
                  subtitle: s.t('karingHourlyHint'),
                  value: value.karingHourly,
                  onChanged: (next) async {
                    await settings.update((item) => item.karingHourly = next);
                    await _syncHourly();
                  },
                ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('karingMirrors'),
            icon: Icons.cloud_queue_rounded,
            trailing: TextButton(
              onPressed: _karing.checking ? null : () => _karing.checkMirrors(),
              child: Text(s.t('karingMirrorCheck')),
            ),
            child: Column(
              children: [
                if (_karing.checking)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
                  ),
                for (final mirror in WhitelistCatalog.mirrors)
                  _MirrorRow(
                    mirror: mirror,
                    state: _karing.reachability[mirror.id],
                    selected: subscription?.url == mirror.url,
                    onTap: () => _addSubscription(mirror.url),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MirrorRow extends StatelessWidget {
  const _MirrorRow({required this.mirror, required this.state, required this.selected, required this.onTap});

  final WhitelistMirror mirror;
  final bool? state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final color = state == null ? p.textDisabled : (state! ? p.success : p.error);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(mirror.label, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                        if (mirror.experimental) ...[
                          const SizedBox(width: 8),
                          Text(s.t('karingMirrorExperimental'), style: p.captionStyle),
                        ],
                      ],
                    ),
                    Text(mirror.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.captionStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state == null ? '—' : (state! ? s.t('karingMirrorOk') : s.t('karingMirrorFail')),
                style: AppTextStyles.bodySecondary.copyWith(color: color),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 16, color: p.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
