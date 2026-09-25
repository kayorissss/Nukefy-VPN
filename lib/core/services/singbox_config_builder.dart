import 'dart:convert';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';
import '../models/vpn_status.dart';

class SingboxConfigBuilder {
  static String buildJson({
    required ServerModel server,
    ServerModel? detour,
    required AppSettings settings,
    required String logPath,
    required String cachePath,
    required bool desktopTun,
    required bool forceProxyOnly,
  }) {
    final config = build(
      server: server,
      detour: detour,
      settings: settings,
      logPath: logPath,
      cachePath: cachePath,
      desktopTun: desktopTun,
      forceProxyOnly: forceProxyOnly,
    );
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> build({
    required ServerModel server,
    ServerModel? detour,
    required AppSettings settings,
    required String logPath,
    required String cachePath,
    required bool desktopTun,
    required bool forceProxyOnly,
  }) {
    final useTun = settings.tunEnabled && !forceProxyOnly;
    final proxy = _tagged(_cloneOutbound(server), 'proxy');
    _applyMuxAndFragment(proxy, settings);
    if (detour != null) {
      proxy['detour'] = 'bridge';
    }

    final outbounds = <Map<String, dynamic>>[
      if (!server.isWireGuard) proxy,
      if (detour != null && !detour.isWireGuard)
        _tagged(_cloneOutbound(detour), 'bridge'),
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
    ];

    final endpoints = <Map<String, dynamic>>[];
    if (server.isWireGuard && server.endpoint != null) {
      final endpoint = _clone(server.endpoint!);
      endpoint['tag'] = 'proxy';
      if (detour != null) endpoint['detour'] = 'bridge';
      endpoints.add(endpoint);
    }
    if (detour != null && detour.isWireGuard && detour.endpoint != null) {
      final endpoint = _clone(detour.endpoint!);
      endpoint['tag'] = 'bridge';
      endpoints.add(endpoint);
    }

    final inbounds = <Map<String, dynamic>>[];
    if (useTun) {
      inbounds.add({
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': AppConstants.tunInterface,
        'address': [AppConstants.tunAddress],
        'mtu': settings.mtu,
        'auto_route': true,
        'strict_route': true,
        'stack': _stack(settings.tunStack),
        'sniff': true,
        'sniff_override_destination': true,
        if (settings.perAppMode == PerAppMode.include &&
            settings.perAppPackages.isNotEmpty)
          'include_package': settings.perAppPackages,
        if (settings.perAppMode == PerAppMode.exclude &&
            settings.perAppPackages.isNotEmpty)
          'exclude_package': settings.perAppPackages,
      });
    }
    if (settings.localProxyEnabled) {
      final listen = settings.allowLan ? '0.0.0.0' : '127.0.0.1';
      inbounds.add({
        'type': 'socks',
        'tag': 'socks-in',
        'listen': listen,
        'listen_port': settings.socksPort,
      });
      inbounds.add({
        'type': 'http',
        'tag': 'http-in',
        'listen': listen,
        'listen_port': settings.httpPort,
      });
    }

    final ruleSets = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
    ];

    if (settings.blockAds) {
      ruleSets.add(_remoteSet('geosite-ads', AppConstants.ruleSetAds));
      rules.add({
        'rule_set': 'geosite-ads',
        'action': 'reject',
      });
    }
    if (settings.blockQuic) {
      rules.add({'protocol': 'quic', 'action': 'reject'});
    }
    if (settings.blockIpv6) {
      rules.add({'ip_version': 6, 'action': 'reject'});
    }

    final directDomains = <String>[];
    final proxyDomains = <String>[];
    final blockDomains = <String>[];
    final directIps = <String>[];
    final proxyIps = <String>[];
    for (final rule in settings.rules) {
      final bucket = switch (rule.action) {
        'direct' => rule.kind == 'ip_cidr' ? directIps : directDomains,
        'block' => blockDomains,
        _ => rule.kind == 'ip_cidr' ? proxyIps : proxyDomains,
      };
      if (rule.value.trim().isNotEmpty) bucket.add(rule.value.trim());
    }
    if (blockDomains.isNotEmpty) {
      rules.add({
        'domain_suffix': blockDomains,
        'action': 'reject',
      });
    }

    switch (settings.routingMode) {
      case RoutingMode.global:
        break;
      case RoutingMode.blockedOnly:
        rules.add({
          'domain_suffix': AppConstants.blockedDomainSuffixes,
          'action': 'route',
          'outbound': 'proxy',
        });
        if (proxyDomains.isNotEmpty) {
          rules.add({
            'domain_suffix': proxyDomains,
            'action': 'route',
            'outbound': 'proxy',
          });
        }
        if (proxyIps.isNotEmpty) {
          rules.add({
            'ip_cidr': proxyIps,
            'action': 'route',
            'outbound': 'proxy',
          });
        }
      case RoutingMode.bypassRu:
        ruleSets.add(_remoteSet('geosite-ru', AppConstants.ruleSetGeositeRu));
        ruleSets.add(_remoteSet('geoip-ru', AppConstants.ruleSetGeoipRu));
        rules.add({
          'domain_suffix': ['.ru', '.su', '.рф', ...directDomains],
          'action': 'route',
          'outbound': 'direct',
        });
        rules.add({
          'rule_set': ['geosite-ru', 'geoip-ru'],
          'action': 'route',
          'outbound': 'direct',
        });
      case RoutingMode.custom:
        if (directDomains.isNotEmpty) {
          rules.add({
            'domain_suffix': directDomains,
            'action': 'route',
            'outbound': 'direct',
          });
        }
        if (directIps.isNotEmpty) {
          rules.add({
            'ip_cidr': directIps,
            'action': 'route',
            'outbound': 'direct',
          });
        }
        if (proxyDomains.isNotEmpty) {
          rules.add({
            'domain_suffix': proxyDomains,
            'action': 'route',
            'outbound': 'proxy',
          });
        }
        if (proxyIps.isNotEmpty) {
          rules.add({
            'ip_cidr': proxyIps,
            'action': 'route',
            'outbound': 'proxy',
          });
        }
    }

    final dns = _dns(settings);
    final finalOutbound = settings.routingMode == RoutingMode.blockedOnly
        ? 'direct'
        : 'proxy';

    return {
      'log': {
        'level': settings.logLevel,
        'timestamp': true,
        'output': logPath,
      },
      'dns': dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      if (endpoints.isNotEmpty) 'endpoints': endpoints,
      'route': {
        'rules': rules,
        if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
        'final': finalOutbound,
        'auto_detect_interface': desktopTun && useTun,
        'default_domain_resolver': 'direct-dns',
      },
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:${AppConstants.clashApiPort}',
          'secret': '',
        },
        'cache_file': {
          'enabled': true,
          'path': cachePath,
        },
      },
    };
  }

  static Map<String, dynamic> _dns(AppSettings settings) {
    final proxy = _parseDns(settings.proxyDns, 'proxy-dns', detour: 'proxy');
    final direct = _parseDns(settings.directDns, 'direct-dns');
    final rules = <Map<String, dynamic>>[];
    if (settings.routingMode == RoutingMode.bypassRu ||
        settings.routingMode == RoutingMode.custom) {
      rules.add({
        'domain_suffix': ['.ru', '.su', '.рф'],
        'action': 'route',
        'server': 'direct-dns',
      });
    }
    if (settings.routingMode == RoutingMode.bypassRu) {
      rules.add({
        'rule_set': 'geosite-ru',
        'action': 'route',
        'server': 'direct-dns',
      });
    }
    return {
      'servers': [proxy, direct],
      'rules': rules,
      'final': settings.routingMode == RoutingMode.blockedOnly
          ? 'direct-dns'
          : 'proxy-dns',
      'strategy': settings.blockIpv6 ? 'ipv4_only' : 'prefer_ipv4',
    };
  }

  static Map<String, dynamic> _parseDns(
    String raw,
    String tag, {
    String? detour,
  }) {
    final value = raw.trim();
    if (value.isEmpty || value == 'local' || value == 'system') {
      return {
        'type': 'udp',
        'tag': tag,
        'server': '77.88.8.8',
        if (detour != null) 'detour': detour,
      };
    }
    final uri = Uri.tryParse(value.contains('://') ? value : 'udp://$value');
    final scheme = uri?.scheme.toLowerCase() ?? 'udp';
    final host = (uri?.host.isNotEmpty ?? false) ? uri!.host : value;
    final port = (uri?.hasPort ?? false) ? uri!.port : null;
    switch (scheme) {
      case 'https':
        return {
          'type': 'https',
          'tag': tag,
          'server': host,
          'server_port': port ?? 443,
          'path': (uri?.path.isNotEmpty ?? false) ? uri!.path : '/dns-query',
          if (detour != null) 'detour': detour,
        };
      case 'tls':
      case 'dot':
        return {
          'type': 'tls',
          'tag': tag,
          'server': host,
          'server_port': port ?? 853,
          if (detour != null) 'detour': detour,
        };
      default:
        return {
          'type': 'udp',
          'tag': tag,
          'server': host,
          if (port != null) 'server_port': port,
          if (detour != null) 'detour': detour,
        };
    }
  }

  static Map<String, dynamic> _remoteSet(String tag, String url) {
    return {
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      'url': url,
      'download_detour': 'proxy',
    };
  }

  static Map<String, dynamic> _cloneOutbound(ServerModel server) {
    final source = server.outbound ??
        {
          'type': server.protocol,
          'server': server.address,
          'server_port': server.port,
        };
    return _clone(source);
  }

  static Map<String, dynamic> _tagged(Map<String, dynamic> outbound, String tag) {
    outbound['tag'] = tag;
    outbound.putIfAbsent('server', () => '');
    return outbound;
  }

  static void _applyMuxAndFragment(
    Map<String, dynamic> outbound,
    AppSettings settings,
  ) {
    final tls = outbound['tls'];
    if (tls is Map && (settings.tlsFragment || settings.recordFragment)) {
      final copy = Map<String, dynamic>.from(tls);
      if (settings.tlsFragment) {
        copy['fragment'] = true;
        copy['fragment_fallback_delay'] = '${settings.fragmentFallbackMs}ms';
      }
      if (settings.recordFragment) copy['record_fragment'] = true;
      outbound['tls'] = copy;
    }
    final flow = (outbound['flow'] ?? '').toString();
    final vision = flow.contains('vision');
    final type = (outbound['type'] ?? '').toString();
    final muxSafe = type != 'hysteria2' && type != 'tuic' && type != 'wireguard';
    if (settings.muxEnabled && !vision && muxSafe) {
      outbound['multiplex'] = {
        'enabled': true,
        'protocol': settings.muxProtocol,
        'max_connections': settings.muxMaxConnections.clamp(1, 8),
        'padding': settings.muxPadding,
      };
    }
  }

  static String _stack(String value) {
    switch (value) {
      case 'system':
      case 'gvisor':
      case 'mixed':
        return value;
      default:
        return 'mixed';
    }
  }

  static Map<String, dynamic> _clone(Map<String, dynamic> source) {
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }
}

// Imported for the enum used above without a circular service import.
// ignore: unused_import
import '../models/vpn_status.dart';
