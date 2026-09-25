import 'package:yaml/yaml.dart';

import 'geo_utils.dart';
import 'link_parser.dart';

class ClashParser {
  static List<ServerDraft> parse(String text) {
    dynamic doc;
    try {
      doc = loadYaml(text);
    } catch (_) {
      return const [];
    }
    final root = _toDart(doc);
    if (root is! Map) return const [];
    final proxies = root['proxies'];
    if (proxies is! List) return const [];
    final servers = <ServerDraft>[];
    for (final item in proxies) {
      if (item is Map) {
        final draft = _proxy(item.map((k, v) => MapEntry(k.toString(), v)));
        if (draft != null) servers.add(draft);
      }
    }
    return servers;
  }

  static ServerDraft? _proxy(Map<String, dynamic> proxy) {
    final type = (proxy['type'] ?? '').toString().toLowerCase();
    final name = (proxy['name'] ?? proxy['tag'] ?? type).toString();
    final server = (proxy['server'] ?? '').toString();
    final port = (proxy['port'] as num?)?.toInt() ??
        int.tryParse('${proxy['port']}') ??
        443;
    if (server.isEmpty) return null;
    switch (type) {
      case 'vless':
        return _draft(name, server, port, 'vless', _vless(proxy, server, port));
      case 'vmess':
        return _draft(name, server, port, 'vmess', _vmess(proxy, server, port));
      case 'trojan':
        return _draft(
          name,
          server,
          port,
          'trojan',
          _trojan(proxy, server, port),
        );
      case 'ss':
      case 'shadowsocks':
        return _draft(
          name,
          server,
          port,
          'shadowsocks',
          _ss(proxy, server, port),
        );
      case 'hysteria2':
      case 'hy2':
        return _draft(
          name,
          server,
          port,
          'hysteria2',
          _hy2(proxy, server, port),
        );
      case 'tuic':
        return _draft(name, server, port, 'tuic', _tuic(proxy, server, port));
      case 'wireguard':
      case 'wg':
        final endpoint = _wg(proxy, server, port, amnezia: false);
        return endpoint == null
            ? null
            : _draft(name, server, port, 'wireguard', null, endpoint: endpoint);
      case 'amneziawg':
      case 'awg':
        final endpoint = _wg(proxy, server, port, amnezia: true);
        return endpoint == null
            ? null
            : _draft(name, server, port, 'amneziawg', null, endpoint: endpoint);
      default:
        return null;
    }
  }

  static Map<String, dynamic> _vless(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    final outbound = <String, dynamic>{
      'type': 'vless',
      'server': server,
      'server_port': port,
      'uuid': (proxy['uuid'] ?? '').toString(),
    };
    final flow = (proxy['flow'] ?? '').toString();
    if (flow.isNotEmpty) outbound['flow'] = flow;
    final tls = _tls(proxy, server);
    if (tls != null) outbound['tls'] = tls;
    final transport = _transport(proxy);
    if (transport != null) outbound['transport'] = transport;
    return outbound;
  }

  static Map<String, dynamic> _vmess(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    final outbound = <String, dynamic>{
      'type': 'vmess',
      'server': server,
      'server_port': port,
      'uuid': (proxy['uuid'] ?? '').toString(),
      'security': (proxy['cipher'] ?? proxy['security'] ?? 'auto').toString(),
      'alter_id': (proxy['alterId'] as num?)?.toInt() ?? 0,
    };
    final tls = _tls(proxy, server);
    if (tls != null) outbound['tls'] = tls;
    final transport = _transport(proxy);
    if (transport != null) outbound['transport'] = transport;
    return outbound;
  }

  static Map<String, dynamic> _trojan(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    return {
      'type': 'trojan',
      'server': server,
      'server_port': port,
      'password': (proxy['password'] ?? '').toString(),
      'tls': _tls(proxy, server, defaultOn: true),
      if (_transport(proxy) != null) 'transport': _transport(proxy),
    };
  }

