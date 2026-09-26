import 'dart:convert';

import '../constants/app_constants.dart';
import 'base64_utils.dart';
import 'clash_parser.dart';
import 'geo_utils.dart';

class ServerDraft {
  ServerDraft({
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    this.rawLink,
    this.outbound,
    this.endpoint,
    this.countryCode,
    this.tags = const [],
  });

  final String name;
  final String address;
  final int port;
  final String protocol;
  final String? rawLink;
  final Map<String, dynamic>? outbound;
  final Map<String, dynamic>? endpoint;
  final String? countryCode;
  final List<String> tags;
}

class ParsedImport {
  ParsedImport({
    this.servers = const [],
    this.subscriptionUrls = const [],
    this.warnings = const [],
    this.kind = 'empty',
  });

  final List<ServerDraft> servers;
  final List<String> subscriptionUrls;
  final List<String> warnings;
  final String kind;

  bool get isEmpty => servers.isEmpty && subscriptionUrls.isEmpty;
}

class LinkParser {
  static const _shareSchemes = {
    'vless',
    'vmess',
    'trojan',
    'ss',
    'shadowsocks',
    'hysteria',
    'hysteria2',
    'hy2',
    'tuic',
    'wg',
    'wireguard',
    'awg',
    'amneziawg',
  };

  static ParsedImport parseInput(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) {
      return ParsedImport(warnings: const ['empty']);
    }
    if (text.startsWith('<') && text.toLowerCase().contains('<html')) {
      return ParsedImport(warnings: const ['html']);
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      final jsonParsed = _parseJson(text);
      if (jsonParsed != null && !jsonParsed.isEmpty) return jsonParsed;
    }

    if (text.contains('[Interface]') && text.contains('[Peer]')) {
      final wg = _parseWireGuardConf(text);
      if (wg != null) {
        return ParsedImport(servers: [wg], kind: 'wireguard-conf');
      }
    }

    if (_looksLikeClash(text)) {
      final clashServers = ClashParser.parse(text);
      if (clashServers.isNotEmpty) {
        return ParsedImport(servers: clashServers, kind: 'clash');
      }
    }

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#') && !e.startsWith('//'))
        .toList();

    if (lines.length == 1 && _isHttpUrl(lines.first) && !_isShare(lines.first)) {
      return ParsedImport(
        subscriptionUrls: [lines.first],
        kind: 'subscription-url',
      );
    }

    final direct = _parseLines(lines);
    if (!direct.isEmpty) return direct;

    final decoded = Base64Utils.tryDecodeUtf8(text);
    if (decoded != null && decoded.trim() != text.trim()) {
      final nested = parseInput(decoded);
      if (!nested.isEmpty) {
        return ParsedImport(
          servers: nested.servers,
          subscriptionUrls: nested.subscriptionUrls,
          warnings: nested.warnings,
          kind: nested.kind == 'empty' ? 'base64' : nested.kind,
        );
      }
    }

