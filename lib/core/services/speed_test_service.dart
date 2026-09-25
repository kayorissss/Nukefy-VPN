import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../constants/app_constants.dart';

class SpeedTestResult {
  SpeedTestResult({
    required this.downloadBps,
    required this.uploadBps,
    required this.bytes,
    required this.elapsed,
  });

  final int downloadBps;
  final int uploadBps;
  final int bytes;
  final Duration elapsed;
}

class SpeedTestService {
  Future<SpeedTestResult> run({
    required int httpPort,
    bool throughProxy = true,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
    ));
    if (throughProxy) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY 127.0.0.1:$httpPort';
          client.connectionTimeout = const Duration(seconds: 15);
          return client;
        },
      );
    }
    final stopwatch = Stopwatch()..start();
    final response = await dio.get<List<int>>(
      AppConstants.speedTestUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    stopwatch.stop();
    final bytes = response.data?.length ?? 0;
    final seconds = stopwatch.elapsedMilliseconds / 1000;
    final down = seconds <= 0 ? 0 : (bytes / seconds).round();
    var up = 0;
    try {
      final payload = List<int>.filled(256 * 1024, 65);
      final upWatch = Stopwatch()..start();
      await dio.post<void>(
        AppConstants.speedTestUploadUrl,
        data: Stream.fromIterable([payload]),
        options: Options(
          headers: {'Content-Length': payload.length},
          contentType: 'application/octet-stream',
        ),
      );
      upWatch.stop();
      final upSeconds = upWatch.elapsedMilliseconds / 1000;
      up = upSeconds <= 0 ? 0 : (payload.length / upSeconds).round();
    } catch (_) {}
    return SpeedTestResult(
      downloadBps: down,
      uploadBps: up,
      bytes: bytes,
      elapsed: stopwatch.elapsed,
    );
  }
}
