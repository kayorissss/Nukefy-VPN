import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../utils/version_utils.dart';
import 'vpn_platform.dart';
import 'zapret_service.dart';

class ZapretUpdateInfo {
  const ZapretUpdateInfo({required this.version, required this.notes, required this.url, required this.digest, required this.size});
  final String version;
  final String notes;
  final String url;
  final String digest;
  final int size;
}

/// Only official GitHub release assets; SHA-256 checked before extraction.
/// Hash verification detects corruption, not a compromised upstream release.
class ZapretUpdateService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 2),
    sendTimeout: const Duration(seconds: 30),
  ));
  static const repo = 'Flowseal/zapret-discord-youtube';

  Future<ZapretUpdateInfo?> check() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$repo/releases/latest',
      options: Options(headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': AppConstants.userAgent}),
    );
    final data = response.data!;
    final tag = data['tag_name'] as String;
    final local = ZapretService.instance.version;
    if (local != null && !VersionUtils.isNewer(tag, local)) return null;
    final asset = (data['assets'] as List).cast<Map>().where((a) => (a['name'] as String).endsWith('.zip')).first;
    final url = Uri.parse(asset['browser_download_url'] as String);
    if (url.scheme != 'https' || url.host != 'github.com' || !url.path.startsWith('/$repo/releases/download/')) {
      throw const FormatException('Unexpected release URL');
    }
    final digest = asset['digest'] as String?;
    if (digest == null || !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Release has no SHA-256 digest');
    }
    return ZapretUpdateInfo(version: tag, notes: data['body'] as String? ?? '', url: url.toString(), digest: digest.substring(7), size: asset['size'] as int);
  }

  static bool safeArchivePath(String path) {
    final value = path.replaceAll('\\', '/');
    return value.isNotEmpty && !value.startsWith('/') && !value.contains(':') && !value.contains('\u0000') &&
        !value.split('/').any((s) => s == '..' || s == '.' || s.endsWith(' ') || s.endsWith('.'));
  }

  Future<void> install(ZapretUpdateInfo info, void Function(DownloadProgress) progress) async {
    final service = ZapretService.instance;
    final target = service.root;
    if (target == null) throw StateError('zapret-missing');
    if (service.isRunning && service.runningStrategyId == null) throw StateError('Select a strategy before updating an external zapret service');
    final support = await getApplicationSupportDirectory();
    final download = File(p.join(support.path, 'zapret-update.zip'));
    final started = DateTime.now();
    if (info.size > 128 * 1024 * 1024) throw const FormatException('Archive too large');
    await _dio.download(info.url, download.path, onReceiveProgress: (received, total) {
      progress(DownloadProgress(received: received, total: total > 0 ? total : info.size, startedAt: started));
    });
    final hash = await sha256.bind(download.openRead()).first;
    if (hash.toString() != info.digest || await download.length() != info.size) {
      await download.delete();
      throw const FormatException('Archive integrity check failed');
    }
    final stage = await Directory(target.parent.path).createTemp('zapret-stage-');
    final backup = Directory('${stage.path}-previous');
    final wasRunning = service.isRunning;
    final oldId = service.runningStrategyId;
    var swapped = false;
    try {
      final archive = ZipDecoder().decodeBytes(await download.readAsBytes(), verify: true);
      final exe = archive.files.where((f) => f.isFile && f.name.replaceAll('\\', '/').endsWith('bin/winws.exe')).single;
      final prefix = exe.name.replaceAll('\\', '/').replaceFirst(RegExp(r'bin/winws\.exe$'), '');
      var expanded = 0;
      for (final entry in archive.files) {
        final name = entry.name.replaceAll('\\', '/');
        if (!safeArchivePath(name) || (entry.mode & 0xf000) == 0xa000) {
          throw const FormatException('Unsafe archive path');
        }
        if (!entry.isFile || !name.startsWith(prefix)) continue;
        final relative = name.substring(prefix.length);
        if (!(relative.startsWith('bin/') || relative.startsWith('lists/') || relative.startsWith('utils/') || relative == 'service.bat' || RegExp(r'^general[^/]*\.bat$').hasMatch(relative))) continue;
        expanded += entry.size;
        if (expanded > 256 * 1024 * 1024) throw const FormatException('Expanded archive too large');
        final out = File(p.join(stage.path, relative));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>);
      }
      if (!await File(p.join(stage.path, 'bin', 'winws.exe')).exists() || !stage.listSync().whereType<File>().any((f) => p.basename(f.path).startsWith('general'))) {
        throw const FormatException('Incomplete zapret archive');
      }
      // Preserve app/user configuration, games, exclusions and active fakes.
      for (final file in target.listSync(recursive: true, followLinks: false).whereType<File>()) {
        final rel = p.relative(file.path, from: target.path).replaceAll('\\', '/');
        final name = p.basename(rel);
        if ((rel.startsWith('lists/') && (name.contains('-user.') || rel.startsWith('lists/games/') || name.startsWith('ipset-all.txt'))) ||
            rel == 'utils/game_filter.enabled' || rel == 'bin/ACTIVE_DISCORD_UDP.bin' || rel == 'bin/ACTIVE_GAME_UDP.bin') {
          final dest = File(p.join(stage.path, rel));
          await dest.parent.create(recursive: true);
          await file.copy(dest.path);
        }
      }
      final flag = File(p.join(stage.path, 'utils', 'check_updates.enabled'));
      if (service.autoUpdateCheck) {
        await flag.parent.create(recursive: true);
        await flag.writeAsString('ENABLED');
      } else if (await flag.exists()) { await flag.delete(); }
      await File(p.join(stage.path, 'VERSION.txt')).writeAsString(info.version);
      await service.stop();
      await target.rename(backup.path);
      try {
        await stage.rename(target.path);
      } catch (_) {
        await backup.rename(target.path);
        rethrow;
      }
      swapped = true;
      if (wasRunning) {
        final chosen = service.strategies().where((s) => s.id == oldId).firstOrNull;
        if (chosen == null || !await service.start(chosen)) throw StateError('Cannot restore running strategy');
      }
      await backup.delete(recursive: true);
    } catch (_) {
      if (swapped && await backup.exists()) {
        await service.stop();
        await Directory(target.path).delete(recursive: true);
        await backup.rename(target.path);
      }
      if (wasRunning && !service.isRunning) {
        final original = service.strategies().where((s) => s.id == oldId).firstOrNull;
        if (original != null && !await service.start(original)) throw StateError('Update failed; restart failed: ${service.lastError}');
      }
      rethrow;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
      if (await download.exists()) await download.delete();
    }
  }
}
