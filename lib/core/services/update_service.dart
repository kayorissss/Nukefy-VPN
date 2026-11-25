import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../utils/version_utils.dart';
import 'vpn_platform.dart';

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.code);

  final String code;

  @override
  String toString() => code;
}

class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
    this.assetDigest,
  });

  final String version;
  final String notes;
  final String htmlUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  /// `sha256:<hex>` published by GitHub for this asset, when present.
  final String? assetDigest;

  bool get hasAsset => assetUrl != null && assetUrl!.isNotEmpty;
}

class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;

  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return AppConstants.version;
    }
  }

  Future<UpdateInfo?> check() async {
    final response = await _dio.get<Map<String, dynamic>>(
      AppConstants.releasesApi,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': AppConstants.clientUserAgent,
        },
        validateStatus: (code) => code != null && code < 500,
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode == 404) return null;
    final data = response.data;
    if (data == null) return null;
    final tag = (data['tag_name'] as String?) ?? '';
    if (tag.isEmpty) return null;
    final local = await currentVersion();
    if (!VersionUtils.isNewer(tag, local)) return null;
    final assets = (data['assets'] as List?) ?? const [];
    final asset = _pickAsset(assets);
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: (data['body'] as String?) ?? '',
      htmlUrl: (data['html_url'] as String?) ?? AppConstants.releasesPage,
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: (asset?['size'] as num?)?.toInt(),
      assetDigest: _normalizedDigest(asset?['digest']),
    );
  }

  Map<String, dynamic>? _pickAsset(List assets) {
    final maps = assets.whereType<Map>().map((item) {
      return item.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
    bool nameHas(Map<String, dynamic> asset, String needle) =>
        '${asset['name']}'.toLowerCase().contains(needle);
    if (Platform.isAndroid) {
      return maps.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => nameHas(asset!, '.apk'),
            orElse: () => null,
          );
    }
    if (Platform.isWindows) {
      final list = maps.cast<Map<String, dynamic>?>();
      // The setup asset can replace an installed copy and asks Windows for
      // elevation. It is the only Windows asset that completes the update;
      // the portable exe is for a fresh/manual launch.
      return list.firstWhere(
            (asset) => nameHas(asset!, 'setup') && nameHas(asset, '.exe'),
            orElse: () => list.firstWhere(
              (asset) => nameHas(asset!, '.exe'),
              orElse: () => list.firstWhere(
                (asset) => nameHas(asset!, 'windows') && nameHas(asset, '.zip'),
                orElse: () => null,
              ),
            ),
          );
    }
    return maps.isEmpty ? null : maps.first;
  }

  /// GitHub returns `sha256:<hex>` for new release assets. Anything else is
  /// ignored: a digest we cannot parse must not be treated as verified.
  static String? _normalizedDigest(Object? raw) {
    final value = '${raw ?? ''}';
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(value)) return null;
    return value.substring(7);
  }

  /// Verifies a downloaded file against the release digest.
  ///
  /// The Windows updater runs the downloaded setup with administrator rights,
  /// so an unverified file was the weakest link in an otherwise careful
  /// release pipeline (Android checks the APK signature, every optional
  /// component checks its SHA-256). Releases published before GitHub exposed
  /// asset digests have none, and those are accepted as before.
  Future<void> _verifyIntegrity(File part, String? digest) async {
    if (digest == null) return;
    final actual = await sha256.bind(part.openRead()).first;
    if (actual.toString() == digest) return;
    try {
      await part.delete();
    } catch (_) {}
    throw const UpdateDownloadException('updateIntegrityFailed');
  }

  Future<File> download(
    UpdateInfo info, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final url = info.assetUrl;
    if (url == null) throw const UpdateDownloadException('no-asset');
    final dir = await getApplicationSupportDirectory();
    final updates = Directory(p.join(dir.path, 'updates'));
    if (!updates.existsSync()) updates.createSync(recursive: true);

    // Keep versions separate. A half-written APK must never be mistaken for a
    // complete update, and an interrupted download can be resumed after the
    // app is opened again.
    final name = info.assetName ?? 'NukefyVPN-update';
    final file = File(p.join(updates.path, '${info.version}-$name'));
    final part = File('${file.path}.part');
    final expected = info.assetSize;
    final started = DateTime.now();

    Future<File> finalize() async {
      await _verifyIntegrity(part, info.assetDigest);
      if (file.existsSync()) await file.delete();
      return part.rename(file.path);
    }

    var received = part.existsSync() ? await part.length() : 0;
    if (expected != null && received == expected) {
      return finalize();
    }
    if (expected != null && received > expected) {
      await part.delete();
      received = 0;
    }

    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final headers = <String, String>{
          'User-Agent': AppConstants.clientUserAgent,
          'Accept': 'application/octet-stream',
        };
        if (received > 0) headers['Range'] = 'bytes=$received-';
        final response = await _dio.get<ResponseBody>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
            followRedirects: true,
            validateStatus: (status) => status != null && status >= 200 && status < 400,
          ),
        );
        final body = response.data;
        if (body == null) throw const UpdateDownloadException('updateDownloadFailed');

        // Some mirrors ignore Range and return the complete file. Restarting
        // from zero is safer than appending a second copy of the APK.
        final resumed = received > 0 && response.statusCode == 206;
        if (received > 0 && !resumed) {
          await part.writeAsBytes(const <int>[], flush: true);
          received = 0;
        }
        final contentLength = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
        final total = expected ?? (resumed && contentLength != null ? received + contentLength : contentLength ?? 0);
        final sink = await part.open(mode: resumed ? FileMode.append : FileMode.write);
        try {
          await for (final chunk in body.stream) {
            await sink.writeFrom(chunk);
            received += chunk.length;
            onProgress?.call(DownloadProgress(received: received, total: total, startedAt: started));
          }
        } finally {
          await sink.close();
        }

        if (expected != null && received != expected) {
          throw const UpdateDownloadException('updateDownloadInterrupted');
        }
        if (expected != null && received > expected) {
          throw const UpdateDownloadException('updateDownloadFailed');
        }
        return await finalize();
      } catch (error) {
        lastError = error;
        received = part.existsSync() ? await part.length() : 0;
        if (expected != null && received == expected) {
          return await finalize();
        }
        if (attempt < 4) {
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    // Do not expose Dio's redirect/stream internals in the UI. The partial
    // file remains in place and the next attempt can continue with Range.
    if (lastError is UpdateDownloadException && lastError.code == 'no-asset') {
      throw lastError;
    }
    throw const UpdateDownloadException('updateDownloadNetwork');
  }
}
