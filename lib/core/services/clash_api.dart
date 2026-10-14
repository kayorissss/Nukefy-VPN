import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

/// Minimal client for the sing-box Clash API (127.0.0.1, local only).
/// Used for *real* through-tunnel delay tests and the live connection list —
/// never for simulated numbers.
class ClashApi {
  ClashApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'http://127.0.0.1:${AppConstants.clashApiPort}',
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 6),
            ));

  final Dio _dio;

  /// Through-tunnel delay of the active proxy, milliseconds.
  /// Returns null when the core does not answer (older core, proxy mode…).
  Future<int?> proxyDelay({
    String tag = 'proxy',
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/proxies/${Uri.encodeComponent(tag)}/delay',
        queryParameters: {'url': url, 'timeout': timeoutMs},
      );
      final delay = (response.data?['delay'] as num?)?.toInt();
      return delay != null && delay > 0 ? delay : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> connections() async {
    final response = await _dio.get<Map<String, dynamic>>('/connections');
    final list = response.data?['connections'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<({int up, int down})?> connectionTotals() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/connections');
      final up = (response.data?['uploadTotal'] as num?)?.toInt();
      final down = (response.data?['downloadTotal'] as num?)?.toInt();
      if (up == null || down == null) return null;
      return (up: up, down: down);
    } catch (_) {
      return null;
    }
  }
}
