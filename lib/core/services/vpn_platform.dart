import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

class CoreInfo {
  CoreInfo({
    required this.libbox,
    required this.binary,
    this.binaryPath,
    this.version,
  });

  final bool libbox;
  final bool binary;
  final String? binaryPath;
  final String? version;

  bool get available => libbox || binary;
}

class CoreStartResult {
  CoreStartResult({
    required this.ok,
    required this.mode,
    this.error,
  });

  final bool ok;
  final String mode;
  final String? error;
}

/// Failure while fetching or unpacking the sing-box core. [code] is a stable
/// key that the UI maps to a localized message.
class CoreDownloadException implements Exception {
  const CoreDownloadException(this.code);

  final String code;

  @override
  String toString() => code;
}

class DownloadProgress {
  DownloadProgress({
    required this.received,
    required this.total,
    required this.startedAt,
  });

  final int received;
  final int total;
  final DateTime startedAt;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
  int get bps {
    final seconds = DateTime.now().difference(startedAt).inMilliseconds / 1000;
    if (seconds < 0.2) return 0;
    return (received / seconds).round();
  }

  Duration get eta {
    final speed = bps;
    if (speed <= 0 || total <= received) return Duration.zero;
    return Duration(seconds: ((total - received) / speed).round());
  }
}

class VpnPlatform {
  VpnPlatform({Dio? dio}) : _dio = dio ?? Dio();

  static const _channel = MethodChannel('com.nukefy.vpn/core');
  final Dio _dio;
  Process? _process;
  final _log = StringBuffer();

  String get logText => _log.toString();

  void appendLog(String line) {
    _log.writeln(line);
    if (_log.length > 200000) {
      final text = _log.toString();
      _log
        ..clear()
        ..write(text.substring(text.length - 120000));
    }
  }

  Future<Directory> coreDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'core'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static const List<String> bundledRuleSets = [
    'geosite-category-ru.srs',
    'geoip-ru.srs',
    'geosite-category-ads-all.srs',
  ];

  /// Copies the bundled rule sets next to the config and returns the folder.
  Future<Directory> ensureRuleSets() async {
    final dir = Directory(p.join((await configDirectory()).path, 'rules'));
    await dir.create(recursive: true);
    for (final name in bundledRuleSets) {
      final file = File(p.join(dir.path, name));
      final data = await rootBundle.load('assets/rules/$name');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (!file.existsSync() || file.lengthSync() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
    return dir;
  }

  Future<Directory> configDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'run'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String?> binaryPath() async {
    final dir = await coreDirectory();
    final name = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final file = File(p.join(dir.path, name));
    if (file.existsSync()) return file.path;
    return null;
  }

  Future<CoreInfo> coreInfo() async {
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('coreInfo');
        return CoreInfo(
          libbox: raw?['libbox'] == true,
          binary: raw?['binary'] == true,
          binaryPath: raw?['binaryPath'] as String?,
          version: raw?['version'] as String?,
        );
      } catch (error) {
        return CoreInfo(libbox: false, binary: false, version: '$error');
      }
    }
    final path = await binaryPath();
    String? version;
    if (path != null) {
      try {
        final result = await Process.run(path, ['version']);
        version = '${result.stdout}'.trim().split('\n').first;
      } catch (_) {}
    }
    return CoreInfo(
      libbox: false,
      binary: path != null,
      binaryPath: path,
      version: version,
    );
  }

