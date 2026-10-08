import 'dart:io';

import 'zapret_service.dart';
import 'vpn_platform.dart';

enum DiagSeverity { info, warning, conflict }

/// One observation produced by the system analysis. Everything here is
/// read-only: the wizard turns findings into *proposed* changes and only
/// applies the ones the user keeps checked.
class DiagFinding {
  const DiagFinding({
    required this.id,
    required this.titleKey,
    required this.hintKey,
    this.severity = DiagSeverity.warning,
    this.fixable = false,
  });

  final String id;
  final String titleKey;
  final String hintKey;
  final DiagSeverity severity;

  /// A safe, reversible remedy exists (app settings or an opt-in system fix).
  final bool fixable;
}

/// Full-system analysis used by the auto-setup wizard: which VPN components
/// are present, what competes with Nukefy for the TUN/device, and which
/// system switches intercept traffic before the tunnel.
class SystemDiagnosticService {
  static const List<String> _warpServices = ['warp_svc', 'warp-svc', 'CloudflareWARP'];

  Future<List<DiagFinding>> analyze() async {
    final findings = <DiagFinding>[];
    if (Platform.isWindows) {
      if (await _warpPresent()) {
        findings.add(const DiagFinding(
          id: 'warp',
          titleKey: 'diagWarp',
          hintKey: 'diagWarpHint',
          severity: DiagSeverity.conflict,
          fixable: true,
        ));
      }
      if (await _otherTunAdapters()) {
        findings.add(const DiagFinding(
          id: 'tun',
          titleKey: 'diagOtherVpn',
          hintKey: 'diagOtherVpnHint',
          severity: DiagSeverity.conflict,
        ));
      }
      if (await _systemProxyEnabled()) {
        findings.add(const DiagFinding(
          id: 'proxy',
          titleKey: 'diagProxy',
          hintKey: 'diagProxyHint',
          severity: DiagSeverity.warning,
          fixable: true,
        ));
      }
      if (await _staticDns()) {
        findings.add(const DiagFinding(
          id: 'dns',
          titleKey: 'diagDns',
          hintKey: 'diagDnsHint',
          severity: DiagSeverity.info,
        ));
      }
      try {
        await ZapretService.instance.serviceInstalled();
        if (!ZapretService.instance.isRunning) {
          findings.add(const DiagFinding(
            id: 'zapret',
            titleKey: 'diagZapret',
            hintKey: 'diagZapretHint',
            severity: DiagSeverity.info,
          ));
        }
      } catch (_) {}
    }
    return findings;
  }

  Future<bool> _warpPresent() async {
    for (final service in _warpServices) {
      try {
        final result = await Process.run('sc.exe', ['query', service]);
        if (result.exitCode != 1060) return true;
      } catch (_) {}
    }
    try {
      final tasks = await Process.run('tasklist', ['/FI', 'IMAGENAME eq warp-svc.exe', '/NH']);
      if ('${tasks.stdout}'.toLowerCase().contains('warp-svc.exe')) return true;
    } catch (_) {}
    return false;
  }

  Future<bool> _otherTunAdapters() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-NetAdapter | Where-Object Status -eq Up | Select-Object -ExpandProperty InterfaceDescription',
      ]);
      final text = '${result.stdout}'.toLowerCase();
      for (final marker in ['wintun', 'tap-windows', 'wireguard', 'happ', 'tailscale', 'openvpn']) {
        if (text.contains(marker)) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _systemProxyEnabled() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);
      final match = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch('${result.stdout}');
      if (match != null) return int.parse(match.group(1)!, radix: 16) == 1;
    } catch (_) {}
    return false;
  }

  Future<bool> _staticDns() async {
    try {
      final result = await Process.run('netsh', ['interface', 'ip', 'show', 'dns']);
      return '${result.stdout}'.toLowerCase().contains('static');
    } catch (_) {
      return false;
    }
  }

  /// Opt-in, reversible remedy for the system-proxy finding. Delegates to the
  /// service that snapshots the current user's proxy and PAC values first.
  Future<String> disableSystemProxy() => VpnPlatform().disableSystemProxy();
}
