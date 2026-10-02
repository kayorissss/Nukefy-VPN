import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/models/app_settings.dart';
import 'package:nukefy_vpn/core/models/server_model.dart';
import 'package:nukefy_vpn/core/models/subscription_model.dart';
import 'package:nukefy_vpn/core/services/karing_service.dart';
import 'package:nukefy_vpn/core/services/singbox_config_builder.dart';
import 'package:nukefy_vpn/core/services/whitelist_mirrors.dart';

ServerModel _node(String id, String country, String subscriptionId) => ServerModel(
      id: id,
      name: 'node-$id',
      address: '$id.example.com',
      port: 443,
      protocol: 'vless',
      countryCode: country,
      subscriptionId: subscriptionId,
      rawLink: 'vless://$id@example.com:443',
      outbound: {
        'type': 'vless',
        'server': '$id.example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
      },
    );

void main() {
  test('every whitelist mirror resolves to the same repository', () {
    for (final mirror in WhitelistCatalog.mirrors) {
      expect(WhitelistCatalog.repoOf(mirror.url), WhitelistCatalog.repo, reason: mirror.url);
      expect(WhitelistCatalog.isWhitelistUrl(mirror.url), isTrue);
    }
    expect(WhitelistCatalog.isWhitelistUrl('https://raw.githubusercontent.com/other/repo/main/a.txt'), isFalse);
  });

  test('fallback list keeps the working order and skips the current url', () {
    final first = WhitelistCatalog.mirrors.first.url;
    final fallbacks = WhitelistCatalog.fallbacksFor(first);
    expect(fallbacks, hasLength(WhitelistCatalog.mirrors.length - 1));
    expect(fallbacks.contains(first), isFalse);
    expect(fallbacks.first, WhitelistCatalog.mirrors[1].url);
    // An unrelated subscription gets no mirrors at all.
    expect(WhitelistCatalog.fallbacksFor('https://panel.example/sub/1'), isEmpty);
  });

  test('balancer pool only spans the whitelist subscription and honours the RU filter', () {
    const sub = 'sub-1';
    final subscriptions = [
      SubscriptionModel(id: sub, name: 'wl', url: WhitelistCatalog.mirrors.first.url),
      SubscriptionModel(id: 'sub-2', name: 'other', url: 'https://panel.example/sub/2'),
    ];
    final servers = [
      _node('a', 'de', sub),
      _node('b', 'fi', sub),
      _node('c', 'ru', sub),
      _node('d', 'de', 'sub-2'),
    ];
    final settings = AppSettings(karingEnabled: true);
    final pool = KaringService.balancerPool(
      servers: servers,
      subscriptions: subscriptions,
      settings: settings,
      activeSubscriptionId: sub,
    );
    expect(pool.map((e) => e.id).toSet(), {'a', 'b'});

    // Without the RU filter the russian node joins the pool.
    settings.karingExcludeRu = false;
    expect(
      KaringService.balancerPool(servers: servers, subscriptions: subscriptions, settings: settings, activeSubscriptionId: sub),
      hasLength(3),
    );

    // A non-whitelist subscription never becomes a balancer.
    settings.karingExcludeRu = true;
    expect(
      KaringService.balancerPool(servers: servers, subscriptions: subscriptions, settings: settings, activeSubscriptionId: 'sub-2'),
      isEmpty,
    );

    // Switching the mode off disables the pool entirely.
    settings.karingEnabled = false;
    expect(
      KaringService.balancerPool(servers: servers, subscriptions: subscriptions, settings: settings, activeSubscriptionId: sub),
      isEmpty,
    );
  });

  test('sing-box config emits a urltest group over the pool', () {
    const sub = 'sub-1';
    final subscriptions = [
      SubscriptionModel(id: sub, name: 'wl', url: WhitelistCatalog.mirrors.first.url),
    ];
    final servers = [_node('a', 'de', sub), _node('b', 'fi', sub)];
    final settings = AppSettings(karingEnabled: true);
    final config = SingboxConfigBuilder.build(
      server: servers.first,
      settings: settings,
      logPath: '/tmp/sing-box.log',
      cachePath: '/tmp/cache.db',
      desktopTun: true,
      forceProxyOnly: false,
      balancerPool: KaringService.balancerPool(
        servers: servers,
        subscriptions: subscriptions,
        settings: settings,
        activeSubscriptionId: sub,
      ),
    );
    final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final urltest = outbounds.where((o) => o['type'] == 'urltest').toList();
    expect(urltest, hasLength(1));
    expect(urltest.first['tag'], 'proxy');
    expect((urltest.first['outbounds'] as List), hasLength(2));
    // The selected node is part of the pool under its own tag.
    expect(outbounds.where((o) => o['tag'] == 'kb0'), hasLength(1));
  });
}