  static Map<String, dynamic> _ss(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    return {
      'type': 'shadowsocks',
      'server': server,
      'server_port': port,
      'method': (proxy['cipher'] ?? proxy['method'] ?? 'chacha20-ietf-poly1305')
          .toString(),
      'password': (proxy['password'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _hy2(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'server': server,
      'server_port': port,
      'password': (proxy['password'] ?? proxy['auth'] ?? '').toString(),
      'tls': {
        'enabled': true,
        'server_name': (proxy['sni'] ?? server).toString(),
        'insecure': proxy['skip-cert-verify'] == true,
        'alpn': ['h3'],
      },
    };
    final obfs = proxy['obfs'];
    if (obfs is String && obfs.isNotEmpty) {
      outbound['obfs'] = {
        'type': obfs,
        'password': (proxy['obfs-password'] ?? '').toString(),
      };
    } else if (obfs is Map) {
      outbound['obfs'] = {
        'type': (obfs['type'] ?? 'salamander').toString(),
        'password': (obfs['password'] ?? '').toString(),
      };
    }
    return outbound;
  }

  static Map<String, dynamic> _tuic(
    Map<String, dynamic> proxy,
    String server,
    int port,
  ) {
    return {
      'type': 'tuic',
      'server': server,
      'server_port': port,
      'uuid': (proxy['uuid'] ?? '').toString(),
      'password': (proxy['password'] ?? '').toString(),
      'congestion_control':
          (proxy['congestion-controller'] ?? proxy['congestion_control'] ?? 'bbr')
              .toString(),
      'udp_relay_mode':
          (proxy['udp-relay-mode'] ?? proxy['udp_relay_mode'] ?? 'native')
              .toString(),
      'tls': {
        'enabled': true,
        'server_name': (proxy['sni'] ?? server).toString(),
        'insecure': proxy['skip-cert-verify'] == true,
        'alpn': (proxy['alpn'] is List)
            ? (proxy['alpn'] as List).map((e) => e.toString()).toList()
            : ['h3'],
      },
    };
  }

  static Map<String, dynamic>? _wg(
    Map<String, dynamic> proxy,
    String server,
    int port, {
    required bool amnezia,
  }) {
    final privateKey =
        (proxy['private-key'] ?? proxy['private_key'] ?? '').toString();
    final publicKey =
        (proxy['public-key'] ?? proxy['public_key'] ?? '').toString();
    if (privateKey.isEmpty || publicKey.isEmpty) return null;
    final ip = (proxy['ip'] ?? proxy['address'] ?? '10.0.0.2/32').toString();
    final amneziaMap = proxy['amnezia'];
    return {
      'type': 'wireguard',
      'tag': 'proxy',
      'mtu': (proxy['mtu'] as num?)?.toInt() ?? 1420,
      'address': ip.split(',').map((e) => e.trim()).toList(),
      'private_key': privateKey,
      'peers': [
        {
          'address': server,
          'port': port,
          'public_key': publicKey,
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          if ((proxy['preshared-key'] ?? '').toString().isNotEmpty)
            'pre_shared_key': proxy['preshared-key'].toString(),
          'persistent_keepalive_interval':
              (proxy['persistent-keepalive'] as num?)?.toInt() ?? 25,
        }
      ],
      if (amnezia || amneziaMap is Map)
        'amnezia': amneziaMap is Map
            ? amneziaMap.map((k, v) => MapEntry(k.toString(), v))
            : {
                'jc': 4,
                'jmin': 40,
                'jmax': 70,
                's1': 0,
                's2': 0,
                'h1': 1,
                'h2': 2,
                'h3': 3,
                'h4': 4,
              },
    };
  }

  static Map<String, dynamic>? _tls(
    Map<String, dynamic> proxy,
    String server, {
    bool defaultOn = false,
  }) {
    final reality = proxy['reality-opts'] ?? proxy['reality-opt'];
    final tlsOn = proxy['tls'] == true || reality != null || defaultOn;
    if (!tlsOn) return null;
    final sni = (proxy['servername'] ?? proxy['sni'] ?? server).toString();
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': sni,
      'insecure': proxy['skip-cert-verify'] == true,
    };
    final alpn = proxy['alpn'];
    if (alpn is List && alpn.isNotEmpty) {
      tls['alpn'] = alpn.map((e) => e.toString()).toList();
    }
    final fp = (proxy['client-fingerprint'] ?? proxy['fingerprint'] ?? '')
        .toString();
    if (fp.isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': fp};
    }
    if (reality is Map) {
      tls['reality'] = {
        'enabled': true,
        'public_key': (reality['public-key'] ?? reality['public_key'] ?? '')
            .toString(),
        'short_id': (reality['short-id'] ?? reality['short_id'] ?? '').toString(),
      };
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, dynamic> proxy) {
    final network = (proxy['network'] ?? 'tcp').toString().toLowerCase();
    if (network == 'tcp' || network == 'raw' || network.isEmpty) return null;
    if (network == 'ws') {
      final opts = proxy['ws-opts'];
      final path = opts is Map ? (opts['path'] ?? '/') : '/';
      final headers = opts is Map ? opts['headers'] : null;
      return {
        'type': 'ws',
        'path': path.toString(),
        if (headers is Map) 'headers': _stringMap(headers),
      };
    }
    if (network == 'grpc') {
      final opts = proxy['grpc-opts'];
      final service = opts is Map
          ? (opts['grpc-service-name'] ?? opts['serviceName'] ?? '')
          : '';
      return {'type': 'grpc', 'service_name': service.toString()};
    }
    if (network == 'h2' || network == 'http') {
      final opts = proxy['h2-opts'] ?? proxy['http-opts'];
      final path = opts is Map ? (opts['path'] ?? '/') : '/';
      final host = opts is Map ? opts['host'] : null;
      return {
        'type': 'http',
        'path': path.toString(),
        'host': host is List
            ? host.map((e) => e.toString()).toList()
            : <String>[],
      };
    }
    return null;
  }

  static ServerDraft _draft(
    String name,
    String address,
    int port,
    String protocol,
    Map<String, dynamic>? outbound, {
    Map<String, dynamic>? endpoint,
  }) {
    final geo = GeoUtils.detect(name);
    return ServerDraft(
      name: name,
      address: address,
      port: port,
      protocol: protocol,
      outbound: outbound,
      endpoint: endpoint,
      countryCode: geo.code,
      tags: geo.tags,
    );
  }

  static Map<String, String> _stringMap(Map source) {
    return {
      for (final entry in source.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static dynamic _toDart(dynamic node) {
    if (node is YamlMap) {
      return {
        for (final entry in node.entries) entry.key.toString(): _toDart(entry.value),
      };
    }
    if (node is YamlList) {
      return [for (final item in node) _toDart(item)];
    }
    if (node is Map) {
      return {
        for (final entry in node.entries) entry.key.toString(): _toDart(entry.value),
      };
    }
    if (node is List) return [for (final item in node) _toDart(item)];
    return node;
  }
}
