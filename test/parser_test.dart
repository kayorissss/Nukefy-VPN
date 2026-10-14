import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/models/app_settings.dart';
import 'package:nukefy_vpn/core/models/server_model.dart';
import 'package:nukefy_vpn/core/models/subscription_model.dart';
import 'package:nukefy_vpn/core/models/vpn_status.dart';
import 'package:nukefy_vpn/core/services/singbox_config_builder.dart';
import 'package:nukefy_vpn/core/services/xray_config_builder.dart';
import 'package:nukefy_vpn/core/utils/base64_utils.dart';
import 'package:nukefy_vpn/core/utils/link_parser.dart';
import 'package:nukefy_vpn/core/utils/share_link_builder.dart';
import 'package:nukefy_vpn/core/utils/version_utils.dart';

void main() {
  test('parses a VLESS Reality link', () {
    const link =
        'vless://11111111-1111-1111-1111-111111111111@example.com:443?security=reality&sni=www.cloudflare.com&pbk=abc&sid=dead&fp=chrome&flow=xtls-rprx-vision#Home';
    final parsed = LinkParser.parseInput(link);
    expect(parsed.servers, hasLength(1));
    expect(parsed.servers.first.protocol, 'vless');
    expect(parsed.servers.first.address, 'example.com');
    expect(parsed.servers.first.port, 443);
    expect(parsed.servers.first.outbound?['flow'], 'xtls-rprx-vision');
  });

  test('parses a Base64 subscription body', () {
    const link = 'trojan://secret@node.example:443?security=tls&sni=node.example#Node';
    final body = base64Encode(utf8.encode(link));
    final parsed = LinkParser.parseInput(body);
    expect(parsed.servers, hasLength(1));
    expect(parsed.servers.first.protocol, 'trojan');
  });

  test('parses Clash YAML and SIP008', () {
    const clash = '''
proxies:
  - name: Hy2
    type: hysteria2
    server: hy.example
    port: 443
    password: pass
''';
    final clashParsed = LinkParser.parseInput(clash);
    expect(clashParsed.kind, 'clash');
    expect(clashParsed.servers.first.protocol, 'hysteria2');

    const sip = '''
{"version":1,"servers":[{"server":"ss.example","server_port":8388,"password":"p","method":"chacha20-ietf-poly1305","remarks":"SIP"}]}
''';
    final sipParsed = LinkParser.parseInput(sip);
    expect(sipParsed.kind, 'sip008');
    expect(sipParsed.servers.first.protocol, 'shadowsocks');
    expect(sipParsed.servers.first.address, 'ss.example');
  });

  test('treats a bare https url as a subscription', () {
    final parsed = LinkParser.parseInput('https://example.com/sub');
    expect(parsed.subscriptionUrls, ['https://example.com/sub']);
    expect(parsed.servers, isEmpty);
  });

  test('share link keeps the original link', () {
    final server = ServerModel(
      id: '1',
      name: 'Home',
      address: 'example.com',
      port: 443,
      protocol: 'vless',
      rawLink: 'vless://uuid@example.com:443#Home',
    );
    expect(ShareLinkBuilder.build(server), server.rawLink);
  });

  test('version compare ignores a leading v', () {
    expect(VersionUtils.isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(VersionUtils.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(VersionUtils.isNewer('1.0.0-beta', '1.0.0'), isFalse);
  });

  test('sing-box config is 1.12 shaped and has no local DNS', () {
    final server = ServerModel(
      id: '1',
      name: 'Home',
      address: 'example.com',
      port: 443,
      protocol: 'vless',
      outbound: {
        'type': 'vless',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
      },
    );
    final config = SingboxConfigBuilder.build(
      server: server,
      settings: AppSettings(),
      logPath: '/tmp/sing-box.log',
      cachePath: '/tmp/cache.db',
      desktopTun: true,
      forceProxyOnly: false,
    );
    final encoded = jsonEncode(config);
    expect(encoded.contains('"type":"local"'), isFalse);
    expect(encoded.contains('172.19.0.1/30'), isTrue);
    expect(encoded.contains('geosite-category-ru.srs'), isTrue);
    expect(encoded.contains('"download_detour":"direct"'), isTrue);
    expect(encoded.contains('geoip-ru.srs'), isTrue);
    expect((config['inbounds'] as List).any((item) => item['type'] == 'tun'), isTrue);
    expect((config['inbounds'] as List).any((item) => item['listen_port'] == 10808), isTrue);
  });

  test('parses an XHTTP (SplitHTTP) VLESS link with extra', () {
    const link =
        'vless://11111111-1111-1111-1111-111111111111@x.example:443?security=reality&sni=www.cloudflare.com&pbk=abc&sid=dead&type=xhttp&path=%2Fapi&host=cdn.example&mode=stream-one&extra=%7B%22scMaxEachPostBytes%22%3A1000000%7D#XHTTP';
    final parsed = LinkParser.parseInput(link);
    expect(parsed.servers, hasLength(1));
    final server = parsed.servers.first;
    expect(server.isXhttp, isTrue);
    final transport = server.outbound?['transport'] as Map;
    expect(transport['type'], 'xhttp');
    expect(transport['path'], '/api');
    expect(transport['mode'], 'stream-one');
    expect((transport['extra'] as Map)['scMaxEachPostBytes'], 1000000);
  });

  test('sing-box builder refuses XHTTP instead of degrading it', () {
    final server = ServerModel(
      id: '1',
      name: 'X',
      address: 'x.example',
      port: 443,
      protocol: 'vless',
      outbound: {
        'type': 'vless',
        'server': 'x.example',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'transport': {'type': 'xhttp', 'path': '/api'},
      },
    );
    expect(
      () => SingboxConfigBuilder.build(
        server: server,
        settings: AppSettings(),
        logPath: '/tmp/sing-box.log',
        cachePath: '/tmp/cache.db',
        desktopTun: true,
        forceProxyOnly: false,
      ),
      throwsArgumentError,
    );
  });

  test('xray builder emits a real XHTTP outbound', () {
    final server = ServerModel(
      id: '1',
      name: 'X',
      address: 'x.example',
      port: 443,
      protocol: 'vless',
      outbound: {
        'type': 'vless',
        'server': 'x.example',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        'tls': {
          'enabled': true,
          'server_name': 'www.cloudflare.com',
          'reality': {'enabled': true, 'public_key': 'abc', 'short_id': 'dead'},
        },
        'transport': {'type': 'xhttp', 'path': '/api', 'mode': 'stream-one'},
      },
    );
    final config = XrayConfigBuilder.build(server: server, settings: AppSettings());
    final outbound = (config['outbounds'] as List).first as Map;
    expect(outbound['protocol'], 'vless');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['network'], 'xhttp');
    expect(stream['security'], 'reality');
    expect((stream['xhttpSettings'] as Map)['path'], '/api');
    final inbounds = config['inbounds'] as List;
    expect(inbounds.any((e) => e['port'] == 10808), isTrue);
    expect(inbounds.any((e) => e['tag'] == 'api'), isTrue);
  });

  test('subscription mirrors survive a JSON round trip', () {
    final sub = SubscriptionModel(
      id: '1',
      name: 'Sub',
      url: 'https://a.example/sub',
      mirrors: const ['https://b.example/sub', 'https://c.example/sub'],
      lastUsedUrl: 'https://b.example/sub',
    );
    final restored = SubscriptionModel.fromJson(sub.toJson());
    expect(restored.mirrors, sub.mirrors);
    expect(restored.lastUsedUrl, 'https://b.example/sub');
    expect(UpdateInterval.hour6.minutes, 360);
  });

  test('base64 helper round-trips text', () {
    expect(Base64Utils.tryDecodeUtf8(base64Encode(utf8.encode('vless://a'))), 'vless://a');
  });
}
