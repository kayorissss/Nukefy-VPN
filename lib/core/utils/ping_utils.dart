import 'dart:async';
import 'dart:io';

class PingUtils {
  static Future<int> tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      socket.destroy();
      final ms = stopwatch.elapsedMilliseconds;
      return ms <= 0 ? 1 : ms;
    } catch (_) {
      return -1;
    }
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
        final ms = await tcpPing(target.host, target.port, timeout: timeout);
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
