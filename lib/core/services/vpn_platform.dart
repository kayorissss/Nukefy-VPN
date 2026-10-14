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
    this.xray = false,
    this.xrayPath,
  });

  final bool libbox;
  final bool binary;
  final String? binaryPath;
  final String? version;

  /// Xray-core binary (serves XHTTP/SplitHTTP servers sing-box cannot run).
  final bool xray;
  final String? xrayPath;

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
  Process? _xrayProcess;
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

  Future<String?> xrayBinaryPath() async {
    final dir = await coreDirectory();
    final name = Platform.isWindows ? 'xray.exe' : 'xray';
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
          xray: raw?['xray'] == true,
          xrayPath: raw?['xrayPath'] as String?,
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
    final xrayPath = await xrayBinaryPath();
    return CoreInfo(
      libbox: false,
      binary: path != null,
      binaryPath: path,
      version: version,
      xray: xrayPath != null,
      xrayPath: xrayPath,
    );
  }

  Future<CoreStartResult> start({
    required String configJson,
    required bool preferTun,
    String engine = 'singbox',
    String? fallbackConfigJson,
  }) async {
    final dir = await configDirectory();
    final isXray = engine == 'xray';
    final configFile = File(p.join(dir.path, isXray ? 'xray.json' : 'config.json'));
    await configFile.writeAsString(configJson);
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('start', {
          'configPath': configFile.path,
          'configJson': configJson,
          'preferTun': preferTun,
          'engine': engine,
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
    var result = await _startProcess(
      configFile.path,
      dir.path,
      engine: engine,
    );
    if (!result.ok && !isXray && fallbackConfigJson != null) {
      // Remote rule sets are the most common first-start failure (their
      // download needs network before the tunnel exists). Retry once with
      // the built-in suffix rules instead of reporting a dead client.
      appendLog('retrying without remote rule sets');
      await configFile.writeAsString(fallbackConfigJson);
      result = await _startProcess(configFile.path, dir.path, engine: engine);
    }
    return result;
  }

  Future<CoreStartResult> _startProcess(
    String configPath,
    String workDir, {
    String engine = 'singbox',
  }) async {
    final isXray = engine == 'xray';
    final binary = isXray ? await xrayBinaryPath() : await binaryPath();
    if (binary == null) {
      return CoreStartResult(
        ok: false,
        mode: 'missing',
        error: isXray ? 'XRAY_MISSING' : 'CORE_MISSING',
      );
    }
    await stop();
    _log.clear();
    // Validate first so the user sees the real config error, not a spinner
    // that silently dies.
    try {
      final check = isXray
          ? await Process.run(binary, ['run', '-test', '-c', configPath])
          : await Process.run(binary, ['check', '-c', configPath]);
      if (check.exitCode != 0) {
        final message = '${check.stderr}${check.stdout}'.trim();
        return CoreStartResult(
          ok: false,
          mode: 'missing',
          error: message.isEmpty ? 'config-invalid' : message,
        );
      }
    } catch (_) {
      // If the check itself cannot run, fall through to the real start.
    }
    try {
      final process = await Process.start(
        binary,
        isXray
            ? ['run', '-c', configPath]
            : ['run', '-c', configPath, '-D', workDir],
        workingDirectory: p.dirname(binary),
        environment: isXray
            ? {'XRAY_LOCATION_ASSET': p.dirname(binary)}
            : null,
        mode: ProcessStartMode.normal,
      );
      if (isXray) {
        _xrayProcess = process;
      } else {
        _process = process;
      }
      process.stdout.transform(utf8.decoder).listen(appendLog);
      process.stderr.transform(utf8.decoder).listen(appendLog);
      process.exitCode.then((code) {
        appendLog('${isXray ? 'xray' : 'sing-box'} exited: $code');
        if (identical(_process, process)) _process = null;
        if (identical(_xrayProcess, process)) _xrayProcess = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final alive = isXray ? _xrayProcess != null : _process != null;
      if (!alive) {
        return CoreStartResult(
          ok: false,
          mode: 'proxy',
          error: logText.trim().isEmpty ? 'core-exited' : logText.trim(),
        );
      }
      return CoreStartResult(ok: true, mode: isXray ? 'xray' : 'tun');
    } catch (error) {
      return CoreStartResult(ok: false, mode: 'missing', error: '$error');
    }
  }

  /// Real per-engine traffic totals from the Xray stats API
  /// (`inbound>>>socks-in/http-in` counters). Returns null when unavailable.
  Future<({int up, int down})?> xrayTrafficTotals() async {
    final binary = await xrayBinaryPath();
    if (binary == null || _xrayProcess == null) return null;
    try {
      final result = await Process.run(binary, [
        'api',
        'statsquery',
        '--server=127.0.0.1:${AppConstants.xrayApiPort}',
      ]).timeout(const Duration(seconds: 4));
      final text = '${result.stdout}';
      if (text.isEmpty) return null;
      var up = 0;
      var down = 0;
      final pattern = RegExp(r'name: "([^"]+)"\s+value: (\d+)');
      for (final match in pattern.allMatches(text)) {
        final name = match.group(1)!;
        final value = int.tryParse(match.group(2)!) ?? 0;
        if (!name.startsWith('inbound>>>')) continue;
        if (name.endsWith('>>>uplink')) up += value;
        if (name.endsWith('>>>downlink')) down += value;
      }
      return (up: up, down: down);
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stop');
      } catch (_) {}
      return;
    }
    for (final process in [_process, _xrayProcess]) {
      if (process == null) continue;
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _process = null;
    _xrayProcess = null;
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

  Future<void> setAutoStart(bool enabled) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setAutoStart', {'enabled': enabled});
      } catch (_) {}
      return;
    }
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    if (enabled) {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'NukefyVPN',
        '/t',
        'REG_SZ',
        '/d',
        exe,
        '/f',
      ]);
    } else {
      await Process.run('reg', [
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'NukefyVPN',
        '/f',
      ]);
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
      throw StateError('no-core-asset');
    }
    final url = asset['browser_download_url'] as String;
    final name = asset['name'] as String;
    final dir = await coreDirectory();
    final archivePath = p.join(dir.path, name);
    final started = DateTime.now();
    await _dio.download(
      url,
      archivePath,
      options: Options(headers: const {'User-Agent': AppConstants.userAgent}),
      onReceiveProgress: (received, total) {
        onProgress?.call(DownloadProgress(
          received: received,
          total: total,
          startedAt: started,
        ));
      },
    );
    await _extractCore(File(archivePath), dir);
    final binary = await binaryPath();
    if (binary == null) throw StateError('extract-failed');
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

  Future<String> downloadXray({
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      AppConstants.xrayReleasesApi,
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
    final asset = _pickXrayAsset(assets);
    if (asset == null) {
      throw StateError('no-xray-asset');
    }
    final url = asset['browser_download_url'] as String;
    final name = asset['name'] as String;
    final dir = await coreDirectory();
    final archivePath = p.join(dir.path, name);
    final started = DateTime.now();
    await _dio.download(
      url,
      archivePath,
      options: Options(headers: const {'User-Agent': AppConstants.userAgent}),
      onReceiveProgress: (received, total) {
        onProgress?.call(DownloadProgress(
          received: received,
          total: total,
          startedAt: started,
        ));
      },
    );
    await _extractXray(File(archivePath), dir);
    final binary = await xrayBinaryPath();
    if (binary == null) throw StateError('extract-failed');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', binary]);
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('registerXray', {'path': binary});
      } catch (_) {}
    }
    return binary;
  }

  Map<String, dynamic>? _pickXrayAsset(List assets) {
    final names = assets.whereType<Map>().map((e) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
    bool match(Map<String, dynamic> asset, List<String> needles) {
      final name = '${asset['name']}'.toLowerCase();
      return needles.every(name.contains);
    }

    Map<String, dynamic>? find(List<String> needles) {
      return names.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => match(asset!, needles),
            orElse: () => null,
          );
    }

    if (Platform.isWindows) return find(['xray-windows-64', '.zip']);
    if (Platform.isAndroid) {
      switch (_androidAbi()) {
        case 'arm64':
          return find(['xray-android-arm64']) ?? find(['android', 'arm64']);
        case 'armv7':
          return find(['xray-android-arm']) ?? find(['android', 'arm']);
        default:
          return find(['android', 'amd64']) ?? find(['xray-android']);
      }
    }
    if (Platform.isLinux) return find(['xray-linux-64', '.zip']);
    return null;
  }

  Future<void> _extractXray(File archiveFile, Directory dest) async {
    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final base = p.basename(file.name);
      if (base == 'xray' ||
          base == 'xray.exe' ||
          base == 'geoip.dat' ||
          base == 'geosite.dat') {
        final out = File(p.join(dest.path, base));
        await out.writeAsBytes(file.content as List<int>, flush: true);
      }
    }
  }

  Map<String, dynamic>? _pickCoreAsset(List assets) {
    final names = assets.whereType<Map>().map((e) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
    bool match(Map<String, dynamic> asset, List<String> needles) {
      final name = '${asset['name']}'.toLowerCase();
      return needles.every(name.contains);
    }

    if (Platform.isWindows) {
      return names.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => match(asset!, ['windows', 'amd64', '.zip']),
            orElse: () => null,
          );
    }
    if (Platform.isAndroid) {
      final abi = _androidAbi();
      return names.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => match(asset!, ['android', abi]),
            orElse: () => names.cast<Map<String, dynamic>?>().firstWhere(
                  (asset) => match(asset!, ['android', 'arm64']),
                  orElse: () => null,
                ),
          );
    }
    if (Platform.isLinux) {
      return names.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => match(asset!, ['linux', 'amd64']),
            orElse: () => null,
          );
    }
    return null;
  }

  String _androidAbi() {
    final arch = Abi.current();
    switch (arch) {
      case Abi.androidArm64:
        return 'arm64';
      case Abi.androidArm:
        return 'armv7';
      case Abi.androidX64:
        return 'amd64';
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
      throw StateError('unsupported-archive');
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
