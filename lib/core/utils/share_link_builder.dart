import 'dart:convert';

import '../models/server_model.dart';
import 'base64_utils.dart';

class ShareLinkBuilder {
  static String build(ServerModel server) {
    final raw = server.rawLink;
    if (raw != null && raw.contains('://')) return raw;
    if (server.endpoint != null) return _wireguard(server);
    final outbound = server.outbound;
    if (outbound == null) {
      return '${server.protocol}://${server.address}:${server.port}';
    }
    switch (server.protocol) {
      case 'vless':
        return _vless(server, outbound);
      case 'trojan':
        return _trojan(server, outbound);
      case 'vmess':
        return _vmess(server, outbound);
      case 'shadowsocks':
        return _ss(server, outbound);
      case 'hysteria2':
        return _hy2(server, outbound);
      case 'tuic':
        return _tuic(server, outbound);
      default:
        return jsonEncode(outbound);
    }
  }

  static String _vless(ServerModel server, Map<String, dynamic> outbound) {
    final query = <String, String>{
      'encryption': 'none',
      ..._tlsQuery(outbound['tls']),
      ..._transportQuery(outbound['transport']),
    };
    final flow = outbound['flow'];
    if (flow != null && '$flow'.isNotEmpty) query['flow'] = '$flow';
    return _uri(
      scheme: 'vless',
      user: '${outbound['uuid'] ?? ''}',
      host: server.address,
      port: server.port,
      query: query,
      name: server.name,
    );
  }

  static String _trojan(ServerModel server, Map<String, dynamic> outbound) {
    return _uri(
      scheme: 'trojan',
      user: '${outbound['password'] ?? ''}',
      host: server.address,
      port: server.port,
      query: {
        ..._tlsQuery(outbound['tls']),
        ..._transportQuery(outbound['transport']),
      },
      name: server.name,
    );
  }

  static String _vmess(ServerModel server, Map<String, dynamic> outbound) {
    final tls = outbound['tls'];
    final transport = outbound['transport'];
    final json = {
      'v': '2',
      'ps': server.name,
      'add': server.address,
      'port': '${server.port}',
      'id': '${outbound['uuid'] ?? ''}',
      'aid': '${outbound['alter_id'] ?? 0}',
      'scy': '${outbound['security'] ?? 'auto'}',
      'net': transport is Map ? '${transport['type']}' : 'tcp',
      'tls': tls is Map ? 'tls' : '',
      'sni': tls is Map ? '${tls['server_name'] ?? ''}' : '',
    };
    return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';
  }

  static String _ss(ServerModel server, Map<String, dynamic> outbound) {
    final method = '${outbound['method'] ?? 'chacha20-ietf-poly1305'}';
    final password = '${outbound['password'] ?? ''}';
    final user = Base64Utils.encodeUtf8('$method:$password');
    return _uri(
      scheme: 'ss',
      user: user,
      host: server.address,
      port: server.port,
      query: const {},
      name: server.name,
    );
  }

  static String _hy2(ServerModel server, Map<String, dynamic> outbound) {
    final tls = outbound['tls'];
    final obfs = outbound['obfs'];
    return _uri(
      scheme: 'hysteria2',
      user: '${outbound['password'] ?? ''}',
      host: server.address,
      port: server.port,
      query: {
        if (tls is Map && tls['server_name'] != null)
          'sni': '${tls['server_name']}',
        if (tls is Map && tls['insecure'] == true) 'insecure': '1',
        if (obfs is Map) 'obfs': '${obfs['type'] ?? 'salamander'}',
        if (obfs is Map) 'obfs-password': '${obfs['password'] ?? ''}',
      },
      name: server.name,
    );
  }

  static String _tuic(ServerModel server, Map<String, dynamic> outbound) {
    final tls = outbound['tls'];
    return _uri(
      scheme: 'tuic',
      user: '${outbound['uuid'] ?? ''}:${outbound['password'] ?? ''}',
      host: server.address,
      port: server.port,
      query: {
        'congestion_control': '${outbound['congestion_control'] ?? 'bbr'}',
        if (tls is Map && tls['server_name'] != null)
          'sni': '${tls['server_name']}',
      },
      name: server.name,
    );
  }

  static String _wireguard(ServerModel server) {
    final endpoint = server.endpoint ?? const {};
    final peers = endpoint['peers'];
    final peer = peers is List && peers.isNotEmpty && peers.first is Map
        ? Map<String, dynamic>.from(peers.first as Map)
        : const <String, dynamic>{};
    final addresses = endpoint['address'];
    final address = addresses is List && addresses.isNotEmpty
        ? '${addresses.first}'
        : '10.0.0.2/32';
    final amnezia = endpoint['amnezia'] is Map;
    final query = <String, String>{
      'publickey': '${peer['public_key'] ?? ''}',
      'address': address,
      'mtu': '${endpoint['mtu'] ?? 1420}',
    };
    if (amnezia) {
      final a = Map<String, dynamic>.from(endpoint['amnezia'] as Map);
      for (final key in ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']) {
        if (a[key] != null) query[key] = '${a[key]}';
      }
    }
    return _uri(
      scheme: amnezia ? 'awg' : 'wg',
      user: '${endpoint['private_key'] ?? ''}',
      host: server.address,
      port: server.port,
      query: query,
      name: server.name,
    );
  }

  static Map<String, String> _tlsQuery(dynamic tls) {
    if (tls is! Map) return const {};
    final query = <String, String>{'security': 'tls'};
    if (tls['server_name'] != null) query['sni'] = '${tls['server_name']}';
    if (tls['insecure'] == true) query['insecure'] = '1';
    final utls = tls['utls'];
    if (utls is Map && utls['fingerprint'] != null) {
      query['fp'] = '${utls['fingerprint']}';
    }
    final reality = tls['reality'];
    if (reality is Map && reality['enabled'] == true) {
      query['security'] = 'reality';
      query['pbk'] = '${reality['public_key'] ?? ''}';
      query['sid'] = '${reality['short_id'] ?? ''}';
    }
    return query;
  }

  static Map<String, String> _transportQuery(dynamic transport) {
    if (transport is! Map) return {'type': 'tcp'};
    final type = '${transport['type'] ?? 'tcp'}';
    final query = <String, String>{'type': type};
    if (transport['path'] != null) query['path'] = '${transport['path']}';
    if (transport['service_name'] != null) {
      query['serviceName'] = '${transport['service_name']}';
    }
    final headers = transport['headers'];
    if (headers is Map && headers['Host'] != null) {
      query['host'] = '${headers['Host']}';
    }
    return query;
  }

  static String _uri({
    required String scheme,
    required String user,
    required String host,
    required int port,
    required Map<String, String> query,
    required String name,
  }) {
    final hostPart = host.contains(':') ? '[$host]' : host;
    final queryString = query.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final buffer = StringBuffer('$scheme://${Uri.encodeComponent(user)}@$hostPart:$port');
    if (queryString.isNotEmpty) buffer.write('?$queryString');
    buffer.write('#${Uri.encodeComponent(name)}');
    return buffer.toString();
  }
}
