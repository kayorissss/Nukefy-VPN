import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'app_perf.dart';

class TgWsProxyRelease {
  const TgWsProxyRelease({required this.version, required this.url, required this.digest, required this.size});

  final String version;
  final String url;
  final String digest;
  final int size;
}

class TgProxyProgress {
  const TgProxyProgress({required this.received, required this.total, required this.startedAt});

  final int received;
  final int total;
  final DateTime startedAt;

  double? get fraction => total <= 0 ? null : (received / total).clamp(0.0, 1.0).toDouble();
}

/// Optional integration with the official Flowseal TG WS Proxy binary.
///
/// The executable is deliberately not bundled into Nukefy or its installer:
/// it is downloaded only after an explicit user action, from the upstream
/// GitHub release, and accepted only when GitHub's SHA-256 digest matches.
class TgWsProxyService extends ChangeNotifier {
  TgWsProxyService._();
  static final instance = TgWsProxyService._();

  static const _repo = 'Flowseal/tg-ws-proxy';
  static const _releaseApi = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _assetName = 'TgWsProxy_windows.exe';
  static const _maxAssetBytes = 80 * 1024 * 1024;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 3),
    sendTimeout: const Duration(seconds: 30),
  ));

  Process? _process;
  Timer? _logTimer;
  int _logOffset = 0;
  bool _readingLog = false;
  bool _busy = false;
  CancelToken? _cancelToken;
  TgProxyProgress? progress;
  String? lastError;

  bool get supported => Platform.isWindows;
  bool get busy => _busy;
  bool get running => _process != null;

  Future<Directory> get _directory async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'tg-ws-proxy'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<File?> binaryFile() async {
    if (!supported) return null;
    final directory = await _directory;
    final file = File(p.join(directory.path, _assetName));
    return file.existsSync() ? file : null;
  }

  Future<File?> logFile() async {
    if (!supported) return null;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    final file = File(p.join(appData, 'TgWsProxy', 'proxy.log'));
    return file.existsSync() ? file : null;
  }

  Future<TgWsProxyRelease> _latestRelease() async {
    final response = await _dio.get<Map<String, dynamic>>(
      _releaseApi,
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': AppConstants.userAgent,
        },
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    if (data == null) throw const FormatException('tg-ws-no-release');
    final tag = '${data['tag_name'] ?? ''}';
    final rawAssets = (data['assets'] as List?) ?? const [];
    Map<String, dynamic>? asset;
    for (final item in rawAssets.whereType<Map>()) {
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      if (map['name'] == _assetName) {
        asset = map;
        break;
      }
    }
    if (tag.isEmpty || asset == null) throw const FormatException('tg-ws-no-windows-asset');
    final url = Uri.tryParse('${asset['browser_download_url'] ?? ''}');
    final digest = '${asset['digest'] ?? ''}';
    final size = (asset['size'] as num?)?.toInt() ?? 0;
    if (url == null || url.scheme != 'https' || url.host != 'github.com' ||
        !url.path.startsWith('/$_repo/releases/download/')) {
      throw const FormatException('tg-ws-invalid-url');
    }
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('tg-ws-no-digest');
    }
    if (size <= 0 || size > _maxAssetBytes) throw const FormatException('tg-ws-invalid-size');
    return TgWsProxyRelease(version: tag, url: url.toString(), digest: digest.substring(7), size: size);
  }

  Future<File> download({void Function(TgProxyProgress progress)? onProgress}) async {
    if (!supported) throw UnsupportedError('tg-ws-windows-only');
    if (_busy) throw StateError('tg-ws-busy');
    _busy = true;
    lastError = null;
    progress = null;
    notifyListeners();
    final started = DateTime.now();
    final token = CancelToken();
    _cancelToken = token;
    try {
      final release = await _latestRelease().timeout(const Duration(seconds: 30));
      final directory = await _directory;
      final temporary = File(p.join(directory.path, '$_assetName.download'));
      final destination = File(p.join(directory.path, _assetName));
      if (temporary.existsSync()) await temporary.delete();
      await _dio.download(
        release.url,
        temporary.path,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          final snapshot = TgProxyProgress(
            received: received,
            total: total > 0 ? total : release.size,
            startedAt: started,
          );
          progress = snapshot;
          onProgress?.call(snapshot);
          notifyListeners();
        },
        options: Options(headers: const {'User-Agent': AppConstants.userAgent}),
      ).timeout(const Duration(minutes: 5));
      if (!temporary.existsSync() || await temporary.length() != release.size) {
        throw const FormatException('tg-ws-size-mismatch');
      }
      final digest = await sha256.bind(temporary.openRead()).first;
      if (digest.toString() != release.digest) {
        await temporary.delete();
        throw const FormatException('tg-ws-integrity-failed');
      }
      if (destination.existsSync()) await destination.delete();
      await temporary.rename(destination.path);
      progress = TgProxyProgress(received: release.size, total: release.size, startedAt: started);
      return destination;
    } catch (error) {
      lastError = '$error';
      rethrow;
    } finally {
      _cancelToken = null;
      _busy = false;
      notifyListeners();
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('tg-ws-cancelled');
  }

  Future<void> deleteInstalled() async {
    await stop();
    final file = await binaryFile();
    if (file != null && file.existsSync()) await file.delete();
    notifyListeners();
  }

  Future<void> start() async {
    if (!supported) throw UnsupportedError('tg-ws-windows-only');
    if (_process != null) return;
    lastError = null;
    final file = await binaryFile();
    if (file == null) throw StateError('tg-ws-not-installed');
    try {
      final process = await Process.start(
        file.path,
        const [],
        workingDirectory: file.parent.path,
        mode: ProcessStartMode.normal,
      );
      _process = process;
      process.stdout.transform(systemEncoding.decoder).listen((line) => _appendLog(line));
      process.stderr.transform(systemEncoding.decoder).listen((line) => _appendLog(line));
      unawaited(process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          _stopLogWatcher();
          notifyListeners();
        }
      }));
      unawaited(_startLogWatcher());
      notifyListeners();
    } catch (_) {
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _stopLogWatcher();
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _startLogWatcher() async {
    _stopLogWatcher();
    _logOffset = 0;
    await _readLogFile();
    _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!AppPerf.visible) return;
      unawaited(_readLogFile());
    });
  }

  void _stopLogWatcher() {
    _logTimer?.cancel();
    _logTimer = null;
    _readingLog = false;
  }

  Future<void> _readLogFile() async {
    if (_readingLog) return;
    _readingLog = true;
    try {
      final file = await logFile();
      if (file == null || !file.existsSync()) return;
      final length = await file.length();
      if (length < _logOffset) _logOffset = 0;
      if (length <= _logOffset) return;
      final handle = await file.open();
      try {
        await handle.setPosition(_logOffset);
        final bytes = await handle.read(length - _logOffset);
        _logOffset = length;
        for (final line in systemEncoding.decode(bytes).split(RegExp(r'\r?\n'))) {
          _appendLog(line);
        }
      } finally {
        await handle.close();
      }
    } catch (_) {
      // The proxy can rotate its log while it is running; stdout/stderr still
      // remain available and the next poll will resume from the new file.
    } finally {
      _readingLog = false;
    }
  }

  Future<void> openLog() async {
    if (!supported) return;
    final file = await logFile();
    final directory = file?.parent.path ?? p.join(Platform.environment['APPDATA'] ?? '', 'TgWsProxy');
    if (file != null) {
      await Process.run('explorer.exe', ['/select,', file.path]);
    } else {
      await Process.run('explorer.exe', [directory]);
    }
  }

  final List<String> _log = [];
  List<String> get log => List.unmodifiable(_log);

  void _appendLog(String line) {
    final value = line.trim();
    if (value.isEmpty) return;
    _log.add(value);
    if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    notifyListeners();
  }

}
