import 'dart:convert';
import 'singbox_config_builder.dart' show LocalPorts;
import 'dart:io';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';

class XrayConfigException implements Exception {
  const XrayConfigException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Builds native Xray JSON for transports that sing-box deliberately does not
/// implement. It is intentionally separate from the sing-box builder: an
/// XHTTP link must never be rewritten as TCP or reported as connected by the
/// wrong core.
class XrayConfigBuilder {
  static bool supports(ServerModel server) {
    if (!server.usesXhttp) return false;
    return const {'vless', 'vmess', 'trojan'}.contains(server.protocol.toLowerCase());
  }

  static String buildJson({
    required ServerModel server,
    required AppSettings settings,
    required String logPath,
    required int inboundPort,
    LocalPorts? ports,
  }) {
    if (!supports(server)) throw const XrayConfigException('XRAY_UNSUPPORTED_PROTOCOL');
    final outbound = server.outbound ?? const <String, dynamic>{};
    final transport = outbound['transport'];
    if (transport is! Map || !const {'xhttp', 'splithttp'}.contains('${transport['type']}'.toLowerCase())) {
      throw const XrayConfigException('XRAY_TRANSPORT_MISSING');
    }
    final listen = settings.allowLan ? '0.0.0.0' : '127.0.0.1';
    final inbounds = <Map<String, dynamic>>[];
    // The SOCKS inbound is internal when the sing-box TUN front-end is
    // active, and becomes the user-facing local proxy otherwise.
    if (settings.tunEnabled || settings.localProxyEnabled) {
      inbounds.add({
        'tag': 'socks-in',
        'listen': listen,
        'port': inboundPort,
        'protocol': 'socks',
        'settings': {'udp': true},
      });
    }
    final httpPort = ports?.http ?? settings.httpPort;
    if (!settings.tunEnabled && settings.localProxyEnabled && httpPort != inboundPort) {
      inbounds.add({
        'tag': 'http-in',
        'listen': listen,
        'port': httpPort,
        'protocol': 'http',
        'settings': {},
      });
    }
    final config = <String, dynamic>{
      'log': {'loglevel': settings.logLevel, 'access': logPath, 'error': logPath},
      'inbounds': inbounds,
      'outbounds': [
        _proxyOutbound(server, outbound, transport),
        {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
        {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {'type': 'field', 'inboundTag': ['socks-in', 'http-in'], 'outboundTag': 'proxy'},
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  /// Optional sing-box front-end for desktop TUN. Xray remains the protocol
  /// core; sing-box only provides the system TUN and forwards packets to the
  /// Xray SOCKS inbound. This avoids falsely calling a local proxy a system
  /// VPN.
  static String buildSingboxFrontendJson({
    required AppSettings settings,
    required int xrayPort,
    required String logPath,
    required String cachePath,
    required bool useTun,
    LocalPorts? ports,
  }) {
    final listen = settings.allowLan ? '0.0.0.0' : '127.0.0.1';
    final httpPort = ports?.http ?? settings.httpPort;
    final inbounds = <Map<String, dynamic>>[];
    if (useTun) {
      inbounds.add({
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'NukefyXray',
        'address': ['172.19.0.1/30'],
        'mtu': settings.mtu,
        'auto_route': true,
        'strict_route': true,
        'stack': settings.tunStack == 'system' || settings.tunStack == 'gvisor' || settings.tunStack == 'mixed' ? settings.tunStack : 'mixed',
      });
    }
    if (settings.localProxyEnabled) {
      inbounds.addAll([
        {'type': 'socks', 'tag': 'socks-in', 'listen': listen, 'listen_port': ports?.socks ?? settings.socksPort},
        {'type': 'http', 'tag': 'http-in', 'listen': listen, 'listen_port': httpPort},
      ]);
    }
    final config = <String, dynamic>{
      'log': {'level': settings.logLevel, 'timestamp': true, 'output': logPath},
      'dns': {'servers': [{'type': 'local', 'tag': 'direct-dns'}], 'final': 'direct-dns'},
      'inbounds': inbounds,
      'outbounds': [
        {'type': 'socks', 'tag': 'xray', 'server': '127.0.0.1', 'server_port': xrayPort},
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
          if (!Platform.isAndroid) {'process_path': [Platform.resolvedExecutable], 'action': 'route', 'outbound': 'direct'},
        ],
        'final': 'xray',
        'auto_detect_interface': useTun,
      },
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:${ports?.clash ?? AppConstants.clashApiPort}', 'secret': ''},
        'cache_file': {'enabled': true, 'path': cachePath},
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _proxyOutbound(
    ServerModel server,
    Map<String, dynamic> source,
    Map<dynamic, dynamic> transport,
  ) {
    final protocol = server.protocol.toLowerCase();
    final stream = _streamSettings(source, transport);
    switch (protocol) {
      case 'vless':
        final uuid = '${source['uuid'] ?? ''}'.trim();
        if (uuid.isEmpty) throw const XrayConfigException('XRAY_VLESS_UUID_MISSING');
        return {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': server.address,
                'port': server.port,
                'users': [
                  {
                    'id': uuid,
                    'encryption': 'none',
                    if ('${source['flow'] ?? ''}'.isNotEmpty) 'flow': source['flow'],
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'vmess':
        final uuid = '${source['uuid'] ?? ''}'.trim();
        if (uuid.isEmpty) throw const XrayConfigException('XRAY_VMESS_UUID_MISSING');
        return {
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': server.address,
                'port': server.port,
                'users': [
                  {
                    'id': uuid,
                    'alterId': (source['alter_id'] as num?)?.toInt() ?? 0,
                    'security': '${source['security'] ?? 'auto'}',
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'trojan':
        final password = '${source['password'] ?? ''}';
        if (password.isEmpty) throw const XrayConfigException('XRAY_TROJAN_PASSWORD_MISSING');
        return {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {'address': server.address, 'port': server.port, 'password': password},
            ],
          },
          'streamSettings': stream,
        };
      default:
        throw const XrayConfigException('XRAY_UNSUPPORTED_PROTOCOL');
    }
  }

  static Map<String, dynamic> _streamSettings(
    Map<String, dynamic> source,
    Map<dynamic, dynamic> transport,
  ) {
    final tls = source['tls'];
    final security = tls is Map && tls['reality'] is Map ? 'reality' : (tls is Map && tls['enabled'] == true ? 'tls' : 'none');
    final rawPath = '${transport['path'] ?? ''}'.trim();
    final stream = <String, dynamic>{
      'network': 'xhttp',
      'security': security,
      'xhttpSettings': {
        'path': rawPath.isEmpty ? '/' : rawPath,
        if ('${transport['host'] ?? ''}'.isNotEmpty) 'host': '${transport['host']}',
        if ('${transport['mode'] ?? ''}'.isNotEmpty) 'mode': '${transport['mode']}',
        if (transport['extra'] is Map) 'extra': transport['extra'],
      },
    };
    if (tls is Map && tls['enabled'] == true) {
      final reality = tls['reality'];
      if (security == 'reality' && reality is Map) {
        stream['realitySettings'] = {
          'serverName': '${tls['server_name'] ?? ''}',
          'publicKey': '${reality['public_key'] ?? ''}',
          'shortId': '${reality['short_id'] ?? ''}',
          'fingerprint': '${(tls['utls'] as Map?)?['fingerprint'] ?? 'chrome'}',
        };
      } else {
        stream['tlsSettings'] = {
          'serverName': '${tls['server_name'] ?? ''}',
          'allowInsecure': tls['insecure'] == true,
          if (tls['alpn'] is List) 'alpn': tls['alpn'],
          if (tls['utls'] is Map) 'fingerprint': '${(tls['utls'] as Map)['fingerprint'] ?? 'chrome'}',
        };
      }
    }
    return stream;
  }
}
