import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Why a measurement could not be finished. The UI turns these into words,
/// never into a raw Dio stack trace.
class SpeedTestException implements Exception {
  const SpeedTestException(this.code);

  /// no-connection | blocked | server-error | timeout
  final String code;

  @override
  String toString() => 'SpeedTestException($code)';
}

class SpeedTestResult {
  SpeedTestResult({
    required this.downloadBps,
    required this.uploadBps,
    required this.pingMs,
    required this.jitterMs,
    required this.bytes,
    required this.elapsed,
    required this.viaVpn,
    this.server,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final int downloadBps;
  /// `null` when the endpoint refused (or does not offer) an upload test —
  /// the UI shows "—" instead of a fake zero.
  final int? uploadBps;
  final int pingMs;
  final int jitterMs;
  final int bytes;
  final Duration elapsed;
  final bool viaVpn;
  final String? server;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'down': downloadBps,
        'up': uploadBps,
        'ping': pingMs,
        'jitter': jitterMs,
        'bytes': bytes,
        'ms': elapsed.inMilliseconds,
        'vpn': viaVpn,
        if (server != null) 'server': server,
        'at': at.toIso8601String(),
      };

  static SpeedTestResult fromJson(Map<String, dynamic> json) => SpeedTestResult(
        downloadBps: (json['down'] as num?)?.toInt() ?? 0,
        uploadBps: (json['up'] as num?)?.toInt(),
        pingMs: (json['ping'] as num?)?.toInt() ?? 0,
        jitterMs: (json['jitter'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        elapsed: Duration(milliseconds: (json['ms'] as num?)?.toInt() ?? 0),
        viaVpn: json['vpn'] == true,
        server: json['server'] as String?,
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

/// One HTTP request of a measurement: url plus the headers it needs.
class SpeedRequest {
  const SpeedRequest(this.url, {this.headers = const <String, String>{}});
  final String url;
  final Map<String, String> headers;
}

/// A measurement endpoint.
///
/// The app tries them in order: if a network (or a DPI, or a WAF) answers
/// 403 to one of them, the next one is used instead of failing the test.
class SpeedTarget {
  const SpeedTarget({
    required this.id,
    required this.name,
    required this.ping,
    required this.chunk,
    this.uploadUrl,
  });

  final String id;
  final String name;
  final SpeedRequest ping;
  /// Download request for `worker` / `chunk` — size-parameterised or ranged.
  final SpeedRequest Function(int worker, int chunk) chunk;
  final String? uploadUrl;
}

/// Speedtest-style measurement: latency + jitter from tiny requests, a timed
/// download made of several parallel chunk requests and an upload stream.
class SpeedTestService {
  static const _downloadWindow = Duration(seconds: 10);
  static const _uploadWindow = Duration(seconds: 8);
  static const _chunkBytes = 25 * 1024 * 1024;
  static const _workers = 3;
  /// Stops pulling data even on a very fast link — 10 s at 1 Gbit would
  /// otherwise move more than a gigabyte.
  static const _maxDownloadBytes = 400 * 1024 * 1024;

  // Cloudflare answers 403 to non-browser clients (bot fight), so the probe
  // has to look like the page it belongs to: same Origin/Referer, normal UA.
  static const _browser = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  static const _cloudflareHeaders = <String, String>{
    ..._browser,
    'Origin': 'https://speed.cloudflare.com',
    'Referer': 'https://speed.cloudflare.com/',
  };

  static const _ovhHeaders = <String, String>{
    ..._browser,
    'Referer': 'https://proof.ovh.net/',
  };

  static final List<SpeedTarget> targets = [
    SpeedTarget(
      id: 'cloudflare',
      name: 'Cloudflare',
      ping: const SpeedRequest('https://speed.cloudflare.com/__down?bytes=1', headers: _cloudflareHeaders),
      chunk: (worker, chunk) => SpeedRequest(
        'https://speed.cloudflare.com/__down?bytes=$_chunkBytes',
        headers: _cloudflareHeaders,
      ),
      uploadUrl: 'https://speed.cloudflare.com/__up',
    ),
    // Fallback: static files with byte ranges — used when Cloudflare is
    // blocked. Download only, so upload stays unmeasured rather than wrong.
    SpeedTarget(
      id: 'ovh',
      name: 'OVH',
      ping: const SpeedRequest('https://proof.ovh.net/files/1Mb.dat', headers: {..._ovhHeaders, 'Range': 'bytes=0-0'}),
      chunk: (worker, chunk) {
        // Interleaved slices so parallel workers never ask for the same
        // bytes and never run past the end of the file.
        final start = (chunk * _workers + worker) * _chunkBytes;
        return SpeedRequest(
          'https://proof.ovh.net/files/1Gb.dat',
          headers: {..._ovhHeaders, 'Range': 'bytes=$start-${start + _chunkBytes - 1}'},
        );
      },
    ),
  ];

  Dio _client({int? httpProxyPort}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      // Status codes are inspected by hand: a 403 means "try the next
      // endpoint", not "crash with a Dio stack trace".
      validateStatus: (status) => status != null && status >= 0,
    ));
    if (httpProxyPort != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY 127.0.0.1:$httpProxyPort';
          client.connectionTimeout = const Duration(seconds: 10);
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
    SpeedTestException? failure;
    for (final target in targets) {
      try {
        return await _measure(target, httpProxyPort: httpProxyPort, viaVpn: viaVpn, onProgress: onProgress);
      } on SpeedTestException catch (error) {
        failure = error;
        // A dead network will not come back for the second endpoint either.
        if (error.code == 'no-connection') break;
      }
    }
    throw failure ?? const SpeedTestException('no-connection');
  }

  Future<SpeedTestResult> _measure(
    SpeedTarget target, {
    int? httpProxyPort,
    required bool viaVpn,
    void Function(SpeedProgress progress)? onProgress,
  }) async {
    final dio = _client(httpProxyPort: httpProxyPort);
    final total = Stopwatch()..start();

    // 1. Latency: 8 tiny requests, the first one warms the connection.
    final samples = <int>[];
    var refused = 0;
    int? refusedStatus;
    for (var i = 0; i < 8; i++) {
      final sw = Stopwatch()..start();
      try {
        final response = await dio.get<List<int>>(
          target.ping.url,
          options: Options(responseType: ResponseType.bytes, headers: target.ping.headers),
        );
        sw.stop();
        if (_isError(response.statusCode)) {
          refused++;
          refusedStatus = response.statusCode;
        } else if (i > 0) {
          samples.add(sw.elapsedMilliseconds);
        }
      } catch (_) {
        sw.stop();
      }
      if (samples.isEmpty && refused >= 3) {
        throw SpeedTestException(_codeFor(refusedStatus));
      }
      onProgress?.call(SpeedProgress(SpeedPhase.ping, 0, pingMs: samples.isEmpty ? null : _median(samples)));
    }
    if (samples.length < 2) {
      throw SpeedTestException(_codeFor(refusedStatus));
    }
    final ping = _median(samples);
    var jitter = 0;
    var sum = 0;
    for (var i = 1; i < samples.length; i++) {
      sum += (samples[i] - samples[i - 1]).abs();
    }
    jitter = (sum / (samples.length - 1)).round();
    onProgress?.call(SpeedProgress(SpeedPhase.download, 0, pingMs: ping, jitterMs: jitter));

    // 2. Download: several parallel chunk requests until the window closes.
    var downBytes = 0;
    var downRefused = false;
    final token = CancelToken();
    final downWatch = Stopwatch()..start();
    var lastEmit = 0;
    final windowTimer = Timer(_downloadWindow, () {
      if (!token.isCancelled) token.cancel('window');
    });

    void emit() {
      final ms = downWatch.elapsedMilliseconds;
      if (ms - lastEmit < 120) return;
      lastEmit = ms;
      onProgress?.call(SpeedProgress(SpeedPhase.download, _bps(downBytes, ms), pingMs: ping, jitterMs: jitter));
    }

    Future<void> worker(int index) async {
      var chunk = 0;
      while (!token.isCancelled &&
          downWatch.elapsed < _downloadWindow &&
          downBytes < _maxDownloadBytes) {
        final request = target.chunk(index, chunk++);
        try {
          final response = await dio.get<ResponseBody>(
            request.url,
            options: Options(responseType: ResponseType.stream, headers: request.headers),
            cancelToken: token,
          );
          if (_isError(response.statusCode)) {
            downRefused = true;
            break;
          }
          await for (final piece in response.data!.stream) {
            downBytes += piece.length;
            emit();
            if (token.isCancelled) break;
          }
        } on DioException catch (error) {
          if (error.type == DioExceptionType.cancel && token.isCancelled) break;
          // A rejected status is a refusal; a broken pipe mid-stream is not.
          if (downBytes == 0 && error.type == DioExceptionType.badResponse) downRefused = true;
          break;
        } catch (_) {
          break;
        }
      }
    }

    await Future.wait([for (var i = 0; i < _workers; i++) worker(i)]);
    windowTimer.cancel();
    if (!token.isCancelled) token.cancel('done');
    downWatch.stop();
    if (downBytes == 0) {
      throw SpeedTestException(downRefused ? 'blocked' : 'no-connection');
    }
    final down = _bps(downBytes, downWatch.elapsedMilliseconds);
    onProgress?.call(SpeedProgress(SpeedPhase.upload, 0, pingMs: ping, jitterMs: jitter));

    // 3. Upload: push chunks until the window closes (when the endpoint has
    // an upload URL at all).
    int? up;
    var upBytes = 0;
    final uploadUrl = target.uploadUrl;
    if (uploadUrl != null) {
      final upWatch = Stopwatch()..start();
      final body = List<int>.filled(256 * 1024, 65);
      try {
        while (upWatch.elapsed < _uploadWindow) {
          final batch = List.generate(3, (_) {
            return dio
                .post<void>(
              uploadUrl,
              data: Stream.fromIterable(List.generate(4, (_) => body)),
              options: Options(
                responseType: ResponseType.plain,
                headers: {
                  ..._browser,
                  'Content-Type': 'application/octet-stream',
                  'Content-Length': '${body.length * 4}',
                },
              ),
            )
                .then((_) => body.length * 4, onError: (_) => 0);
          });
          final sent = await Future.wait(batch);
          upBytes += sent.fold<int>(0, (a, b) => a + b);
          final ms = upWatch.elapsedMilliseconds;
          onProgress?.call(SpeedProgress(SpeedPhase.upload, _bps(upBytes, ms), pingMs: ping, jitterMs: jitter));
          if (sent.every((b) => b == 0)) break;
        }
      } catch (_) {}
      upWatch.stop();
      if (upBytes > 0) up = _bps(upBytes, upWatch.elapsedMilliseconds);
    }
    total.stop();

    final result = SpeedTestResult(
      downloadBps: down,
      uploadBps: up,
      pingMs: ping,
      jitterMs: jitter,
      bytes: downBytes + upBytes,
      elapsed: total.elapsed,
      viaVpn: viaVpn,
      server: target.name,
    );
    onProgress?.call(SpeedProgress(SpeedPhase.done, down, pingMs: ping, jitterMs: jitter));
    dio.close(force: true);
    return result;
  }

  /// HTTP status → error code words the UI can show.
  static String _codeFor(int? status) {
    if (status == null) return 'no-connection';
    if (status >= 500) return 'server-error';
    return 'blocked';
  }

  static bool _isError(int? status) => status == null || status >= 400;

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
