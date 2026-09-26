import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../constants/app_constants.dart';

class SpeedTestResult {
  SpeedTestResult({
    required this.downloadBps,
    required this.uploadBps,
    required this.pingMs,
    required this.jitterMs,
    required this.bytes,
    required this.elapsed,
    required this.viaVpn,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final int downloadBps;
  final int uploadBps;
  final int pingMs;
  final int jitterMs;
  final int bytes;
  final Duration elapsed;
  final bool viaVpn;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'down': downloadBps,
        'up': uploadBps,
        'ping': pingMs,
        'jitter': jitterMs,
        'bytes': bytes,
        'ms': elapsed.inMilliseconds,
        'vpn': viaVpn,
        'at': at.toIso8601String(),
      };

  static SpeedTestResult fromJson(Map<String, dynamic> json) => SpeedTestResult(
        downloadBps: (json['down'] as num?)?.toInt() ?? 0,
        uploadBps: (json['up'] as num?)?.toInt() ?? 0,
        pingMs: (json['ping'] as num?)?.toInt() ?? 0,
        jitterMs: (json['jitter'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        elapsed: Duration(milliseconds: (json['ms'] as num?)?.toInt() ?? 0),
        viaVpn: json['vpn'] == true,
        at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
      );
}

enum SpeedPhase { ping, download, upload, done }

/// Live progress: current phase and the instantaneous value for the gauge.
class SpeedProgress {
  const SpeedProgress(this.phase, this.bps, {this.pingMs, this.jitterMs});
  final SpeedPhase phase;
  final int bps;
  final int? pingMs;
  final int? jitterMs;
}

/// Speedtest-style measurement against Cloudflare's speed endpoints:
/// latency + jitter from several tiny requests, then timed download and
/// upload streams with live progress for the gauge.
class SpeedTestService {
  static const _downUrl = 'https://speed.cloudflare.com/__down?bytes=';
  static const _upUrl = 'https://speed.cloudflare.com/__up';
  static const _downloadWindow = Duration(seconds: 10);
  static const _uploadWindow = Duration(seconds: 8);

  Dio _client({int? httpProxyPort}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': AppConstants.userAgent},
    ));
    if (httpProxyPort != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY 127.0.0.1:$httpProxyPort';
          client.connectionTimeout = const Duration(seconds: 12);
          return client;
        },
      );
    }
    return dio;
  }

  Future<SpeedTestResult> run({
    int? httpProxyPort,
    required bool viaVpn,
    void Function(SpeedProgress progress)? onProgress,
  }) async {
    final dio = _client(httpProxyPort: httpProxyPort);
    final total = Stopwatch()..start();

    // 1. Latency: 8 tiny requests, first one warms the connection.
    final samples = <int>[];
    for (var i = 0; i < 8; i++) {
      final sw = Stopwatch()..start();
      try {
        await dio.get<void>('${_downUrl}0', options: Options(responseType: ResponseType.bytes));
        sw.stop();
        if (i > 0) samples.add(sw.elapsedMilliseconds);
      } catch (_) {
        sw.stop();
      }
      onProgress?.call(SpeedProgress(SpeedPhase.ping, 0, pingMs: samples.isEmpty ? null : _median(samples)));
    }
    if (samples.isEmpty) throw Exception('no-connection');
    final ping = _median(samples);
    var jitter = 0;
    if (samples.length > 1) {
      var sum = 0;
      for (var i = 1; i < samples.length; i++) {
        sum += (samples[i] - samples[i - 1]).abs();
      }
      jitter = (sum / (samples.length - 1)).round();
    }
    onProgress?.call(SpeedProgress(SpeedPhase.download, 0, pingMs: ping, jitterMs: jitter));

    // 2. Download: stream a large body, stop after the window.
    var downBytes = 0;
    final downToken = CancelToken();
    final downWatch = Stopwatch()..start();
    var lastEmit = 0;
    Timer(_downloadWindow, () => downToken.cancel('window'));
    try {
      await dio.get<ResponseBody>(
        '$_downUrl${200 * 1024 * 1024}',
        cancelToken: downToken,
        options: Options(responseType: ResponseType.stream),
      ).then((response) async {
        await for (final chunk in response.data!.stream) {
          downBytes += chunk.length;
          final ms = downWatch.elapsedMilliseconds;
          if (ms - lastEmit >= 120) {
            lastEmit = ms;
            onProgress?.call(SpeedProgress(SpeedPhase.download, _bps(downBytes, ms), pingMs: ping, jitterMs: jitter));
          }
          if (downToken.isCancelled) break;
        }
      });
    } on DioException catch (error) {
      if (error.type != DioExceptionType.cancel && downBytes == 0) rethrow;
    } catch (_) {
      if (downBytes == 0) rethrow;
    }
    downWatch.stop();
    final down = _bps(downBytes, downWatch.elapsedMilliseconds);
    onProgress?.call(SpeedProgress(SpeedPhase.upload, 0, pingMs: ping, jitterMs: jitter));

    // 3. Upload: push chunks until the window closes.
    var upBytes = 0;
    final upWatch = Stopwatch()..start();
    final chunk = List<int>.filled(256 * 1024, 65);
    lastEmit = 0;
    try {
      while (upWatch.elapsed < _uploadWindow) {
        // Several parallel 2 MB posts keep the pipe full without one huge body.
        final batch = List.generate(3, (_) {
          return dio.post<void>(
            _upUrl,
            data: Stream.fromIterable(List.generate(8, (_) => chunk)),
            options: Options(
              headers: {'Content-Length': chunk.length * 8},
              contentType: 'application/octet-stream',
              sendTimeout: const Duration(seconds: 20),
            ),
            onSendProgress: (sent, _) {},
          ).then((_) => chunk.length * 8, onError: (_) => 0);
        });
        final sent = await Future.wait(batch);
        upBytes += sent.fold<int>(0, (a, b) => a + b);
        final ms = upWatch.elapsedMilliseconds;
        onProgress?.call(SpeedProgress(SpeedPhase.upload, _bps(upBytes, ms), pingMs: ping, jitterMs: jitter));
        if (sent.every((b) => b == 0)) break;
      }
    } catch (_) {}
    upWatch.stop();
    final up = _bps(upBytes, upWatch.elapsedMilliseconds);
    total.stop();

    final result = SpeedTestResult(
      downloadBps: down,
      uploadBps: up,
      pingMs: ping,
      jitterMs: jitter,
      bytes: downBytes + upBytes,
      elapsed: total.elapsed,
      viaVpn: viaVpn,
    );
    onProgress?.call(SpeedProgress(SpeedPhase.done, down, pingMs: ping, jitterMs: jitter));
    return result;
  }

  static int _bps(int bytes, int ms) => ms <= 0 ? 0 : (bytes * 1000 / ms).round();

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Mbit/s for display.
  static double mbps(int bps) => bps * 8 / 1e6;

  /// Gauge position 0..1 on a log-ish scale that keeps 1–1000 Mbit readable.
  static double gauge(int bps) {
    final m = mbps(bps);
    if (m <= 0) return 0;
    return (math.log(1 + m) / math.log(1 + 1000)).clamp(0.0, 1.0);
  }
}
