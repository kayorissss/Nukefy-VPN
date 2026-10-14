import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';
import '../models/vpn_status.dart';

/// Builds an Xray-core configuration.
///
/// sing-box (checked up to v1.14) has no XHTTP/SplitHTTP transport, so
/// servers using it are served by the bundled Xray engine instead of being
/// rejected or silently degraded to raw TCP. The local listeners reuse the
/// same SOCKS/HTTP ports as the sing-box engine, and a stats API inbound is
/// added so traffic numbers stay real (queried via `xray api statsquery`).
class XrayConfigBuilder {
  static Map<String, dynamic> build({
    required ServerModel server,
    required AppSettings settings,
  }) {
    final outbound = _proxyOutbound(server);
    final listen = settings.allowLan ? '0.0.0.0' : '127.0.0.1';
    return {
      'log': {'loglevel': 'warning'},
      'stats': <String, dynamic>{},
      'api': {
        'tag': 'api',
        'services': ['StatsService'],
      },
      'policy': {
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'dns': {
        'servers': [
          _dnsServer(settings.proxyDns),
          _dnsServer(settings.directDns),
        ],
        'queryStrategy': 'UseIPv4',
      },
      'inbounds': [
        {
          'tag': 'socks-in',
          'listen': listen,
          'port': settings.socksPort,
          'protocol': 'socks',
          'settings': {'udp': true},
          'sniffing': {'enabled': true, 'destOverride': ['http', 'tls']},
        },
        {
          'tag': 'http-in',
          'listen': listen,
          'port': settings.httpPort,
          'protocol': 'http',
          'sniffing': {'enabled': true, 'destOverride': ['http', 'tls']},
        },
        {
          'tag': 'api',
          'listen': '127.0.0.1',
          'port': AppConstants.xrayApiPort,
          'protocol': 'dokodemo-door',
          'settings': {'address': '127.0.0.1'},
        },
      ],
      'outbounds': [
        outbound,
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'inboundTag': ['api'],
            'outboundTag': 'api',
          },
          ..._routingRules(settings),
        ],
      },
    };
  }

  static String _dnsServer(String raw) {
    final value = raw.trim();
    if (value.startsWith('https://')) return value;
    if (value.startsWith('tls://')) return value;
    // Plain IPs and udp://host are passed as bare addresses.
    return value.replaceFirst('udp://', '');
  }

  static List<Map<String, dynamic>> _routingRules(AppSettings settings) {
    final rules = <Map<String, dynamic>>[
      {
        'type': 'field',
        'ip': ['geoip:private'],
        'outboundTag': 'direct',
      },
    ];
    switch (settings.routingMode) {
      case RoutingMode.global:
        rules.add({
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': 'proxy',
        });
      case RoutingMode.blockedOnly:
        rules.add({
          'type': 'field',
          'domain': [
            for (final suffix in AppConstants.blockedDomainSuffixes)
              'domain:$suffix',
          ],
          'outboundTag': 'proxy',
        });
        for (final rule in settings.rules) {
          rules.add(_customRule(rule));
        }
        rules.add({
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': 'direct',
        });
      case RoutingMode.bypassRu:
        rules.addAll([
          {
            'type': 'field',
            'domain': ['geosite:ru'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'ip': ['geoip:ru'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'network': 'tcp,udp',
            'outboundTag': 'proxy',
          },
        ]);
      case RoutingMode.custom:
        for (final rule in settings.rules) {
          rules.add(_customRule(rule));
        }
        rules.add({
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': 'proxy',
        });
    }
    return rules;
  }

  static Map<String, dynamic> _customRule(RoutingRule rule) {
    final outbound = switch (rule.action) {
      'direct' => 'direct',
      'block' => 'block',
      _ => 'proxy',
    };
    if (rule.kind == 'ip_cidr') {
      return {
        'type': 'field',
        'ip': [rule.value.trim()],
        'outboundTag': outbound,
      };
    }
    return {
      'type': 'field',
      'domain': ['domain:${rule.value.trim()}'],
      'outboundTag': outbound,
    };
  }

  static Map<String, dynamic> _proxyOutbound(ServerModel server) {
    final source = server.outbound ??
        {
          'type': server.protocol,
          'server': server.address,
          'server_port': server.port,
        };
    final type = (source['type'] ?? server.protocol).toString().toLowerCase();
    final address = (source['server'] ?? server.address).toString();
    final port = (source['server_port'] as num?)?.toInt() ?? server.port;
    final stream = _streamSettings(source);
    switch (type) {
      case 'vless':
        final flow = (source['flow'] ?? '').toString();
        final network = (stream['network'] ?? 'tcp').toString();
        return {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': address,
                'port': port,
                'users': [
                  {
                    'id': (source['uuid'] ?? '').toString(),
                    'encryption': 'none',
                    // Vision flow only exists on raw TCP in Xray.
                    if (flow.isNotEmpty && network == 'tcp') 'flow': flow,
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'vmess':
        return {
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': address,
                'port': port,
                'users': [
                  {
                    'id': (source['uuid'] ?? '').toString(),
                    'alterId': (source['alter_id'] as num?)?.toInt() ?? 0,
                    'security': (source['security'] ?? 'auto').toString(),
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'trojan':
        return {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {
                'address': address,
                'port': port,
                'password': (source['password'] ?? '').toString(),
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'shadowsocks':
        if (server.isXhttp) {
          throw ArgumentError('ss-xhttp-unsupported');
        }
        return {
          'tag': 'proxy',
          'protocol': 'shadowsocks',
          'settings': {
            'servers': [
              {
                'address': address,
                'port': port,
                'method': (source['method'] ?? '').toString(),
                'password': (source['password'] ?? '').toString(),
              },
            ],
          },
          'streamSettings': stream,
        };
      default:
        throw ArgumentError('xray-unsupported-protocol:$type');
    }
  }

  static Map<String, dynamic> _streamSettings(Map<String, dynamic> source) {
    final transport = source['transport'];
    final transportMap = transport is Map
        ? transport.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final type = (transportMap['type'] ?? 'tcp').toString().toLowerCase();
    final stream = <String, dynamic>{};
    switch (type) {
      case 'xhttp':
      case 'splithttp':
        stream['network'] = 'xhttp';
        final settings = <String, dynamic>{
          'path': (transportMap['path'] ?? '/').toString(),
          'mode': (transportMap['mode'] ?? 'auto').toString(),
        };
        final host = (transportMap['host'] ?? '').toString();
        if (host.isNotEmpty) settings['host'] = host;
        final extra = transportMap['extra'];
        if (extra is Map && extra.isNotEmpty) {
          settings['extra'] = extra.map((k, v) => MapEntry(k.toString(), v));
        }
        stream['xhttpSettings'] = settings;
      case 'ws':
      case 'websocket':
        stream['network'] = 'ws';
        final headers = transportMap['headers'];
        stream['wsSettings'] = {
          'path': (transportMap['path'] ?? '/').toString(),
          if (headers is Map && headers.isNotEmpty)
            'headers': headers.map((k, v) => MapEntry(k.toString(), '$v')),
        };
      case 'grpc':
        stream['network'] = 'grpc';
        stream['grpcSettings'] = {
          'serviceName': (transportMap['service_name'] ?? '').toString(),
          'multiMode': false,
        };
      case 'http':
      case 'h2':
      case 'httpupgrade':
        // Xray folded the old HTTP transports into XHTTP.
        stream['network'] = 'xhttp';
        final hosts = transportMap['host'];
        stream['xhttpSettings'] = {
          'path': (transportMap['path'] ?? '/').toString(),
          if (hosts is List && hosts.isNotEmpty) 'host': hosts.first.toString(),
          if (hosts is String && hosts.isNotEmpty) 'host': hosts,
        };
      default:
        stream['network'] = 'tcp';
    }

    final tls = source['tls'];
    if (tls is Map) {
      final tlsMap = tls.map((k, v) => MapEntry(k.toString(), v));
      final reality = tlsMap['reality'];
      final realityMap = reality is Map
          ? reality.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{};
      final utls = tlsMap['utls'];
      final fingerprint = utls is Map
          ? (utls['fingerprint'] ?? 'chrome').toString()
          : 'chrome';
      final serverName = (tlsMap['server_name'] ?? '').toString();
      if (realityMap['enabled'] == true) {
        stream['security'] = 'reality';
        stream['realitySettings'] = {
          'serverName': serverName,
          'fingerprint': fingerprint,
          'publicKey': (realityMap['public_key'] ?? '').toString(),
          'shortId': (realityMap['short_id'] ?? '').toString(),
          'spiderX': '',
        };
      } else if (tlsMap['enabled'] == true) {
        stream['security'] = 'tls';
        final alpn = tlsMap['alpn'];
        stream['tlsSettings'] = {
          'serverName': serverName,
          'allowInsecure': tlsMap['insecure'] == true,
          'fingerprint': fingerprint,
          if (alpn is List && alpn.isNotEmpty)
            'alpn': alpn.map((e) => e.toString()).toList(),
        };
      } else {
        stream['security'] = 'none';
      }
    } else {
      stream['security'] = 'none';
    }
    return stream;
  }
}
