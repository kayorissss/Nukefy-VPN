import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

enum ApkInstallResult { launched, permissionRequired, missing, invalid, wrongPackage, notNewer, signatureMismatch, failed }

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

class XrayCoreInfo {
  XrayCoreInfo({required this.binary, this.binaryPath, this.version});

  final bool binary;
  final String? binaryPath;
  final String? version;

  bool get available => binary;
}

class XrayStartResult {
  const XrayStartResult({required this.ok, this.error});
  final bool ok;
  final String? error;
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
  VpnPlatform({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 2),
              sendTimeout: const Duration(seconds: 30),
            ));

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

  Future<Directory> xrayDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'xray'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String?> xrayBinaryPath() async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    final dir = await xrayDirectory();
    final name = Platform.isWindows ? 'xray.exe' : 'xray';
    final file = File(p.join(dir.path, name));
    return file.existsSync() ? file.path : null;
  }

  Future<void> deleteXrayCore() async {
    await stopXray();
    final path = await xrayBinaryPath();
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }

  Future<XrayCoreInfo> xrayCoreInfo() async {
    final path = await xrayBinaryPath();
    String? version;
    if (path != null) {
      try {
        final result = await Process.run(path, ['version']).timeout(const Duration(seconds: 5));
        version = '${result.stdout}'.trim().split('\n').first;
      } catch (_) {}
    }
    return XrayCoreInfo(binary: path != null, binaryPath: path, version: version);
  }

  Future<XrayStartResult> startXray({required String configJson, required String workDir}) async {
    if (Platform.isAndroid || Platform.isIOS) return const XrayStartResult(ok: false, error: 'XRAY_PLATFORM_UNSUPPORTED');
    final binary = await xrayBinaryPath();
    if (binary == null) return const XrayStartResult(ok: false, error: 'XRAY_CORE_MISSING');
    await stopXray();
    final config = File(p.join(workDir, 'xray-config.json'));
    await config.writeAsString(configJson, flush: true);
    try {
      final process = await Process.start(binary, ['run', '-config', config.path], workingDirectory: p.dirname(binary), mode: ProcessStartMode.normal);
      _xrayProcess = process;
      process.stdout.transform(utf8.decoder).listen((line) => appendLog('xray: $line'));
      process.stderr.transform(utf8.decoder).listen((line) => appendLog('xray: $line'));
      process.exitCode.then((code) {
        appendLog('xray exited: $code');
        if (identical(_xrayProcess, process)) _xrayProcess = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_xrayProcess == null) return XrayStartResult(ok: false, error: logText.trim().isEmpty ? 'XRAY_EXITED' : logText.trim());
      return const XrayStartResult(ok: true);
    } catch (error) {
      return XrayStartResult(ok: false, error: '$error');
    }
  }

  Future<void> stopXray() async {
    final process = _xrayProcess;
    _xrayProcess = null;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      if (Platform.isWindows) {
        try {
          await Process.run('taskkill', ['/F', '/IM', 'xray.exe']).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
  }

  Future<String> downloadXrayCore({void Function(DownloadProgress progress)? onProgress}) async {
    if (Platform.isAndroid || Platform.isIOS) throw const CoreDownloadException('xray-platform-unsupported');
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/XTLS/Xray-core/releases/latest',
      options: Options(headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': AppConstants.userAgent}, responseType: ResponseType.json),
    );
    final assets = (response.data?['assets'] as List?) ?? const [];
    final asset = _pickXrayAsset(assets);
    if (asset == null) throw const CoreDownloadException('xray-no-asset');
    final url = '${asset['browser_download_url'] ?? ''}';
    final name = '${asset['name'] ?? ''}';
    final expected = (asset['size'] as num?)?.toInt() ?? 0;
    final digest = '${asset['digest'] ?? ''}';
    if (!Uri.tryParse(url).toString().startsWith('https://github.com/XTLS/Xray-core/releases/download/')) throw const CoreDownloadException('xray-invalid-url');
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) throw const CoreDownloadException('xray-no-digest');
    final dir = await xrayDirectory();
    final archive = File(p.join(dir.path, name));
    final started = DateTime.now();
    final streamResponse = await _dio.get<ResponseBody>(url, options: Options(responseType: ResponseType.stream, headers: const {'User-Agent': AppConstants.userAgent}));
    final total = expected > 0 ? expected : int.tryParse(streamResponse.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    var received = 0;
    final sink = archive.openWrite();
    try {
      await for (final chunk in streamResponse.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received: received, total: total, startedAt: started));
      }
    } finally {
      await sink.close();
    }
    if (expected > 0 && received != expected) {
      await archive.delete();
      throw const CoreDownloadException('xray-size-mismatch');
    }
    final actual = await sha256.bind(archive.openRead()).first;
    if (actual.toString() != digest.substring(7)) {
      await archive.delete();
      throw const CoreDownloadException('xray-integrity-failed');
    }
    await _extractXray(archive, dir);
    await archive.delete();
    final binary = await xrayBinaryPath();
    if (binary == null) throw const CoreDownloadException('xray-extract-failed');
    if (!Platform.isWindows) await Process.run('chmod', ['755', binary]);
    return binary;
  }

  Map<String, dynamic>? _pickXrayAsset(List assets) {
    final names = assets.whereType<Map>().map((item) => item.map((k, v) => MapEntry(k.toString(), v))).toList();
    final wanted = Platform.isWindows ? ['Xray-windows-64.zip'] : Platform.isLinux ? ['Xray-linux-64.zip'] : ['Xray-macos-64.zip', 'Xray-macos-arm64-v8a.zip'];
    for (final name in wanted) {
      for (final asset in names) {
        if ('${asset['name']}' == name) return asset;
      }
    }
    return null;
  }

  Future<void> _extractXray(File archiveFile, Directory destination) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final base = p.basename(entry.name);
      if (base != 'xray' && base != 'xray.exe') continue;
      final out = File(p.join(destination.path, Platform.isWindows ? 'xray.exe' : 'xray'));
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    }
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

  Future<void> deleteCore() async {
    await stop();
    final path = await binaryPath();
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
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
    return _startProcess(configFile.path, dir.path, preferTun: preferTun);
  }

  Future<CoreStartResult> _startProcess(String configPath, String workDir, {required bool preferTun}) async {
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
      return CoreStartResult(ok: true, mode: preferTun ? 'tun' : 'proxy');
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
      // Killing is immediate; waiting seconds here only made quitting the
      // app feel broken.
      await process.exitCode.timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      if (Platform.isWindows) {
        try {
          await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
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

  /// Restarts the UI after a launcher icon change.  The new process is
  /// started before the current one exits so the user never lands on a dead
  /// tray icon; Android delegates to the activity launcher.
  Future<void> restartApp() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('restartApp');
      } catch (_) {}
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await Process.start(
        Platform.resolvedExecutable,
        Platform.executableArguments,
        mode: ProcessStartMode.detached,
      );
    }
  }

  Future<void> setAutoStart(bool enabled, {bool startInTray = false}) async {
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
          '/TR', '"$exe" --autostart${startInTray ? ' --tray' : ''}',
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

  Future<ApkInstallResult> installApk(String path) async {
    if (!Platform.isAndroid) return ApkInstallResult.failed;
    try {
      final raw = await _channel.invokeMethod<String>('installApk', {'path': path});
      return switch (raw) {
        'launched' => ApkInstallResult.launched,
        'permission' => ApkInstallResult.permissionRequired,
        'missing' => ApkInstallResult.missing,
        'invalid' => ApkInstallResult.invalid,
        'package' => ApkInstallResult.wrongPackage,
        'version' => ApkInstallResult.notNewer,
        'signature' => ApkInstallResult.signatureMismatch,
        _ => ApkInstallResult.failed,
      };
    } catch (_) {
      return ApkInstallResult.failed;
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

  /// Starts the downloaded desktop installer and closes this process so the
  /// installer can replace locked files. Android delegates to its package
  /// installer through [installApk].
  Future<bool> installUpdate(String path) async {
    if (!Platform.isWindows) return false;
    final installer = File(path);
    if (!installer.existsSync()) return false;
    await Process.start(
      installer.path,
      const ['/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<void> revealFile(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
      return;
    }
    await Process.run('xdg-open', [p.dirname(path)]);
  }

  /// Flushes the platform resolver cache without changing firewall or
  /// Defender settings.  A failed command is returned to the caller so the
  /// result can be copied instead of being hidden behind a spinner.
  Future<String> flushDnsCache() async {
    if (Platform.isWindows) {
      final result = await Process.run('ipconfig', ['/flushdns']);
      return '${result.stdout}${result.stderr}'.trim();
    }
    if (Platform.isLinux) {
      final result = await Process.run('resolvectl', ['flush-caches']);
      return '${result.stdout}${result.stderr}'.trim();
    }
    if (Platform.isMacOS) {
      final result = await Process.run('sh', ['-c', 'dscacheutil -flushcache; killall -HUP mDNSResponder']);
      return '${result.stdout}${result.stderr}'.trim();
    }
    return 'unsupported';
  }

  /// Restarts Discord through its official updater when it is installed.
  /// Killing the current Discord process is intentionally left to the caller
  /// after an explicit confirmation.
  Future<String> restartDiscord() async {
    if (!Platform.isWindows) return 'unsupported';
    final stopped = await Process.run('taskkill', ['/F', '/IM', 'Discord.exe']);
    final local = Platform.environment['LOCALAPPDATA'];
    final updater = local == null ? null : File(p.join(local, 'Discord', 'Update.exe'));
    if (updater != null && updater.existsSync()) {
      await Process.start(updater.path, const ['--processStart', 'Discord.exe'], mode: ProcessStartMode.detached);
      return '${stopped.stdout}${stopped.stderr}'.trim();
    }
    await Process.start('cmd.exe', ['/c', 'start', '', 'discord://-/'], mode: ProcessStartMode.detached);
    return '${stopped.stdout}${stopped.stderr}'.trim();
  }

  /// Runs only the documented Windows Winsock reset. The caller must show a
  /// confirmation and the command output; no Defender or firewall changes are
  /// made here.
  Future<String> windowsNetworkReset() async {
    if (!Platform.isWindows) return 'unsupported';
    final results = <String>[];
    for (final command in [
      ('netsh', ['winsock', 'reset']),
      ('ipconfig', ['/flushdns']),
    ]) {
      final result = await Process.run(command.$1, command.$2);
      results.add('${command.$1}: ${result.stdout}${result.stderr}'.trim());
    }
    return results.join('\\n');
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
    final expected = (asset['size'] as num?)?.toInt() ?? 0;
    final dir = await coreDirectory();
    final archiveFile = File(p.join(dir.path, name));
    final started = DateTime.now();
    var existing = archiveFile.existsSync() ? archiveFile.lengthSync() : 0;
    if (expected > 0 && existing > expected) {
      await archiveFile.delete();
      existing = 0;
    }
    if (expected > 0 && existing == expected) {
      onProgress?.call(DownloadProgress(received: existing, total: expected, startedAt: started));
    } else {
      final headers = <String, dynamic>{'User-Agent': AppConstants.userAgent};
      if (existing > 0) headers['Range'] = 'bytes=$existing-';
      final streamResponse = await _dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream, headers: headers),
      );
      final append = existing > 0 && streamResponse.statusCode == 206;
      if (!append) existing = 0;
      final total = expected > 0
          ? expected
          : (streamResponse.headers.value(Headers.contentLengthHeader) == null
              ? 0
              : int.tryParse(streamResponse.headers.value(Headers.contentLengthHeader)!) ?? 0) + existing;
      final sink = archiveFile.openWrite(mode: append ? FileMode.append : FileMode.writeOnly);
      var received = existing;
      try {
        await for (final chunk in streamResponse.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(DownloadProgress(received: received, total: total, startedAt: started));
        }
      } finally {
        await sink.close();
      }
    }
    await _extractCore(archiveFile, dir);
    if (archiveFile.existsSync()) await archiveFile.delete();
    final binary = await binaryPath();
    if (binary == null) {
      throw const CoreDownloadException('extract-failed');
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', binary]);
    }
    if (Platform.isAndroid) {
      await _channel.invokeMethod('registerBinary', {'path': binary});
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
