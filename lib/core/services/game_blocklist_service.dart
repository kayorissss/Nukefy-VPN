import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'storage_service.dart';

/// One game/service list from medvedeff-true/ru-gaming-blocklist.
class GameListInfo {
  const GameListInfo({
    required this.id,
    required this.name,
    required this.file,
    this.size = 0,
  });

  /// File name without `.txt`, e.g. `EpicGames_Fortnite`.
  final String id;
  /// Human readable name, e.g. `Epic Games / Fortnite`.
  final String name;
  final String file;
  final int size;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'file': file, 'size': size};

  static GameListInfo fromJson(Map<String, dynamic> json) => GameListInfo(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        file: (json['file'] as String?) ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class InstalledGame {
  const InstalledGame({
    required this.id,
    required this.name,
    required this.count,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int count;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'count': count,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static InstalledGame fromJson(Map<String, dynamic> json) => InstalledGame(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse('${json['updatedAt']}'),
      );
}

class GameListPreview {
  GameListPreview({required this.game, required List<String> domains, required this.rejected}) : domains = List.unmodifiable(domains);
  final GameListInfo game;
  final List<String> domains;
  final int rejected;
}

/// Downloads per-game domain lists and drops them next to zapret as
/// hostlists, so the DPI bypass covers game services too.
///
/// Everything is fetched from one fixed repository and every single line is
/// validated before it reaches a file winws will read — nothing executable
/// and nothing outside `games/*.txt` is ever accepted.
class GameBlocklistService {
  GameBlocklistService._();
  static final GameBlocklistService instance = GameBlocklistService._();

  static const String repo = 'medvedeff-true/ru-gaming-blocklist';
  static const String branch = 'main';
  static const String _contentsApi = 'https://api.github.com/repos/$repo/contents/games';
  static const String _rawBase = 'https://raw.githubusercontent.com/$repo/$branch/games';

  static bool validId(String id) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,100}$').hasMatch(id);

  /// Refuse anything that is not a plain host name: no slashes, no shell
  /// characters, no spaces, at least one dot and a latin TLD.
  static final RegExp _domain = RegExp(r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})$');
  static const int _maxFileBytes = 2 * 1024 * 1024;

  static const String _catalogKey = 'zapret_games_catalog';
  static const String _installedKey = 'zapret_games_installed';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
  ));

  bool _usedFallback = false;
  bool get usedFallback => _usedFallback;

  /// Stable names from the upstream repository. This is deliberately only a
  /// catalogue: domain contents are still downloaded from the official raw
  /// file after the user explicitly adds a game.
  static const List<GameListInfo> _fallbackCatalog = [
    GameListInfo(id: 'ApexLegends_RocketLeague', name: 'Apex Legends / Rocket League', file: 'ApexLegends_RocketLeague.txt', size: 4864),
    GameListInfo(id: 'Arknights', name: 'Arknights', file: 'Arknights.txt', size: 2643),
    GameListInfo(id: 'ArmaReforger', name: 'Arma Reforger', file: 'ArmaReforger.txt', size: 2563),
    GameListInfo(id: 'BattleNet', name: 'Battle Net', file: 'BattleNet.txt', size: 2881),
    GameListInfo(id: 'Battlefield6', name: 'Battlefield 6', file: 'Battlefield6.txt', size: 3426),
    GameListInfo(id: 'BlueArchive', name: 'Blue Archive', file: 'BlueArchive.txt', size: 7866),
    GameListInfo(id: 'Cloudflare_AWS', name: 'Cloudflare / AWS', file: 'Cloudflare_AWS.txt', size: 17966),
    GameListInfo(id: 'DeadByDaylight', name: 'Dead By Daylight', file: 'DeadByDaylight.txt', size: 4302),
    GameListInfo(id: 'EA_Origin', name: 'EA / Origin', file: 'EA_Origin.txt', size: 4913),
    GameListInfo(id: 'EpicGames_Fortnite', name: 'Epic Games / Fortnite', file: 'EpicGames_Fortnite.txt', size: 9996),
    GameListInfo(id: 'GooseGooseDuck', name: 'Goose Goose Duck', file: 'GooseGooseDuck.txt', size: 9),
    GameListInfo(id: 'LeagueOfLegends', name: 'League Of Legends', file: 'LeagueOfLegends.txt', size: 18106),
    GameListInfo(id: 'Minecraft_Extra', name: 'Minecraft / Extra', file: 'Minecraft_Extra.txt', size: 5030),
    GameListInfo(id: 'MortalKombat1', name: 'Mortal Kombat 1', file: 'MortalKombat1.txt', size: 17),
    GameListInfo(id: 'Other_Games', name: 'Other Games', file: 'Other_Games.txt', size: 142545),
    GameListInfo(id: 'PhotonEngine', name: 'Photon Engine', file: 'PhotonEngine.txt', size: 356),
    GameListInfo(id: 'RiotGames_Valorant', name: 'Riot Games / Valorant', file: 'RiotGames_Valorant.txt', size: 7661),
    GameListInfo(id: 'Roblox', name: 'Roblox', file: 'Roblox.txt', size: 15494),
    GameListInfo(id: 'Steam', name: 'Steam', file: 'Steam.txt', size: 16499),
    GameListInfo(id: 'Ubisoft_Rainbow_Six_Siege', name: 'Ubisoft / Rainbow Six Siege', file: 'Ubisoft_Rainbow_Six_Siege.txt', size: 7834),
    GameListInfo(id: 'VRChat', name: 'VRChat', file: 'VRChat.txt', size: 1604),
    GameListInfo(id: 'Warframe', name: 'Warframe', file: 'Warframe.txt', size: 227002),
    GameListInfo(id: 'WutheringWaves', name: 'Wuthering Waves', file: 'WutheringWaves.txt', size: 1284),
  ];

  /// Canonical user data, survives portable-app and zapret replacement.
  Future<Directory> get _dir async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'zapret-games'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Absolute paths of every installed game list that exists on disk —
  /// injected as extra `--hostlist` arguments when winws starts.
  Future<List<String>> installedListPaths() async {
    final dir = await _dir;
    if (!dir.existsSync()) return const [];
    final ids = installed().map((g) => g.id).where(validId).toSet();
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt') && ids.contains(p.basenameWithoutExtension(f.path)))
        .map((f) => f.path)
        .toList()
      ..sort();
  }

  List<InstalledGame> installed() {
    final json = StorageService.instance.readJson(_installedKey);
    final items = (json?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => InstalledGame.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _saveInstalled(List<InstalledGame> items) async {
    await StorageService.instance.writeJson(
      _installedKey,
      {'items': items.map((e) => e.toJson()).toList()},
    );
  }

  /// Cached copy of the catalogue (refreshed whenever the tab is opened).
  List<GameListInfo> cachedCatalog() {
    final json = StorageService.instance.readJson(_catalogKey);
    final items = (json?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => GameListInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Lists `games/*.txt` straight from the repository, so games added
  /// upstream show up on their own. If the catalogue request is unavailable,
  /// use the last known upstream names instead of leaving the page empty.
  Future<List<GameListInfo>?> refreshCatalog() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        _contentsApi,
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': AppConstants.userAgent,
          },
          responseType: ResponseType.json,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      if (response.statusCode != 200) throw StateError('GitHub HTTP ${response.statusCode}');
      final list = (response.data ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .where((e) => e['type'] == 'file')
          .map((e) => '${e['name']}')
          .where((name) => name.endsWith('.txt') && validId(name.substring(0, name.length - 4)))
          .map((name) => GameListInfo(
                id: name.substring(0, name.length - 4),
                name: _pretty(name.substring(0, name.length - 4)),
                file: name,
                size: 0,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (list.isEmpty) throw StateError('Empty game catalogue');
      _usedFallback = false;
      await _saveCatalog(list, source: 'github');
      return list;
    } on DioException {
      return _fallbackCatalogResult();
    } on StateError catch (error) {
      final raw = '$error';
      if (raw.contains('GitHub HTTP') || raw.contains('Empty game catalogue')) {
        return _fallbackCatalogResult();
      }
      rethrow;
    }
  }

  Future<List<GameListInfo>> _fallbackCatalogResult() async {
    _usedFallback = true;
    final fallback = List<GameListInfo>.unmodifiable(_fallbackCatalog);
    await _saveCatalog(fallback, source: 'built-in');
    return fallback;
  }

  Future<void> _saveCatalog(List<GameListInfo> list, {required String source}) async {
    await StorageService.instance.writeJson(
      _catalogKey,
      {
        'items': list.map((e) => e.toJson()).toList(),
        'at': DateTime.now().toIso8601String(),
        'source': source,
      },
    );
  }

  /// `EpicGames_Fortnite` → `EpicGames / Fortnite`.
  static String _pretty(String id) {
    return id.replaceAll('_', ' / ').replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        );
  }

  /// Downloads one list, validates it and writes it as a hostlist.
  Future<GameListPreview> prepare(GameListInfo game) async {
    if (!validId(game.id) || game.file != '${game.id}.txt') throw const FormatException('Invalid game ID');
      final url = '$_rawBase/${Uri.encodeComponent(game.file)}';
      final response = await _dio.get<ResponseBody>(
        url, options: Options(responseType: ResponseType.stream, followRedirects: false),
      );
      final body = <int>[];
      await for (final chunk in response.data!.stream) {
        if (body.length + chunk.length > _maxFileBytes) throw const FormatException('List exceeds 2 MiB');
        body.addAll(chunk);
      }
      if (body.isEmpty) {
        throw const FormatException('Empty domain list');
      }
      final text = utf8.decode(body, allowMalformed: true);
      final clean = <String>[];
      var rejected = 0;
      for (final rawLine in text.split(RegExp(r'\r?\n'))) {
        final line = rawLine.trim().toLowerCase();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
        if (validDomain(line)) {
          clean.add(line);
        } else {
          rejected++;
        }
      }
      if (clean.isEmpty) throw const FormatException('Empty domain list');

      return GameListPreview(game: game, domains: clean.toSet().toList(), rejected: rejected);
  }

  Future<void> install(GameListPreview preview) async {
    final game = preview.game;
    if (!validId(game.id) || preview.domains.isEmpty || !preview.domains.every(validDomain)) {
      throw const FormatException('Invalid domain list');
    }
    final dir = await _dir;
    final file = File(p.join(dir.path, '${game.id}.txt'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString('${preview.domains.join('\n')}\n', flush: true);
    await temp.rename(file.path);
    final items = [...installed()]..removeWhere((e) => e.id == game.id);
    items.add(InstalledGame(id: game.id, name: game.name, count: preview.domains.length, updatedAt: DateTime.now()));
    await _saveInstalled(items);
  }

  static bool validDomain(String value) => _domain.hasMatch(value) &&
      !const ['exe', 'bat', 'cmd', 'ps1', 'dll', 'bin', 'txt', 'local', 'localhost', 'internal', 'test', 'invalid'].contains(value.split('.').last);

  Future<File> fileFor(String id) async {
    if (!validId(id)) throw const FormatException('Invalid game ID');
    return File(p.join((await _dir).path, '$id.txt'));
  }

  Future<List<String>> domains(String id) async {
    final file = await fileFor(id);
    return (await file.readAsLines()).where(validDomain).toList();
  }

  Future<void> addDomain(String id, String value) async {
    final domain = value.trim().toLowerCase();
    if (!validDomain(domain)) throw const FormatException('Invalid domain');
    final current = await domains(id);
    if (!current.contains(domain)) current.add(domain);
    await _writeDomains(id, current);
  }

  Future<void> removeDomain(String id, String value) async {
    final current = await domains(id);
    current.remove(value.trim().toLowerCase());
    if (current.isEmpty) throw const FormatException('A game list must contain at least one domain');
    await _writeDomains(id, current);
  }

  Future<void> restore(String id, String name) async {
    final preview = await prepare(GameListInfo(id: id, name: name, file: '$id.txt'));
    await install(preview);
  }

  Future<void> _writeDomains(String id, List<String> values) async {
    final clean = values.map((value) => value.trim().toLowerCase()).where(validDomain).toSet().toList()..sort();
    if (clean.isEmpty) throw const FormatException('Empty domain list');
    final file = await fileFor(id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString('${clean.join('\\n')}\\n', flush: true);
    await temp.rename(file.path);
    final items = [...installed()];
    final index = items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      items[index] = InstalledGame(id: items[index].id, name: items[index].name, count: clean.length, updatedAt: DateTime.now());
      await _saveInstalled(items);
    }
  }

  Future<void> openFile(String id) async {
    final file = await fileFor(id);
    if (!file.existsSync()) throw const FileSystemException('Game list file not found');
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', file.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
    } else {
      await Process.run('xdg-open', [file.path]);
    }
  }

  Future<void> openFolder() async {
    final directory = await _dir;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [directory.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [directory.path]);
    } else {
      await Process.run('xdg-open', [directory.path]);
    }
  }

  /// Re-downloads every installed list; returns how many changed.
  Future<int> refreshInstalled() async {
    final current = installed();
    var updated = 0;
    for (final game in current) {
      final info = GameListInfo(id: game.id, name: game.name, file: '${game.id}.txt');
      final before = await domains(game.id);
      final preview = await prepare(info);
      await install(preview);
      final after = await domains(game.id);
      if (before.join('\n') != after.join('\n')) updated++;
    }
    return updated;
  }

  Future<void> remove(String id) async {
    if (!validId(id)) throw const FormatException('Invalid game ID');
    final dir = await _dir;
    final file = File(p.join(dir.path, '$id.txt'));
    if (file.existsSync()) {
      await file.delete();
    }
    final items = [...installed()]..removeWhere((e) => e.id == id);
    await _saveInstalled(items);
  }
}
