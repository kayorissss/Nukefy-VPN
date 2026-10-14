import 'dart:async';
import 'dart:io';

/// Result of one HTTP probe.
class ProbeResult {
  ProbeResult({required this.ok, this.status, this.ms = 0, this.error});

  final bool ok;
  final int? status;
  final int ms;
  final String? error;
}

/// A named reachability target shown in the analyzer ("YouTube", "Discord"…).
class ProbeTarget {
  const ProbeTarget(this.id, this.label, this.url);

  final String id;
  final String label;
  final String url;
}

/// Tiny HTTP client helper shared by the post-connect traffic check, the
/// analyzer and the best-server scan.
///
/// Every probe can be sent either directly or through the local HTTP inbound
/// of the running tunnel (`PROXY 127.0.0.1:<port>`), which is exactly what the
/// user's browser/machine gets when proxy mode is on. Certificate validation
/// stays strict on purpose: if something in the chain is broken, the probe
/// must fail and be reported, not silently succeed.
class ConnectivityProbe {
  ConnectivityProbe._();

  /// Sites people actually care about. A VPN that says "connected" while
  /// YouTube stays unreachable is the single most common complaint, so the
  /// check answers precisely that question instead of pinging a captive
  /// portal endpoint and declaring victory.
  static const List<ProbeTarget> defaultTargets = [
    ProbeTarget('youtube', 'YouTube', 'https://www.youtube.com/generate_204'),
    ProbeTarget('discord', 'Discord', 'https://discord.com/api/v9/gateway'),
    ProbeTarget('telegram', 'Telegram', 'https://core.telegram.org/'),
  ];

  static Future<ProbeResult> http(
    String url, {
    int? httpProxyPort,
    Duration timeout = const Duration(seconds: 9),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (uri) => httpProxyPort == null ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort';
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      stopwatch.stop();
      final status = response.statusCode;
      return ProbeResult(
        ok: status >= 200 && status < 400,
        status: status,
        ms: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      return ProbeResult(ok: false, ms: stopwatch.elapsedMilliseconds, error: _short(error));
    } finally {
      client.close(force: true);
    }
  }

  /// Reads a small text body (used for public-IP echoes).
  static Future<({String? body, String? error})> text(
    String url, {
    int? httpProxyPort,
    Duration timeout = const Duration(seconds: 9),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (uri) => httpProxyPort == null ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort';
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(const SystemEncoding().decoder).join().timeout(timeout);
      return (body: body.trim(), error: null);
    } catch (error) {
      return (body: null, error: _short(error));
    } finally {
      client.close(force: true);
    }
  }

  static String _short(Object error) {
    final text = '$error'.split('\n').first.trim();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}