  Future<CoreStartResult> start({
    required String configJson,
    required bool preferTun,
    String serverName = '',
    String serverHost = '',
    int serverPort = 0,
  }) async {
    final dir = await configDirectory();
    final configFile = File(p.join(dir.path, 'config.json'));
    await configFile.writeAsString(configJson);
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('start', {
          'configPath': configFile.path,
          'configJson': configJson,
          'preferTun': preferTun,
          'serverName': serverName,
          'serverHost': serverHost,
          'serverPort': serverPort,
        });
        return CoreStartResult(
          ok: raw?['ok'] == true,
          mode: (raw?['mode'] as String?) ?? 'missing',
          error: raw?['error'] as String?,
        );
      } on PlatformException catch (error) {
        return CoreStartResult(
          ok: false,
          mode: 'missing',
          error: error.message ?? error.code,
        );
      }
    }
    return _startProcess(configFile.path, dir.path);
  }

  Future<CoreStartResult> _startProcess(String configPath, String workDir) async {
    final binary = await binaryPath();
    if (binary == null) {
      return CoreStartResult(
        ok: false,
        mode: 'missing',
        error: 'CORE_MISSING',
      );
    }
    await stop();
    _log.clear();
    try {
      final process = await Process.start(
        binary,
        ['run', '-c', configPath, '-D', workDir],
        workingDirectory: p.dirname(binary),
        mode: ProcessStartMode.normal,
      );
      _process = process;
      process.stdout.transform(utf8.decoder).listen(appendLog);
      process.stderr.transform(utf8.decoder).listen(appendLog);
      process.exitCode.then((code) {
        appendLog('sing-box exited: $code');
        if (identical(_process, process)) _process = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_process == null) {
        return CoreStartResult(
          ok: false,
          mode: 'proxy',
          error: logText.trim().isEmpty ? 'core-exited' : logText.trim(),
        );
      }
      return CoreStartResult(ok: true, mode: 'tun');
    } catch (error) {
      return CoreStartResult(ok: false, mode: 'missing', error: '$error');
    }
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stop');
      } catch (_) {}
      return;
    }
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<bool> isRunning() async {
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('status');
        return raw?['running'] == true;
      } catch (_) {
        return false;
      }
    }
    return _process != null;
  }

  Future<bool> prepareVpn() async {
    if (!Platform.isAndroid) return true;
    try {
      final ready = await _channel.invokeMethod<bool>('prepareVpn');
      return ready ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<InstalledApp>> listApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listApps');
      return (raw ?? const [])
          .whereType<Map>()
          .map((item) => InstalledApp(
                packageName: '${item['package'] ?? ''}',
                label: '${item['label'] ?? item['package'] ?? ''}',
                system: item['system'] == true,
              ))
          .where((app) => app.packageName.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// PNG bytes of an installed app's icon (Android), cached per package.
  static final Map<String, Future<Uint8List?>> _iconCache = {};
  Future<Uint8List?> appIcon(String package) {
    if (!Platform.isAndroid) return Future.value(null);
    return _iconCache.putIfAbsent(package, () async {
      try {
        return await _channel.invokeMethod<Uint8List>('appIcon', {'package': package});
      } catch (_) {
        return null;
      }
    });
  }

  /// Android: switch the launcher icon (activity-alias). No-op elsewhere.
  Future<bool> setAppIcon(String name) async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('setAppIcon', {'icon': name})) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAutoStart(bool enabled) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setAutoStart', {'enabled': enabled});
      } catch (_) {}
      return;
    }
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    // The app runs elevated (TUN + WinDivert need it); a plain HKCU\Run entry
    // for an elevated exe is silently dropped by UAC at logon, so use a
    // scheduled task with highest privileges instead.
    try {
      await Process.run('schtasks', ['/Delete', '/TN', 'NukefyVPN', '/F']);
      await Process.run('reg', ['delete', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'NukefyVPN', '/f']);
      if (enabled) {
        await Process.run('schtasks', [
          '/Create', '/TN', 'NukefyVPN', '/SC', 'ONLOGON', '/RL', 'HIGHEST', '/F',
          '/TR', '"$exe" --autostart',
        ]);
      }
    } catch (_) {}
  }

  /// Android 13+: asks the system to add the VPN tile to Quick Settings.
  /// Returns the raw result code as a string ("2" added, "1" already there,
  /// "0" declined) or "unsupported".
  Future<String> requestAddTile() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return (await _channel.invokeMethod<String>('requestAddTile')) ?? 'unknown';
    } catch (error) {
      return 'error:$error';
    }
  }

  Future<void> openVpnSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openVpnSettings');
    } catch (_) {}
  }

  Future<void> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } catch (_) {}
  }

  Future<bool> installApk(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {'path': path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> consumeLaunchAction() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('consumeLaunchAction');
    } catch (_) {
      return null;
    }
  }

  Future<void> revealFile(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
      return;
    }
    await Process.run('xdg-open', [p.dirname(path)]);
  }

  Future<String> downloadCore({
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      AppConstants.singboxReleasesApi,
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': AppConstants.userAgent,
        },
        responseType: ResponseType.json,
      ),
    );
    final data = response.data ?? const {};
    final assets = (data['assets'] as List?) ?? const [];
    final asset = _pickCoreAsset(assets);
    if (asset == null) {
      throw const CoreDownloadException('no-core-asset');
    }
    final url = asset['browser_download_url'] as String;
    final name = asset['name'] as String;
    final dir = await coreDirectory();
    final archiveFile = File(p.join(dir.path, name));
    final started = DateTime.now();
    await _dio.download(
      url,
      archiveFile.path,
      options: Options(headers: const {'User-Agent': AppConstants.userAgent}),
      onReceiveProgress: (received, total) {
        onProgress?.call(DownloadProgress(
          received: received,
          total: total,
          startedAt: started,
        ));
      },
    );
    await _extractCore(archiveFile, dir);
    if (archiveFile.existsSync()) {
      try {
        await archiveFile.delete();
      } catch (_) {}
    }
    final binary = await binaryPath();
    if (binary == null) {
      throw const CoreDownloadException('extract-failed');
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', binary]);
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('registerBinary', {'path': binary});
      } catch (_) {}
    }
    return binary;
  }

  /// Picks the official sing-box CLI archive for this platform.
  ///
  /// The sing-box release also contains GUI apps (`SFA-1.x-arm64-v8a.apk`,
  /// `SFW-1.x-x64.exe`) and Linux packages (`.deb`, `.rpm`). Matching only on
  /// "android" + "arm64" used to pick the APK, which then failed to unpack with
  /// `unsupported-archive`. Matching is done on full `-` separated segments of
  /// the `sing-box-<version>-<os>-<arch>` name, so a 32-bit ARM device can
  /// never be handed the `arm64` build.
  Map<String, dynamic>? _pickCoreAsset(List assets) {
    final candidates = assets
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .where(_isSingboxCliAsset)
        .toList(growable: false);

    if (Platform.isWindows) {
      return _pickBySegments(candidates, const ['windows', 'amd64'], '.zip');
    }
    if (Platform.isAndroid) {
      return _pickBySegments(
        candidates,
        ['android', _androidAssetArch()],
        '.tar.gz',
      );
    }
    if (Platform.isLinux) {
      return _pickBySegments(candidates, const ['linux', 'amd64'], '.tar.gz');
    }
    if (Platform.isMacOS) {
      return _pickBySegments(candidates, const ['darwin', 'arm64'], '.tar.gz') ??
          _pickBySegments(candidates, const ['darwin', 'amd64'], '.tar.gz');
    }
    return null;
  }

  /// Whether an asset is an unpackable sing-box CLI build.
  static bool _isSingboxCliAsset(Map<String, dynamic> asset) {
    final name = '${asset['name']}'.toLowerCase();
    if (!name.startsWith('sing-box-')) return false;
    for (final suffix in AppConstants.coreBlockedSuffixes) {
      if (name.endsWith(suffix)) return false;
    }
    return name.endsWith('.tar.gz') || name.endsWith('.zip');
  }

  /// First asset whose name carries [segments] as whole `-` separated parts.
  /// The shortest name wins, so `sing-box-1.14.2-windows-amd64.zip` beats
  /// `sing-box-1.14.2-windows-amd64-legacy-windows-7.zip`.
  static Map<String, dynamic>? _pickBySegments(
    List<Map<String, dynamic>> assets,
    List<String> segments,
    String extension,
  ) {
    Map<String, dynamic>? picked;
    var pickedLength = 1 << 30;
    for (final asset in assets) {
      final name = '${asset['name']}'.toLowerCase();
      if (!name.endsWith(extension)) continue;
      final stem = name.substring(0, name.length - extension.length);
      if (!_hasSegments(stem, segments)) continue;
      if (name.length < pickedLength) {
        picked = asset;
        pickedLength = name.length;
      }
    }
    return picked;
  }

  static bool _hasSegments(String name, List<String> segments) {
    final parts = name.split('-');
    for (var i = 0; i + segments.length <= parts.length; i++) {
      var matched = true;
      for (var j = 0; j < segments.length; j++) {
        if (parts[i + j] != segments[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  /// Asset arch segment matching the device ABI. 32-bit ARM is `arm`, not
  /// `armv7` and definitely not `arm64`.
  static String _androidAssetArch() {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return 'arm64';
      case Abi.androidArm:
        return 'arm';
      case Abi.androidX64:
        return 'amd64';
      case Abi.androidIA32:
        return '386';
      default:
        return 'arm64';
    }
  }

  Future<void> _extractCore(File archiveFile, Directory dest) async {
    final bytes = await archiveFile.readAsBytes();
    final name = archiveFile.path.toLowerCase();
    Archive archive;
    if (name.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
      final tar = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(tar);
    } else {
      throw const CoreDownloadException('unsupported-archive');
    }
    for (final file in archive) {
      if (!file.isFile) continue;
      final base = p.basename(file.name);
      if (base == 'sing-box' || base == 'sing-box.exe' || base == 'wintun.dll') {
        final out = File(p.join(dest.path, base));
        await out.writeAsBytes(file.content as List<int>, flush: true);
      }
    }
  }
}

class InstalledApp {
  InstalledApp({
    required this.packageName,
    required this.label,
    required this.system,
  });

  final String packageName;
  final String label;
  final bool system;
}
