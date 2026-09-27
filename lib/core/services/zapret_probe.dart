import 'dart:async';

import 'package:dio/dio.dart';

/// A service that tells whether a zapret strategy actually works.
class ZapretProbeTarget {
  const ZapretProbeTarget({
    required this.id,
    required this.name,
    required this.url,
    this.okCodes = const [200, 204],
  });

  final String id;
  final String name;
  final String url;
  /// Answers that mean "the real service replied". A Russian stub page
  /// answering 403 counts as blocked, not as working.
  final List<int> okCodes;
}

class ZapretProbeResult {
  const ZapretProbeResult({required this.targetId, required this.ok, this.ms, this.statusCode});

  final String targetId;
  final bool ok;
  final int? ms;
  final int? statusCode;
}

/// Live checks used by "Анализ стратегий": the two services people notice
/// first when a DPI is in the way.
class ZapretProbe {
  ZapretProbe._();
  static final ZapretProbe instance = ZapretProbe._();

  static const youtube = ZapretProbeTarget(
    id: 'youtube',
    name: 'YouTube',
    url: 'https://www.youtube.com/generate_204',
    okCodes: [200, 204],
  );

  static const discord = ZapretProbeTarget(
    id: 'discord',
    name: 'Discord',
    url: 'https://discord.com/api/v10/gateway',
    okCodes: [200],
  );

  static const List<ZapretProbeTarget> defaults = [youtube, discord];

  static const _headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  /// Asks every target once. Never throws — a failed request is a result.
  Future<List<ZapretProbeResult>> check({
    List<ZapretProbeTarget> targets = defaults,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      validateStatus: (status) => true,
      headers: _headers,
    ));
    try {
      return await Future.wait(targets.map((target) => _one(dio, target)));
    } finally {
      dio.close(force: true);
    }
  }

  Future<ZapretProbeResult> _one(Dio dio, ZapretProbeTarget target) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<List<int>>(
        target.url,
        options: Options(responseType: ResponseType.bytes),
      );
      sw.stop();
      final code = response.statusCode ?? 0;
      final ok = target.okCodes.contains(code) || (code >= 200 && code < 300);
      return ZapretProbeResult(targetId: target.id, ok: ok, ms: sw.elapsedMilliseconds, statusCode: code);
    } catch (_) {
      sw.stop();
      return ZapretProbeResult(targetId: target.id, ok: false, ms: sw.elapsedMilliseconds);
    }
  }
}
