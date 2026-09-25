import '../constants/app_constants.dart';
import '../utils/ping_utils.dart';

/// What the "Проверить сеть" probe concluded about the current network.
enum NetworkVerdict {
  /// Only Russian hosts answer — the ISP looks like it runs a whitelist.
  whitelists,

  /// Google answers as well, so no interference is visible.
  noJamming,

  /// Nothing answered at all.
  offline,

  /// Something answered, but neither Google nor the Russian hosts.
  partial,
}

String networkVerdictKey(NetworkVerdict verdict) => switch (verdict) {
      NetworkVerdict.whitelists => 'verdictWhitelists',
      NetworkVerdict.noJamming => 'verdictNoJamming',
      NetworkVerdict.offline => 'verdictOffline',
      NetworkVerdict.partial => 'verdictPartial',
    };

String networkVerdictHintKey(NetworkVerdict verdict) => switch (verdict) {
      NetworkVerdict.whitelists => 'verdictWhitelistsHint',
      NetworkVerdict.noJamming => 'verdictNoJammingHint',
      NetworkVerdict.offline => 'verdictOfflineHint',
      NetworkVerdict.partial => 'verdictPartialHint',
    };

/// Result of one "Проверить сеть" run. `latencies` maps a host to the
/// measured milliseconds, or `-1` when the host did not answer.
class NetworkCheckResult {
  NetworkCheckResult({required this.latencies});

  final Map<String, int> latencies;

  int latencyOf(String host) => latencies[host] ?? -1;

  bool reachable(String host) => latencyOf(host) >= 0;

  int get reachableCount => latencies.values.where((value) => value >= 0).length;

  bool get googleReachable => reachable('google.com');

  bool get anyRussianReachable =>
      AppConstants.russianProbeHosts.any(reachable);

  NetworkVerdict get verdict {
    if (latencies.isEmpty || reachableCount == 0) return NetworkVerdict.offline;
    if (googleReachable) return NetworkVerdict.noJamming;
    if (anyRussianReachable) return NetworkVerdict.whitelists;
    return NetworkVerdict.partial;
  }
}

/// Probes a fixed list of hosts on TCP 443 to tell a whitelist apart from a
/// healthy connection. No data is sent anywhere except the hosts themselves.
class NetworkCheckService {
  const NetworkCheckService();

  static List<String> get russianHosts => AppConstants.russianProbeHosts;

  static List<String> get otherHosts => AppConstants.otherProbeHosts;

  Future<NetworkCheckResult> check({
    Duration timeout = const Duration(seconds: 4),
    void Function(String host, int ms)? onHost,
  }) async {
    final hosts = <String>[
      ...AppConstants.russianProbeHosts,
      ...AppConstants.otherProbeHosts,
    ];
    final latencies = <String, int>{for (final host in hosts) host: -1};
    final measured = await PingUtils.pingAll(
      hosts
          .map((host) => (id: host, host: host, port: AppConstants.networkCheckPort))
          .toList(),
      timeout: timeout,
      onEach: (id, ms) {
        latencies[id] = ms;
        onHost?.call(id, ms);
      },
    );
    latencies.addAll(measured);
    return NetworkCheckResult(latencies: latencies);
  }
}
