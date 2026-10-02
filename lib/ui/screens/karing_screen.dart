import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/subscription_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/karing_service.dart';
import '../../core/services/whitelist_mirrors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';
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
    final value = settings.settings;
    final s = settings.strings;
    final p = context.palette;
    final subscription = _whitelistSubscription(servers);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: ResponsiveSections(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          SectionCard(
            title: s.t('karingTitle'),
            icon: Icons.route_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('karingHint'), style: p.secondaryStyle),
                const SizedBox(height: 10),
                SwitchTile(
                  icon: Icons.route_rounded,
                  title: s.t('karingEnable'),
                  subtitle: s.t('karingEnableHint'),
                  value: value.karingEnabled,
                  onChanged: _setEnabled,
                ),
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
            title: s.t('karingSub'),
            icon: Icons.rss_feed_rounded,
            description: s.t('karingSubHint'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subscription != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surface.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(subscription.name, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            Text('${servers.serversOf(subscription.id).length}', style: AppTextStyles.number.copyWith(color: p.accent)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(subscription.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.captionStyle),
                        if (subscription.lastError != null) ...[
                          const SizedBox(height: 6),
                          Text('${subscription.lastError}', style: AppTextStyles.bodySecondary.copyWith(color: p.error)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: servers.refreshing ? null : () => servers.refreshSubscription(subscription.id),
                        icon: servers.refreshing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(s.t('refresh')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _adding ? null : () => _addSubscription(subscription.url),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: Text(s.t('refresh')),
                      ),
                    ],
                  ),
                ] else
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
          SectionCard(
            title: s.t('karingAbout'),
            icon: Icons.menu_book_outlined,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://github.com/KaringX/karing'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('KaringX/karing'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://github.com/zieng2/wl'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('zieng2/wl'),
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