    return ParsedImport(warnings: const ['unknown'], kind: 'unknown');
  }

  static ParsedImport parseSubscriptionBody(String body) {
    final text = body.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return ParsedImport(warnings: const ['empty']);
    if (text.startsWith('{') || text.startsWith('[')) {
      final jsonParsed = _parseJson(text);
      if (jsonParsed != null) return jsonParsed;
    }
    if (_looksLikeClash(text)) {
      final clashServers = ClashParser.parse(text);
      if (clashServers.isNotEmpty) {
        return ParsedImport(servers: clashServers, kind: 'clash');
      }
    }
    final decoded = Base64Utils.tryDecodeUtf8(text);
    final source = decoded ?? text;
    if (source.trim().startsWith('{') || source.trim().startsWith('[')) {
      final jsonParsed = _parseJson(source.trim());
      if (jsonParsed != null && !jsonParsed.isEmpty) return jsonParsed;
    }
    if (_looksLikeClash(source)) {
      return ParsedImport(kind: 'clash', warnings: const ['clash']);
    }
    final lines = source
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
    final parsed = _parseLines(lines);
    if (parsed.isEmpty && decoded == null) {
      return ParsedImport(warnings: const ['unknown'], kind: 'unknown');
    }
    return ParsedImport(
      servers: parsed.servers,
      subscriptionUrls: parsed.subscriptionUrls,
      warnings: parsed.warnings,
      kind: decoded != null ? 'base64' : parsed.kind,
    );
  }

  static bool looksLikeClash(String text) => _looksLikeClash(text);

  static ParsedImport _parseLines(List<String> lines) {
    final servers = <ServerDraft>[];
    final subs = <String>[];
    final warnings = <String>[];
    for (final line in lines) {
      if (_isHttpUrl(line) && !_isShare(line)) {
        subs.add(line);
        continue;
      }
      final draft = parseLine(line);
      if (draft != null) {
        servers.add(draft);
      } else if (_isShare(line) || line.contains('://')) {
        warnings.add(line.length > 80 ? '${line.substring(0, 80)}…' : line);
      }
    }
    return ParsedImport(
      servers: servers,
      subscriptionUrls: subs,
      warnings: warnings,
      kind: servers.isNotEmpty ? 'links' : 'empty',
    );
  }

  static ServerDraft? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final scheme = _scheme(trimmed);
    if (scheme == null) return null;
    switch (scheme) {
      case 'vless':
        return _parseVless(trimmed);
      case 'vmess':
        return _parseVmess(trimmed);
      case 'trojan':
        return _parseTrojan(trimmed);
      case 'ss':
      case 'shadowsocks':
        return _parseShadowsocks(trimmed);
      case 'hysteria':
      case 'hysteria2':
      case 'hy2':
        return _parseHysteria2(trimmed);
      case 'tuic':
        return _parseTuic(trimmed);
      case 'wg':
      case 'wireguard':
        return _parseWireGuardUri(trimmed, amnezia: false);
      case 'awg':
      case 'amneziawg':
        return _parseWireGuardUri(trimmed, amnezia: true);
      default:
        return null;
    }
  }

  static ServerDraft? serverFromOutbound(Map<String, dynamic> outbound) {
    final type = (outbound['type'] as String?)?.toLowerCase();
    if (type == null ||
        type == 'direct' ||
        type == 'block' ||
        type == 'dns' ||
        type == 'selector' ||
        type == 'urltest') {
      return null;
    }
    final address = (outbound['server'] as String?) ?? '';
    final port = (outbound['server_port'] as num?)?.toInt() ?? 443;
    if (address.isEmpty) return null;
    final name = (outbound['tag'] as String?) ?? '$type $address';
    final geo = GeoUtils.detect(name);
    final copy = Map<String, dynamic>.from(outbound);
    copy.remove('tag');
    return ServerDraft(
      name: name,
      address: address,
      port: port,
      protocol: type == 'ss' ? 'shadowsocks' : type,
      outbound: copy,
      countryCode: geo.code,
      tags: geo.tags,
    );
  }

  static ServerDraft? serverFromEndpoint(Map<String, dynamic> endpoint) {
    final type = (endpoint['type'] as String?)?.toLowerCase();
    if (type != 'wireguard') return null;
    final peers = endpoint['peers'];
    String address = '';
    var port = 51820;
    if (peers is List && peers.isNotEmpty && peers.first is Map) {
      final peer = Map<String, dynamic>.from(peers.first as Map);
      address = (peer['address'] as String?) ?? '';
      port = (peer['port'] as num?)?.toInt() ?? 51820;
    }
    final name = (endpoint['tag'] as String?) ?? 'WireGuard';
    final geo = GeoUtils.detect(name);
    final amnezia = endpoint['amnezia'] is Map;
    return ServerDraft(
      name: name,
      address: address,
      port: port,
      protocol: amnezia ? 'amneziawg' : 'wireguard',
      endpoint: Map<String, dynamic>.from(endpoint),
      countryCode: geo.code,
      tags: geo.tags,
    );
  }

  static ServerDraft? _parseVless(String line) {
    final uri = _tryUri(line);
    if (uri == null) return null;
    final uuid = _user(uri);
    if (uuid.isEmpty || uri.host.isEmpty) return null;
    final q = uri.queryParameters;
    final name = _name(uri, 'VLESS ${uri.host}');
    final port = uri.hasPort ? uri.port : 443;
    final tls = _tls(q, fallbackSni: uri.host);
    final outbound = <String, dynamic>{
      'type': 'vless',
      'server': uri.host,
      'server_port': port,
      'uuid': uuid,
    };
    final flow = q['flow'];
    if (flow != null && flow.isNotEmpty && flow != 'none') {
      outbound['flow'] = flow;
    }
    final packet = q['packetEncoding'] ?? q['packet_encoding'];
    if (packet != null && packet.isNotEmpty) outbound['packet_encoding'] = packet;
    if (tls != null) outbound['tls'] = tls;
    final transport = _transport(q);
    if (transport != null) outbound['transport'] = transport;
    return _draft(
      name: name,
      address: uri.host,
      port: port,
      protocol: 'vless',
      rawLink: line,
      outbound: outbound,
    );
  }

  static ServerDraft? _parseVmess(String line) {
    final rest = line.substring(line.indexOf('://') + 3);
    if (rest.contains('@')) {
      final uri = _tryUri(line);
      if (uri == null) return null;
      final q = uri.queryParameters;
      final name = _name(uri, 'VMess ${uri.host}');
      final port = uri.hasPort ? uri.port : 443;
      final outbound = <String, dynamic>{
        'type': 'vmess',
        'server': uri.host,
        'server_port': port,
        'uuid': _user(uri),
        'security': q['encryption'] ?? q['scy'] ?? 'auto',
        'alter_id': int.tryParse(q['aid'] ?? '') ?? 0,
      };
      final tls = _tls(q, fallbackSni: uri.host);
      if (tls != null) outbound['tls'] = tls;
      final transport = _transport(q);
      if (transport != null) outbound['transport'] = transport;
      return _draft(
        name: name,
        address: uri.host,
        port: port,
        protocol: 'vmess',
        rawLink: line,
        outbound: outbound,
      );
    }
    final decoded = Base64Utils.tryDecodeUtf8(rest.split('#').first);
    if (decoded == null) return null;
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(decoded) as Map);
    } catch (_) {
      return null;
    }
    final host = (json['add'] ?? json['host'] ?? '').toString();
    final port = int.tryParse('${json['port']}') ?? 443;
    final uuid = (json['id'] ?? '').toString();
    if (host.isEmpty || uuid.isEmpty) return null;
    final name = (json['ps'] ?? json['remark'] ?? 'VMess $host').toString();
    final net = (json['net'] ?? 'tcp').toString();
    final q = <String, String>{
      'type': net,
      'host': (json['host'] ?? '').toString(),
      'path': (json['path'] ?? '').toString(),
      'serviceName': (json['path'] ?? '').toString(),
      'sni': (json['sni'] ?? '').toString(),
      'fp': (json['fp'] ?? '').toString(),
      'alpn': (json['alpn'] ?? '').toString(),
      'security': (json['tls'] ?? '').toString() == 'tls' ? 'tls' : 'none',
      'headerType': (json['type'] ?? '').toString(),
    };
    if ((json['tls'] ?? '').toString() == 'tls' && (q['sni'] ?? '').isEmpty) {
      q['sni'] = q['host']!.isNotEmpty ? q['host']! : host;
    }
    final outbound = <String, dynamic>{
      'type': 'vmess',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'security': (json['scy'] ?? 'auto').toString(),
      'alter_id': int.tryParse('${json['aid']}') ?? 0,
    };
    final tls = _tls(q, fallbackSni: host);
    if (tls != null) outbound['tls'] = tls;
    final transport = _transport(q);
    if (transport != null) outbound['transport'] = transport;
    return _draft(
      name: name,
      address: host,
      port: port,
      protocol: 'vmess',
      rawLink: line,
      outbound: outbound,
    );
  }

  static ServerDraft? _parseTrojan(String line) {
    final uri = _tryUri(line);
    if (uri == null || uri.host.isEmpty) return null;
    final password = _user(uri);
    if (password.isEmpty) return null;
    final q = uri.queryParameters;
    final port = uri.hasPort ? uri.port : 443;
    final name = _name(uri, 'Trojan ${uri.host}');
    final tls = _tls(q, fallbackSni: uri.host, defaultEnabled: true);
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'server': uri.host,
      'server_port': port,
      'password': password,
      if (tls != null) 'tls': tls,
    };
    final transport = _transport(q);
    if (transport != null) outbound['transport'] = transport;
    return _draft(
      name: name,
      address: uri.host,
      port: port,
      protocol: 'trojan',
      rawLink: line,
      outbound: outbound,
    );
  }

  static ServerDraft? _parseShadowsocks(String line) {
    final body = line.substring(line.indexOf('://') + 3);
    final hash = body.lastIndexOf('#');
    final withoutName = hash >= 0 ? body.substring(0, hash) : body;
    final nameRaw = hash >= 0
        ? Uri.decodeComponent(body.substring(hash + 1).replaceAll('+', ' '))
        : '';
    String? method;
    String? password;
    String? host;
    var port = 8388;
    var query = const <String, String>{};

    if (withoutName.contains('@')) {
      final at = withoutName.lastIndexOf('@');
      final user = withoutName.substring(0, at).split('?').first;
      final decodedUser =
          Base64Utils.tryDecodeUtf8(user) ?? Uri.decodeComponent(user);
      final creds = decodedUser.split(':');
      if (creds.length >= 2 && _isSsMethod(creds.first)) {
        method = creds.first;
        password = creds.sublist(1).join(':');
      }
      final parsedHost = _splitHost(withoutName.substring(at + 1));
      host = parsedHost.host;
      port = parsedHost.port ?? 8388;
      query = parsedHost.query;
    } else {
      final decoded = Base64Utils.tryDecodeUtf8(withoutName.split('?').first);
      if (decoded == null || !decoded.contains('@')) return null;
      final at = decoded.lastIndexOf('@');
      final creds = decoded.substring(0, at).split(':');
      if (creds.length < 2) return null;
      method = creds.first;
      password = creds.sublist(1).join(':');
      final parsedHost = _splitHost(decoded.substring(at + 1));
      host = parsedHost.host;
      port = parsedHost.port ?? 8388;
      query = parsedHost.query;
    }
    if (method == null || password == null || host == null || host.isEmpty) {
      return null;
    }
    final outbound = <String, dynamic>{
      'type': 'shadowsocks',
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
    };
    final plugin = query['plugin'];
    if (plugin != null && plugin.contains('websocket')) {
      final map = <String, String>{};
      for (final part in plugin.split(';')) {
        final kv = part.split('=');
        if (kv.length == 2) map[kv[0]] = kv[1];
      }
      outbound['transport'] = {
        'type': 'ws',
        'path': map['path'] ?? '/',
        if ((map['host'] ?? '').isNotEmpty) 'headers': {'Host': map['host']},
      };
    }
    return _draft(
      name: nameRaw.isEmpty ? 'SS $host' : nameRaw,
      address: host,
      port: port,
      protocol: 'shadowsocks',
      rawLink: line,
      outbound: outbound,
    );
  }

  static bool _isSsMethod(String value) {
    return RegExp(
      r'^(aes|chacha|xchacha|2022-blake3|rc4|none|plain)',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static ServerDraft? _parseHysteria2(String line) {
    final uri = _tryUri(line);
    if (uri == null || uri.host.isEmpty) return null;
    final q = uri.queryParameters;
    final port = uri.hasPort ? uri.port : 443;
    final name = _name(uri, 'Hysteria2 ${uri.host}');
    final password = _user(uri);
    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'server': uri.host,
      'server_port': port,
      'password': password,
      'tls': {
        'enabled': true,
        'server_name': (q['sni'] ?? q['peer'] ?? uri.host),
        'insecure': _truthy(q['insecure'] ?? q['allowInsecure']),
        if ((q['alpn'] ?? '').isNotEmpty)
          'alpn': q['alpn']!.split(',').where((e) => e.isNotEmpty).toList()
        else
          'alpn': ['h3'],
      },
    };
    final obfs = q['obfs'] ?? q['obfs-type'];
    if (obfs != null && obfs.isNotEmpty) {
      outbound['obfs'] = {
        'type': obfs,
        'password': q['obfs-password'] ?? q['obfsPassword'] ?? '',
      };
    }
    return _draft(
      name: name,
      address: uri.host,
      port: port,
      protocol: 'hysteria2',
      rawLink: line,
      outbound: outbound,
    );
  }

  static ServerDraft? _parseTuic(String line) {
    final uri = _tryUri(line);
    if (uri == null || uri.host.isEmpty) return null;
    final user = _user(uri);
    final split = user.split(':');
    if (split.length < 2) return null;
    final uuid = split.first;
    final password = split.sublist(1).join(':');
    final q = uri.queryParameters;
    final port = uri.hasPort ? uri.port : 443;
    final name = _name(uri, 'TUIC ${uri.host}');
    final outbound = <String, dynamic>{
      'type': 'tuic',
      'server': uri.host,
      'server_port': port,
      'uuid': uuid,
      'password': password,
      'congestion_control': q['congestion_control'] ?? 'bbr',
      'udp_relay_mode': q['udp_relay_mode'] ?? 'native',
      'tls': {
        'enabled': true,
        'server_name': q['sni'] ?? uri.host,
        'insecure': _truthy(q['allow_insecure'] ?? q['insecure']),
        'alpn': (q['alpn'] ?? 'h3')
            .split(',')
            .where((e) => e.isNotEmpty)
            .toList(),
      },
    };
    return _draft(
      name: name,
      address: uri.host,
      port: port,
      protocol: 'tuic',
      rawLink: line,
      outbound: outbound,
    );
  }

  static ServerDraft? _parseWireGuardUri(String line, {required bool amnezia}) {
    final uri = _tryUri(line);
    if (uri == null) {
      final decoded = Base64Utils.tryDecodeUtf8(
        line.substring(line.indexOf('://') + 3).split('#').first,
      );
      if (decoded != null && decoded.trim().startsWith('{')) {
        try {
          final json = Map<String, dynamic>.from(jsonDecode(decoded) as Map);
          return serverFromEndpoint(json) ??
              _endpointFromFlat(json, amnezia: amnezia, rawLink: line);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    final q = uri.queryParameters;
    final privateKey = _user(uri).isNotEmpty
        ? _user(uri)
        : (q['privatekey'] ?? q['private_key'] ?? '');
    final publicKey =
        q['publickey'] ?? q['public_key'] ?? q['peer_public_key'] ?? '';
    if (uri.host.isEmpty || privateKey.isEmpty || publicKey.isEmpty) return null;
    final port = uri.hasPort ? uri.port : 51820;
    final address = q['address'] ?? q['local_address'] ?? '10.0.0.2/32';
    final name = _name(uri, amnezia ? 'AmneziaWG ${uri.host}' : 'WireGuard ${uri.host}');
    final endpoint = _wgEndpoint(
      name: name,
      server: uri.host,
      port: port,
      privateKey: privateKey,
      publicKey: publicKey,
      address: address,
      mtu: int.tryParse(q['mtu'] ?? '') ?? 1420,
      preshared: q['presharedkey'] ?? q['psk'],
      keepalive: int.tryParse(q['keepalive'] ?? q['persistent_keepalive'] ?? ''),
      amnezia: amnezia ? _amneziaFromQuery(q) : null,
    );
    return _draft(
      name: name,
      address: uri.host,
      port: port,
      protocol: amnezia ? 'amneziawg' : 'wireguard',
      rawLink: line,
      endpoint: endpoint,
    );
  }

  static ServerDraft? _parseWireGuardConf(String text) {
    final sections = <String, Map<String, String>>{};
    String? current;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = line.substring(1, line.length - 1).toLowerCase();
        sections.putIfAbsent(current, () => {});
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0 || current == null) continue;
      sections[current]![line.substring(0, eq).trim().toLowerCase()] =
          line.substring(eq + 1).trim();
    }
    final iface = sections['interface'];
    final peer = sections['peer'];
    if (iface == null || peer == null) return null;
    final endpoint = peer['endpoint'] ?? '';
    final hostPort = _splitHost(endpoint);
    final privateKey = iface['privatekey'] ?? '';
    final publicKey = peer['publickey'] ?? '';
    if (hostPort.host == null || privateKey.isEmpty || publicKey.isEmpty) {
      return null;
    }
    final amnezia = iface.containsKey('jc') ||
        iface.containsKey('jmin') ||
        peer.containsKey('jc');
    final name =
        amnezia ? 'AmneziaWG ${hostPort.host}' : 'WireGuard ${hostPort.host}';
    return _draft(
      name: name,
      address: hostPort.host!,
      port: hostPort.port ?? 51820,
      protocol: amnezia ? 'amneziawg' : 'wireguard',
      endpoint: _wgEndpoint(
        name: name,
        server: hostPort.host!,
        port: hostPort.port ?? 51820,
        privateKey: privateKey,
        publicKey: publicKey,
        address: (iface['address'] ?? '10.0.0.2/32').split(',').first.trim(),
        mtu: int.tryParse(iface['mtu'] ?? '') ?? 1420,
        preshared: peer['presharedkey'],
        keepalive: int.tryParse(peer['persistentkeepalive'] ?? ''),
        amnezia: amnezia ? _amneziaFromQuery(iface) : null,
      ),
    );
  }

  static ParsedImport? _parseJson(String text) {
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is List) {
      final servers = <ServerDraft>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.map((k, v) => MapEntry(k.toString(), v));
        if (map.containsKey('method') && map.containsKey('server')) {
          servers.add(_sip008(map));
          continue;
        }
        final outbound = serverFromOutbound(map);
        if (outbound != null) servers.add(outbound);
        final endpoint = serverFromEndpoint(map);
        if (endpoint != null) servers.add(endpoint);
      }
      if (servers.isEmpty) return null;
      return ParsedImport(servers: servers, kind: 'json-list');
    }
    if (decoded is! Map) return null;
    final map = decoded.map((k, v) => MapEntry(k.toString(), v));
    if (map['containers'] is List || map['awg'] is Map || map['last_config'] != null) {
      final awg = _parseAmneziaExport(map);
      if (awg != null) return ParsedImport(servers: awg, kind: 'amnezia');
    }
    if (map['servers'] is List &&
        ((map['servers'] as List).isNotEmpty) &&
        (map['servers'] as List).first is Map &&
        ((map['servers'] as List).first as Map).containsKey('method')) {
      final servers = <ServerDraft>[];
      for (final item in map['servers'] as List) {
        if (item is Map) {
          servers.add(_sip008(item.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
      return ParsedImport(servers: servers, kind: 'sip008');
    }
    final servers = <ServerDraft>[];
    if (map['outbounds'] is List) {
      for (final item in map['outbounds'] as List) {
        if (item is! Map) continue;
        final draft = serverFromOutbound(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (draft != null) servers.add(draft);
      }
    }
    if (map['endpoints'] is List) {
      for (final item in map['endpoints'] as List) {
        if (item is! Map) continue;
        final draft = serverFromEndpoint(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (draft != null) servers.add(draft);
      }
    }
    if (servers.isEmpty && map['type'] is String) {
      final one = serverFromOutbound(map) ?? serverFromEndpoint(map);
      if (one != null) servers.add(one);
    }
    if (servers.isEmpty) return null;
    return ParsedImport(servers: servers, kind: 'sing-box');
  }

  static List<ServerDraft>? _parseAmneziaExport(Map<String, dynamic> map) {
    final blobs = <String>[];
    void walk(dynamic node) {
      if (node is Map) {
        final m = node.map((k, v) => MapEntry(k.toString(), v));
        final last = m['last_config'];
        if (last is String && last.contains('[')) blobs.add(last);
        if (last is Map) {
          final encoded = jsonEncode(last);
          blobs.add(encoded);
        }
        for (final value in m.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      } else if (node is String && node.contains('[Interface]')) {
        blobs.add(node);
      }
    }

    walk(map);
    final servers = <ServerDraft>[];
    for (final blob in blobs) {
      if (blob.contains('[Interface]')) {
        final draft = _parseWireGuardConf(blob);
        if (draft != null) servers.add(draft);
      }
    }
    if (map['client_priv_key'] != null || map['client_private_key'] != null) {
      final draft = _endpointFromFlat(map, amnezia: true, rawLink: null);
      if (draft != null) servers.add(draft);
    }
    return servers.isEmpty ? null : servers;
  }

  static ServerDraft _sip008(Map<String, dynamic> map) {
    final host = (map['server'] ?? '').toString();
    final port = (map['server_port'] as num?)?.toInt() ??
        int.tryParse('${map['server_port']}') ??
        8388;
    final name = (map['remarks'] ?? map['name'] ?? 'SS $host').toString();
    return _draft(
      name: name,
      address: host,
      port: port,
      protocol: 'shadowsocks',
      outbound: {
        'type': 'shadowsocks',
        'server': host,
        'server_port': port,
        'method': (map['method'] ?? 'chacha20-ietf-poly1305').toString(),
        'password': (map['password'] ?? '').toString(),
      },
    );
  }

  static ServerDraft? _endpointFromFlat(
    Map<String, dynamic> json, {
    required bool amnezia,
    String? rawLink,
  }) {
    final server = (json['hostName'] ?? json['server'] ?? json['endpoint'] ?? '')
        .toString();
    final port = (json['port'] as num?)?.toInt() ??
        int.tryParse('${json['port']}') ??
        51820;
    final privateKey =
        (json['client_priv_key'] ?? json['private_key'] ?? json['privateKey'] ?? '')
            .toString();
    final publicKey =
        (json['server_pub_key'] ?? json['public_key'] ?? json['publicKey'] ?? '')
            .toString();
    if (server.isEmpty || privateKey.isEmpty || publicKey.isEmpty) return null;
    final host = server.contains(':') ? server.split(':').first : server;
    final name = (json['description'] ?? json['name'] ?? 'AmneziaWG $host').toString();
    return _draft(
      name: name,
      address: host,
      port: port,
      protocol: 'amneziawg',
      rawLink: rawLink,
      endpoint: _wgEndpoint(
        name: name,
        server: host,
        port: port,
        privateKey: privateKey,
        publicKey: publicKey,
        address: (json['client_ip'] ?? json['address'] ?? '10.8.1.2/32').toString(),
        mtu: (json['mtu'] as num?)?.toInt() ?? 1420,
        amnezia: _amneziaFromQuery(_lowerKeys(json)),
      ),
    );
  }

  static Map<String, dynamic> _wgEndpoint({
    required String name,
    required String server,
    required int port,
    required String privateKey,
    required String publicKey,
    required String address,
    required int mtu,
    String? preshared,
    int? keepalive,
    Map<String, dynamic>? amnezia,
  }) {
    final addresses = address
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return {
      'type': 'wireguard',
      'tag': 'proxy',
      'mtu': mtu,
      'address': addresses.isEmpty ? ['10.0.0.2/32'] : addresses,
      'private_key': privateKey,
      'peers': [
        {
          'address': server,
          'port': port,
          'public_key': publicKey,
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          if (preshared != null && preshared.isNotEmpty) 'pre_shared_key': preshared,
          'persistent_keepalive_interval': keepalive ?? 25,
        }
      ],
      if (amnezia != null) 'amnezia': amnezia,
    };
  }

  static Map<String, dynamic>? _amneziaFromQuery(Map<String, String> q) {
    int? pick(List<String> keys) {
      for (final key in keys) {
        final value = int.tryParse(q[key] ?? '');
        if (value != null) return value;
      }
      return null;
    }

    final jc = pick(['jc']);
    final jmin = pick(['jmin']);
    final jmax = pick(['jmax']);
    if (jc == null && jmin == null && jmax == null && pick(['h1']) == null) {
      return null;
    }
    return {
      'jc': jc ?? 4,
      'jmin': jmin ?? 40,
      'jmax': jmax ?? 70,
      's1': pick(['s1']) ?? 0,
      's2': pick(['s2']) ?? 0,
      'h1': pick(['h1']) ?? 1,
      'h2': pick(['h2']) ?? 2,
      'h3': pick(['h3']) ?? 3,
      'h4': pick(['h4']) ?? 4,
    };
  }

  static Map<String, dynamic>? _tls(
    Map<String, String> q, {
    required String fallbackSni,
    bool defaultEnabled = false,
  }) {
    final security = (q['security'] ?? q['tls'] ?? '').toLowerCase();
    final reality = security == 'reality' || (q['pbk'] ?? '').isNotEmpty;
    final enabled = defaultEnabled ||
        reality ||
        security == 'tls' ||
        security == 'true' ||
        (q['sni'] ?? '').isNotEmpty;
    if (!enabled || security == 'none' || security == '0') return null;
    final sni = (q['sni'] ?? q['peer'] ?? q['servername'] ?? '').trim();
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': sni.isEmpty ? fallbackSni : sni,
      'insecure': _truthy(q['insecure'] ?? q['allowInsecure'] ?? q['allow_insecure']),
    };
    final alpn = q['alpn'];
    if (alpn != null && alpn.isNotEmpty) {
      tls['alpn'] = alpn.split(',').where((e) => e.isNotEmpty).toList();
    }
    final fp = q['fp'] ?? q['fingerprint'];
    if (fp != null && fp.isNotEmpty && fp != 'none') {
      tls['utls'] = {'enabled': true, 'fingerprint': fp};
    } else if (reality) {
      // sing-box refuses Reality without uTLS; links often omit `fp`.
      tls['utls'] = {'enabled': true, 'fingerprint': 'chrome'};
    }
    if (reality) {
      tls['reality'] = {
        'enabled': true,
        'public_key': q['pbk'] ?? q['publicKey'] ?? '',
        'short_id': q['sid'] ?? q['shortId'] ?? '',
      };
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    final type = (q['type'] ?? q['network'] ?? 'tcp').toLowerCase();
    if (type.isEmpty || type == 'tcp' || type == 'raw' || type == 'none') {
      return null;
    }
    switch (type) {
      case 'ws':
      case 'websocket':
        final host = q['host'] ?? '';
        return {
          'type': 'ws',
          'path': _path(q['path']),
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': q['serviceName'] ?? q['service_name'] ?? q['path'] ?? '',
        };
      case 'http':
      case 'h2':
        final host = q['host'] ?? '';
        return {
          'type': 'http',
          'host': host.isEmpty ? <String>[] : host.split(','),
          'path': _path(q['path']),
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'host': q['host'] ?? '',
          'path': _path(q['path']),
        };
      case 'quic':
        return {'type': 'quic'};
      case 'xhttp':
      case 'splithttp':
        // Not implemented by sing-box. Emit the type as-is so the core fails
        // loudly at config check instead of silently speaking plain TCP to an
        // XHTTP server ("connected" with no traffic).
        return {'type': type, 'path': _path(q['path'])};
      default:
        return null;
    }
  }

  static String _path(String? path) {
    if (path == null || path.isEmpty) return '/';
    return Uri.decodeComponent(path);
  }

  static ServerDraft _draft({
    required String name,
    required String address,
    required int port,
    required String protocol,
    String? rawLink,
    Map<String, dynamic>? outbound,
    Map<String, dynamic>? endpoint,
  }) {
    final geo = GeoUtils.detect(name);
    return ServerDraft(
      name: name,
      address: address,
      port: port,
      protocol: protocol,
      rawLink: rawLink,
      outbound: outbound,
      endpoint: endpoint,
      countryCode: geo.code,
      tags: geo.tags,
    );
  }

  static String _name(Uri uri, String fallback) {
    if (uri.fragment.isEmpty) return fallback;
    return Uri.decodeComponent(uri.fragment.replaceAll('+', ' '));
  }

  static String _user(Uri uri) => Uri.decodeComponent(uri.userInfo);

  static bool _truthy(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  static bool _isHttpUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static bool _isShare(String value) {
    final scheme = _scheme(value);
    return scheme != null && _shareSchemes.contains(scheme);
  }

  static String? _scheme(String value) {
    final index = value.indexOf('://');
    if (index <= 0 || index > 20) return null;
    return value.substring(0, index).toLowerCase();
  }

  static bool _looksLikeClash(String text) {
    final head = text.length > 400 ? text.substring(0, 400) : text;
    return head.contains('proxies:') || head.contains('proxy-groups:');
  }

  static Uri? _tryUri(String line) {
    try {
      return Uri.parse(line);
    } catch (_) {
      return null;
    }
  }

  static ({String? host, int? port, Map<String, String> query}) _splitHost(
    String raw,
  ) {
    var value = raw;
    final qIndex = value.indexOf('?');
    var query = const <String, String>{};
    if (qIndex >= 0) {
      query = Uri.splitQueryString(value.substring(qIndex + 1));
      value = value.substring(0, qIndex);
    }
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) {
        final host = value.substring(1, end);
        final rest = value.substring(end + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
        return (host: host, port: port, query: query);
      }
    }
    final colon = value.lastIndexOf(':');
    if (colon > 0 && !value.substring(colon + 1).contains(']')) {
      return (
        host: value.substring(0, colon),
        port: int.tryParse(value.substring(colon + 1)),
        query: query,
      );
    }
    return (host: value.isEmpty ? null : value, port: null, query: query);
  }

  static Map<String, String> _lowerKeys(Map<String, dynamic> source) {
    return {
      for (final entry in source.entries)
        entry.key.toString().toLowerCase(): entry.value.toString(),
    };
  }
}

/// Exposed for tests and the clash importer.
Map<String, dynamic>? transportFromQuery(Map<String, String> query) =>
    LinkParser._transport(query);

bool isShareScheme(String scheme) =>
    AppConstants.shareSchemes.contains(scheme.toLowerCase());
