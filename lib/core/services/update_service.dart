import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../utils/version_utils.dart';
import 'vpn_platform.dart';

class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
  });

  final String version;
  final String notes;
  final String htmlUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  bool get hasAsset => assetUrl != null && assetUrl!.isNotEmpty;
}

class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

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
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': AppConstants.userAgent,
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
      return maps.cast<Map<String, dynamic>?>().firstWhere(
            (asset) =>
                nameHas(asset!, '.exe') ||
                (nameHas(asset, 'windows') && nameHas(asset, '.zip')),
            orElse: () => null,
          );
    }
    return maps.isEmpty ? null : maps.first;
  }

  Future<File> download(
    UpdateInfo info, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final url = info.assetUrl;
    if (url == null) throw StateError('no-asset');
    final dir = await getApplicationSupportDirectory();
    final updates = Directory(p.join(dir.path, 'updates'));
    if (!updates.existsSync()) updates.createSync(recursive: true);
    final file = File(p.join(updates.path, info.assetName ?? 'NukefyVPN-update'));
    final started = DateTime.now();
    await _dio.download(
      url,
      file.path,
      options: Options(headers: const {'User-Agent': AppConstants.userAgent}),
      onReceiveProgress: (received, total) {
        onProgress?.call(DownloadProgress(
          received: received,
          total: total > 0 ? total : (info.assetSize ?? total),
          startedAt: started,
        ));
      },
    );
    return file;
  }
}
