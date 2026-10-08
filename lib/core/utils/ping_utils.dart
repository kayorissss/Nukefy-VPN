import 'dart:async';
import 'dart:io';

class PingUtils {
  /// TCP handshake time to `host:port` in milliseconds, `-1` on failure.
  ///
  /// The host is resolved first and IPv4 is tried before IPv6: on Windows
  /// `Socket.connect(hostname)` waits for the AAAA attempt to time out when
  /// there is no IPv6 route, which made every ping look dead.
  static Future<int> tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final candidates = await _resolve(host, timeout);
    if (candidates.isEmpty) return -1;
    for (final address in candidates) {
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(address, port, timeout: timeout);
        stopwatch.stop();
        socket.destroy();
        final ms = stopwatch.elapsedMilliseconds;
        return ms <= 0 ? 1 : ms;
      } catch (_) {
        // try the next address family
      }
    }
    return -1;
  }

  static Future<List<InternetAddress>> _resolve(String host, Duration timeout) async {
    final literal = InternetAddress.tryParse(host.replaceAll(RegExp(r'^\[|\]$'), ''));
    if (literal != null) return [literal];
    try {
      final all = await InternetAddress.lookup(host).timeout(timeout);
      final v4 = all.where((a) => a.type == InternetAddressType.IPv4).take(2);
      final v6 = all.where((a) => a.type == InternetAddressType.IPv6).take(1);
      return [...v4, ...v6];
    } catch (_) {
      return const [];
    }
  }

  /// Median of three samples. A single TCP handshake can be answered by a
  /// nearby CDN edge or arrive right after a retransmit, which produced
  /// numbers that looked fake (1 ms) or random (900 ms). Three samples
  /// discard the outliers and give a value people trust.
  static Future<int> tcpPingMedian(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
    int samples = 3,
  }) async {
    final seen = <int>[];
    for (var i = 0; i < samples; i++) {
      final ms = await tcpPing(host, port, timeout: timeout);
      if (ms < 0) return ms;
      seen.add(ms);
    }
    seen.sort();
    return seen[seen.length ~/ 2];
  }

  static Future<Map<String, int>> pingAll(
    List<({String id, String host, int port})> targets, {
    int concurrency = 16,
    Duration timeout = const Duration(seconds: 3),
    void Function(String id, int ms)? onEach,
  }) async {
    final results = <String, int>{};
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final current = index;
        index++;
        if (current >= targets.length) return;
        final target = targets[current];
        final ms = await tcpPingMedian(target.host, target.port, timeout: timeout);
        results[target.id] = ms;
        onEach?.call(target.id, ms);
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, targets.isEmpty ? 1 : targets.length),
      (_) => worker(),
    );
    await Future.wait(workers);
    return results;
  }
}
