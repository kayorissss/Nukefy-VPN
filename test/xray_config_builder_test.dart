import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/models/app_settings.dart';
import 'package:nukefy_vpn/core/models/server_model.dart';
import 'package:nukefy_vpn/core/services/singbox_config_builder.dart';
import 'package:nukefy_vpn/core/services/xray_config_builder.dart';
import 'package:nukefy_vpn/core/utils/link_parser.dart';

void main() {
  test('XHTTP links stay XHTTP and build an Xray Reality outbound', () {
    const link =
        'vless://11111111-1111-1111-1111-111111111111@edge.example:443?type=xhttp&path=%2Fsplit&host=cdn.example&mode=packet-up&security=reality&sni=cover.example&pbk=public-key&sid=01&fp=chrome#XHTTP';
    final parsed = LinkParser.parseInput(link);
    final server = parsed.servers.single;

    expect(server.usesXhttp, isTrue);
    expect(SingboxConfigBuilder.validationError(server), 'XRAY_TRANSPORT_REQUIRED');
    expect(XrayConfigBuilder.supports(server), isTrue);

    final config = jsonDecode(XrayConfigBuilder.buildJson(
      server: server,
      settings: AppSettings(),
      logPath: r'C:\Temp\xray.log',
      inboundPort: 20808,
      ports: const LocalPorts(socks: 10808, http: 10809, clash: 9090),
    )) as Map<String, dynamic>;
    final proxy = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['tag'] == 'proxy');
    final stream = proxy['streamSettings'] as Map<String, dynamic>;
    final xhttp = stream['xhttpSettings'] as Map<String, dynamic>;
    final reality = stream['realitySettings'] as Map<String, dynamic>;

    expect(stream['network'], 'xhttp');
    expect(xhttp['path'], '/split');
    expect(xhttp['host'], 'cdn.example');
    expect(xhttp['mode'], 'packet-up');
    expect(reality['serverName'], 'cover.example');
    expect(reality['publicKey'], 'public-key');
    expect(reality['shortId'], '01');
    expect(reality['fingerprint'], 'chrome');
  });

  test('XHTTP TUN front-end sends traffic to the Xray inbound', () {
    final config = jsonDecode(XrayConfigBuilder.buildSingboxFrontendJson(
      settings: AppSettings(),
      xrayPort: 20808,
      logPath: r'C:\Temp\xray-frontend.log',
      cachePath: r'C:\Temp\xray-cache.db',
      useTun: true,
      ports: const LocalPorts(socks: 10808, http: 10809, clash: 9090),
    )) as Map<String, dynamic>;
    final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final xray = outbounds.singleWhere((item) => item['tag'] == 'xray');

    expect((config['inbounds'] as List).first['type'], 'tun');
    expect(config['route']['final'], 'xray');
    expect(xray['server'], '127.0.0.1');
    expect(xray['server_port'], 20808);
  });

  test('Xray converter refuses protocols it cannot translate', () {
    final server = ServerModel(
      id: '1',
      name: 'unsupported xhttp',
      address: 'edge.example',
      port: 443,
      protocol: 'shadowsocks',
      outbound: {
        'type': 'shadowsocks',
        'transport': {'type': 'xhttp'},
      },
    );

    expect(server.usesXhttp, isTrue);
    expect(XrayConfigBuilder.supports(server), isFalse);
    expect(
      () => XrayConfigBuilder.buildJson(
        server: server,
        settings: AppSettings(),
        logPath: '/tmp/xray.log',
        inboundPort: 20808,
      ),
      throwsA(isA<XrayConfigException>()),
    );
  });
}
