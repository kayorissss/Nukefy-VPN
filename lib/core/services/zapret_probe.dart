import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class ZapretProbeTarget {
  const ZapretProbeTarget({required this.id, required this.name, required this.url, this.okCodes = const [200, 204]});
  final String id;
  final String name;
  final String url;
  final List<int> okCodes;
}

class ZapretProbeResult {
  const ZapretProbeResult({required this.targetId, required this.ok, this.ms, this.statusCode});
  final String targetId;
  final bool ok;
  final int? ms;
  final int? statusCode;
}

/// Direct HTTPS probes: never use the OS proxy or follow redirects.
/// A game's web domain responding is not proof its multiplayer works.
class ZapretProbe {
  ZapretProbe._();
  static final instance = ZapretProbe._();
  static const youtube = ZapretProbeTarget(id: 'youtube', name: 'YouTube', url: 'https://www.youtube.com/generate_204', okCodes: [204]);
  static const discord = ZapretProbeTarget(id: 'discord', name: 'Discord', url: 'https://discord.com/api/v10/gateway', okCodes: [200]);
  static const defaults = [youtube, discord];

  static bool publicAddress(InternetAddress ip) {
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv6) {
      // Only global unicast. Excludes loopback, ULA, link-local, multicast,
      // IPv4-mapped, NAT64 and documentation addresses.
      return (b[0] & 0xe0) == 0x20 && !(b[0] == 0x20 && b[1] == 1 && b[2] == 0x0d && b[3] == 0xb8);
    }
    return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && (b[1] == 168 || b[1] == 0)) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 198 && (b[1] == 18 || b[1] == 19 || b[1] == 51)) ||
        (b[0] == 203 && b[1] == 0 && b[2] == 113));
  }

  Future<List<ZapretProbeResult>> check({List<ZapretProbeTarget> targets = defaults, CancelToken? cancelToken}) async {
    final results = <ZapretProbeResult>[];
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length && cancelToken?.isCancelled != true) {
        final target = targets[cursor++];
        results.add(await _one(target, cancelToken));
      }
    }
    await Future.wait(List.generate(targets.length.clamp(0, 4), (_) => worker()));
    return results;
  }

  Future<ZapretProbeResult> _one(ZapretProbeTarget target, CancelToken? parent) async {
    final token = CancelToken();
    final deadline = Timer(const Duration(seconds: 5), () => token.cancel('probe deadline'));
    parent?.whenCancel.then((_) => token.cancel('analysis cancelled'));
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5),
      followRedirects: false, validateStatus: (_) => true,
      headers: const {'User-Agent': 'Mozilla/5.0', 'Cache-Control': 'no-cache'},
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        final addresses = await InternetAddress.lookup(uri.host);
        final address = addresses.where(publicAddress).firstOrNull;
        if (address == null) throw const SocketException('No public address');
        // Pin the validated address, avoiding a second DNS resolution.
        return Socket.startConnect(address, uri.port);
      };
      return client;
    });
    final clock = Stopwatch()..start();
    try {
      final response = await dio.get<ResponseBody>(target.url, cancelToken: token, options: Options(responseType: ResponseType.stream));
      await response.data!.stream.listen((_) {}).cancel();
      return ZapretProbeResult(targetId: target.id, ok: target.okCodes.contains(response.statusCode), ms: clock.elapsedMilliseconds, statusCode: response.statusCode);
    } on DioException {
      return ZapretProbeResult(targetId: target.id, ok: false, ms: clock.elapsedMilliseconds);
    } finally {
      deadline.cancel();
      dio.close(force: true);
    }
  }
}
