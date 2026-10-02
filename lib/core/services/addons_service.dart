import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'storage_service.dart';

/// One repository of the author that can be installed as an add-on.
class AddonRepo {
  const AddonRepo({
    required this.name,
    required this.description,
    required this.htmlUrl,
  });

  final String name;
  final String description;
  final String htmlUrl;

  /// Music packs are imported by the Music tab instead of being launched.
  bool get isMusic => name.toLowerCase().contains('music');
}

class AddonRelease {
  const AddonRelease({
    required this.version,
    required this.assetName,
    required this.assetUrl,
    required this.size,
  });

  final String version;
  final String assetName;
  final String assetUrl;
  final int size;
}

class InstalledAddon {
  InstalledAddon({
    required this.name,
    required this.version,
    required this.path,
    this.installedAt,
  });

  final String name;
  String version;
  String path;
  DateTime? installedAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'path': path,
        'installedAt': installedAt?.toIso8601String(),
      };

  factory InstalledAddon.fromJson(Map<String, dynamic> json) => InstalledAddon(
        name: (json['name'] as String?) ?? '',
        version: (json['version'] as String?) ?? '',
        path: (json['path'] as String?) ?? '',
        installedAt: DateTime.tryParse((json['installedAt'] as String?) ?? ''),
      );
}

/// "Дополнения и программы": a catalog built from the author's GitHub
/// repositories. Each entry downloads the latest release asset into the app
/// support directory and can be removed again, so the main bundle stays free
/// of optional payloads.
class AddonsService extends ChangeNotifier {
  AddonsService._() {
    _load();
  }
  static final AddonsService instance = AddonsService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
    sendTimeout: const Duration(seconds: 30),
  ));

  static const String _storageKey = 'addons_installed';

  List<AddonRepo> catalog = [];
  final Map<String, AddonRelease?> releases = {};
  final Map<String, InstalledAddon> installed = {};
  bool loading = false;
  String? installing;
  double? progress;
  String? error;

  void _load() {
    final json = StorageService.instance.readJson(_storageKey);
    final items = (json?['items'] as List?) ?? const [];
    installed.clear();
    for (final item in items.whereType<Map>()) {
      final addon = InstalledAddon.fromJson(item.map((k, v) => MapEntry(k.toString(), v)));
      if (addon.name.isNotEmpty) installed[addon.name] = addon;
    }
  }

  Future<void> _persist() async {
    await StorageService.instance.writeJson(_storageKey, {
      'items': installed.values.map((e) => e.toJson()).toList(),
    });
  }

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'addons'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Directory? folderOf(String name) {
    final addon = installed[name];
    if (addon == null) return null;
    final dir = Directory(addon.path);
    return dir.existsSync() ? dir : null;
  }

  /// Lists the author's public repositories, newest activity first.
  Future<void> refreshCatalog() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response = await _dio.get<List<dynamic>>(
        'https://api.github.com/users/kayorissss/repos?per_page=100&sort=pushed',
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': AppConstants.userAgent,
          },
          responseType: ResponseType.json,
        ),
      );
      final repos = <AddonRepo>[];
      for (final item in (response.data ?? const []).whereType<Map>()) {
        final map = item.map((k, v) => MapEntry(k.toString(), v));
        final name = '${map['name'] ?? ''}';
        if (name.isEmpty || map['archived'] == true) continue;
        if (name == 'Nukefy-VPN') continue; // the app itself is not an add-on
        repos.add(AddonRepo(
          name: name,
          description: '${map['description'] ?? ''}',
          htmlUrl: '${map['html_url'] ?? ''}',
        ));
      }
      catalog = repos;
      releases.clear();
      // Resolve the latest release of every repository; repositories without
      // releases simply stay listed as "not installable yet".
      for (final repo in repos) {
        releases[repo.name] = await _latestRelease(repo.name);
      }
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<AddonRelease?> _latestRelease(String repo) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/${AppConstants.githubRepo.split('/').first}/$repo/releases/latest',
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': AppConstants.userAgent,
          },
          responseType: ResponseType.json,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      final data = response.data;
      if (data == null || response.statusCode == 404) return null;
      final assets = (data['assets'] as List?) ?? const [];
      if (assets.isEmpty) return null;
      final asset = assets.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).first;
      final tag = '${data['tag_name'] ?? ''}';
      final url = '${asset['browser_download_url'] ?? ''}';
      if (tag.isEmpty || url.isEmpty) return null;
      return AddonRelease(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        assetName: '${asset['name'] ?? ''}',
        assetUrl: url,
        size: (asset['size'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  bool needsUpdate(String name) {
    final addon = installed[name];
    final release = releases[name];
    if (addon == null || release == null) return false;
    return addon.version != release.version;
  }

  Future<void> install(String name) async {
    final release = releases[name];
    if (release == null || installing != null) return;
    installing = name;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final root = await _root();
      final dir = Directory(p.join(root.path, name, release.version));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, release.assetName.isEmpty ? 'release.bin' : release.assetName));
      final response = await _dio.get<ResponseBody>(
        release.assetUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: const {'User-Agent': AppConstants.userAgent},
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );
      final total = release.size > 0
          ? release.size
          : int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          progress = total <= 0 ? null : (received / total).clamp(0.0, 1.0);
          _throttledNotify();
        }
      } finally {
        await sink.close();
      }
      // Drop older versions of the same add-on: only one copy stays on disk.
      final parent = dir.parent;
      if (parent.existsSync()) {
        for (final old in parent.listSync().whereType<Directory>()) {
          if (old.path != dir.path) {
            try {
              old.deleteSync(recursive: true);
            } catch (_) {}
          }
        }
      }
      installed[name] = InstalledAddon(
        name: name,
        version: release.version,
        path: dir.path,
        installedAt: DateTime.now(),
      );
      await _persist();
    } catch (e) {
      error = '$e';
    } finally {
      installing = null;
      progress = null;
      notifyListeners();
    }
  }

  Timer? _notifyTimer;
  void _throttledNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 200), notifyListeners);
  }

  Future<void> remove(String name) async {
    final addon = installed.remove(name);
    if (addon != null) {
      final dir = Directory(addon.path);
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
      // Remove the now empty per-add-on folder as well.
      final parent = dir.parent;
      if (parent.existsSync() && parent.listSync().isEmpty) {
        try {
          parent.deleteSync();
        } catch (_) {}
      }
    }
    await _persist();
    notifyListeners();
  }

  /// Opens the add-on folder in the system file manager.
  Future<void> openFolder(String name) async {
    final dir = folderOf(name);
    if (dir == null) return;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir.path]);
    } else {
      await Process.run('xdg-open', [dir.path]);
    }
  }

  /// Launches an installed program add-on (Windows executables only).
  Future<bool> launch(String name) async {
    final dir = folderOf(name);
    if (dir == null || !Platform.isWindows) return false;
    final exe = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList()
      ..sort((a, b) => a.path.length.compareTo(b.path.length));
    if (exe.isEmpty) return false;
    await Process.start(exe.first.path, [], workingDirectory: p.dirname(exe.first.path), mode: ProcessStartMode.detached);
    return true;
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    super.dispose();
  }
}
