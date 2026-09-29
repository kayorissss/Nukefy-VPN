import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'game_blocklist_service.dart';
import 'storage_service.dart';
import '../models/app_settings.dart';

/// One `general*.bat` from Flowseal/zapret-discord-youtube, reduced to the
/// arguments it passes to `winws.exe`.
class ZapretStrategy {
  const ZapretStrategy({
    required this.id,
    required this.title,
    required this.file,
    required this.number,
  });

  final String id;
  final String title;
  final File file;
  /// 1-based position in the ordered list — shown on the strategy tile.
  final int number;

}

/// Windows-only wrapper around zapret (`winws.exe`, WinDivert) bundled in
/// `<exe dir>/zapret/`. Runs the DPI bypass in the background, without a
/// console window and without the user touching .bat files.
class ZapretService extends ChangeNotifier {
  ZapretService._();
  static final ZapretService instance = ZapretService._();

  Process? _process;
  String? _runningStrategyId;
  String? lastError;
  final List<String> _log = [];
  final ValueNotifier<int> logRevision = ValueNotifier(0);
  /// Flowseal game filter: off | all | tcp | udp.
  String gameMode = 'off';
  /// Port ranges used for the game filter (Flowseal default: 1024-65535).
  String gameTcpRange = '1024-65535';
  String gameUdpRange = '1024-65535';

  /// Absolute paths of the installed per-game domain lists.
  List<String> gameListPaths = const [];

  /// Name of the list winws reads user domains from.
  static const String userListName = 'list-general-user.txt';
  /// The distributed list every strategy already points at.
  static const String defaultListName = 'list-general.txt';
  static const String _domainsKey = 'zapret_domains';
  static const String _placeholder = 'domain.example.abc';

  bool get isSupported => Platform.isWindows && root != null;
  bool get isRunning => _process != null || serviceRunning;
  bool servicePresent = false;
  bool serviceRunning = false;
  bool busy = false;
  bool _closing = false;

  Future<T> exclusive<T>(Future<T> Function() action) async {
    if (busy) throw StateError('zapret-busy');
    busy = true;
    notifyListeners();
    try { return await action(); }
    finally { busy = false; notifyListeners(); }
  }

  void configure(AppSettings settings) {
    gameMode = settings.zapretGameMode;
    gameTcpRange = settings.zapretGameTcp;
    gameUdpRange = settings.zapretGameUdp;
    if (!const ['off', 'all', 'tcp', 'udp'].contains(gameMode) || !validPorts(gameTcpRange) || !validPorts(gameUdpRange)) {
      throw const FormatException('Invalid game filter ports');
    }
  }

  Future<void> saveGameFilter() async {
    final dir = root;
    if (dir == null) throw StateError('zapret-missing');
    final file = File(p.join(dir.path, 'utils', 'game_filter.enabled'));
    await file.parent.create(recursive: true);
    await file.writeAsString('mode=${gameMode == 'off' ? 'disabled' : gameMode}\ntcp=$gameTcpRange\nudp=$gameUdpRange\n');
  }

  static bool validPorts(String input) => input.isNotEmpty && input.split(',').every((item) {
    if (!RegExp(r'^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$').hasMatch(item)) return false;
    final range = item.split('-').map(int.parse).toList();
    return range.every((n) => n <= 65535) && range.first <= range.last;
  });

  String? get runningStrategyId => _runningStrategyId;
  List<String> get log => List.unmodifiable(_log);

  /// `<exe dir>/zapret` when the bundle is present.
  Directory? get root {
    if (!Platform.isWindows) return null;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final dir = Directory(p.join(exeDir, 'zapret'));
    if (File(p.join(dir.path, 'bin', 'winws.exe')).existsSync()) return dir;
    return null;
  }

  List<ZapretStrategy> strategies() {
    final dir = root;
    if (dir == null) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).toLowerCase().startsWith('general') && f.path.toLowerCase().endsWith('.bat'))
        .toList()
      ..sort((a, b) => _order(a.path).compareTo(_order(b.path)));
    return [
      for (var i = 0; i < files.length; i++)
        ZapretStrategy(
          id: p.basenameWithoutExtension(files[i].path),
          title: _title(p.basenameWithoutExtension(files[i].path)),
          file: files[i],
          number: i + 1,
        ),
    ];
  }

  static int _order(String path) {
    final name = p.basenameWithoutExtension(path).toLowerCase();
    if (name == 'general') return 0;
    final m = RegExp(r'alt(\d*)').firstMatch(name);
    if (m != null) return 10 + (int.tryParse(m.group(1) ?? '') ?? 1);
    if (name.contains('fake tls auto')) return 100 + name.length;
    if (name.contains('simple fake')) return 200 + name.length;
    return 300;
  }

  static String _title(String id) {
    if (id.toLowerCase() == 'general') return 'Стандартная';
    final inner = RegExp(r'\((.*)\)').firstMatch(id)?.group(1) ?? id;
    return inner.replaceAll('ALT', 'Альтернатива ').replaceAll('  ', ' ').replaceAll('FAKE TLS AUTO', 'Fake TLS auto').replaceAll('SIMPLE FAKE', 'Simple fake').replaceAll('EXP', 'Экспериментальная').trim();
  }

  /// Extracts the `winws.exe` argument list from a .bat (joins `^`
  /// continuations, expands %BIN%/%LISTS%/game filter, keeps quoting).
  ///
  /// When [withUserList] is set, every `--hostlist` pointing at the shipped
  /// list also gets the user list next to it, so domains added in the app are
  /// desynced by every strategy — including the ones whose .bat never
  /// mentions `list-general-user.txt`.
  List<String> parseArgs(ZapretStrategy strategy, {bool withUserList = true}) {
    final dir = root!;
    final bin = '${p.join(dir.path, 'bin')}\\';
    final lists = '${p.join(dir.path, 'lists')}\\';
    final raw = strategy.file.readAsStringSync(encoding: const Utf8Codec(allowMalformed: true));
    final lines = raw.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    var collecting = false;
    for (var line in lines) {
      if (!collecting) {
        if (!line.toLowerCase().contains('winws.exe')) continue;
        collecting = true;
        line = line.substring(line.toLowerCase().indexOf('winws.exe') + 'winws.exe'.length);
        if (line.startsWith('"')) line = line.substring(1);
      }
      final trimmed = line.trimRight();
      if (trimmed.endsWith('^')) {
        buffer.write('${trimmed.substring(0, trimmed.length - 1)} ');
      } else {
        buffer.write(trimmed);
        break;
      }
    }
    var command = buffer.toString();
    // Flowseal uses the port 12 as "filter disabled"; with the game filter
    // on it swaps in the configured ranges.
    final gameTcp = (gameMode == 'off' || gameMode == 'udp') ? '12' : gameTcpRange;
    final gameUdp = (gameMode == 'off' || gameMode == 'tcp') ? '12' : gameUdpRange;
    command = command
        .replaceAll('%BIN%', bin)
        .replaceAll('%LISTS%', lists)
        .replaceAll('%GameFilterTCP%', gameTcp)
        .replaceAll('%GameFilterUDP%', gameUdp)
        .replaceAll('%GameFilter%', gameMode == 'udp' ? gameUdp : gameTcp);
    final args = _tokenize(command);
    if (!withUserList || _userListPath == null) return args;

    return withHostlists(args, userList: _userListPath!, gameLists: gameListPaths);
  }

  static List<String> withHostlists(List<String> args, {required String userList, required List<String> gameLists}) {
    final out = <String>[];
    // Hostlist presence must be checked per --new profile, not globally.
    var profile = <String>[];
    void appendProfile() {
      final hasUser = profile.any((a) => a.startsWith('--hostlist=') && a.toLowerCase().contains(userListName));
      for (final arg in profile) {
        out.add(arg);
        if (arg.startsWith('--hostlist=') && arg.toLowerCase().contains(defaultListName)) {
          if (!hasUser) out.add('--hostlist=$userList');
          for (final path in gameLists) { out.add('--hostlist=$path'); }
        }
      }
      profile = [];
    }
    for (final arg in args) {
      if (arg == '--new') { appendProfile(); out.add(arg); }
      else { profile.add(arg); }
    }
    appendProfile();
    return out;
  }

  /// Absolute path of the user domain list, or null when zapret is absent.
  String? get _userListPath {
    final dir = root;
    if (dir == null) return null;
    return p.join(dir.path, 'lists', userListName);
  }

  /// Re-reads the installed game lists from disk; safe to call often.
  Future<void> refreshGameLists() async {
    final next = await GameBlocklistService.instance.installedListPaths();
    if (next.length == gameListPaths.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i] != gameListPaths[i]) same = false;
      }
      if (same) return;
    }
    gameListPaths = next;
    notifyListeners();
  }

  /// Domains the user asked to unblock ("добавить домен для обхода").
  ///
  /// Kept in the app storage and mirrored into the zapret list file, so it
  /// survives a reinstall of the app (unlike the .txt next to winws).
  List<String> loadDomains() {
    final json = StorageService.instance.readJson(_domainsKey);
    var items = <String>[];
    final stored = (json?['items'] as List?) ?? const [];
    items = stored.whereType<String>().map(normalizeDomain).where((e) => e.isNotEmpty).toList();
    if (items.isEmpty) {
      // First run after an upgrade: adopt whatever is already in the file.
      final file = _userListPath;
      if (file != null && File(file).existsSync()) {
        items = File(file)
            .readAsStringSync(encoding: const Utf8Codec(allowMalformed: true))
            .split(RegExp(r'\r?\n'))
            .map(normalizeDomain)
            .where((e) => e.isNotEmpty && e != _placeholder)
            .toList();
      }
    }
    return items;
  }

  Future<void> saveDomains(List<String> domains) async {
    final clean = domains.map(normalizeDomain).where((e) => e.isNotEmpty).toList();
    await StorageService.instance.writeJson(_domainsKey, {'items': clean});
    _writeUserList(clean);
    notifyListeners();
  }

  /// `https://Aniwids.fun/watch` → `aniwids.fun`. Empty when there is
  /// nothing domain-like left.
  static String normalizeDomain(String value) {
    var text = value.trim().toLowerCase();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'^https?://'), '');
    text = text.split(RegExp(r'[/?#\s]')).first;
    text = text.replaceAll(RegExp(r'^www\.'), '');
    return text.trim();
  }

  /// Rough shape check for the "add domain" dialog.
  static bool looksLikeDomain(String value) {
    return RegExp(r'^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$').hasMatch(value);
  }

  // ═══ Version ═══════════════════════════════════════════════════════════

  /// `service.bat` carries `set "LOCAL_VERSION=1.10.3"`; the release workflow
  /// also drops the archive name into VERSION.txt.
  String? get version {
    final dir = root;
    if (dir == null) return null;
    final tagged = File(p.join(dir.path, 'VERSION.txt'));
    if (tagged.existsSync()) {
      final match = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(
        String.fromCharCodes(tagged.readAsBytesSync().where((b) => b != 0)).trim(),
      );
      if (match != null) return match.group(1);
    }
    final bat = File(p.join(dir.path, 'service.bat'));
    if (bat.existsSync()) {
      final text = bat.readAsStringSync(encoding: const Utf8Codec(allowMalformed: true));
      final match = RegExp(r'LOCAL_VERSION=([^"\r\n]+)').firstMatch(text);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  // ═══ IPSet filter (Flowseal: any | loaded | none) ═════════════════════

  static const String _ipsetStub = '203.0.113.113/32';
  static const String _ipsetUrl =
      'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt';

  String? get _ipsetPath {
    final dir = root;
    if (dir == null) return null;
    return p.join(dir.path, 'lists', 'ipset-all.txt');
  }

  /// `any` — empty list (bypass everything), `loaded` — the real list,
  /// `none` — stub entry, nothing matches.
  String ipsetMode() {
    final path = _ipsetPath;
    if (path == null) return 'any';
    final file = File(path);
    if (!file.existsSync()) return 'any';
    final lines = file
        .readAsStringSync(encoding: const Utf8Codec(allowMalformed: true))
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
    if (lines.isEmpty) return 'any';
    if (lines.any((e) => e.contains(_ipsetStub))) return 'none';
    return 'loaded';
  }

  Future<void> setIpsetMode(String mode) async {
    if (!const ['none', 'any', 'loaded'].contains(mode)) throw ArgumentError.value(mode);
    final path = _ipsetPath;
    if (path == null) throw StateError('zapret-missing');
    final file = File(path);
    final backup = File('$path.backup');
    final current = ipsetMode();
    if (current == mode) return;
    if (current == 'loaded') await file.copy(backup.path);
    if (mode == 'loaded') {
      if (!await backup.exists()) throw StateError('ipset-backup-missing');
      await backup.copy(path);
    } else {
      await file.writeAsString(mode == 'none' ? '$_ipsetStub\n' : '');
    }
    notifyListeners();
  }

  Future<void> updateIpsetList() async {
    final path = _ipsetPath;
    if (path == null) throw StateError('zapret-missing');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
    ));
    try {
      final response = await dio.get<String>(_ipsetUrl, options: Options(responseType: ResponseType.plain));
      final clean = <String>[];
      for (final line in response.data!.split('\n')) {
        final value = line.split('#').first.trim();
        if (value.isEmpty) continue;
        if (!validIpOrCidr(value)) throw const FormatException('Invalid IPSet list');
        clean.add(value);
      }
      if (clean.isEmpty) throw const FormatException('Empty IPSet list');
      // Updating a list must not silently enable a disabled filter.
      final destination = ipsetMode() == 'loaded' ? path : '$path.backup';
      await File(destination).writeAsString('${clean.toSet().join('\n')}\n');
      notifyListeners();
    } finally { dio.close(); }
  }

  static bool validIpOrCidr(String value) {
    final parts = value.split('/');
    if (parts.length > 2) return false;
    final ip = InternetAddress.tryParse(parts.first);
    if (ip == null) return false;
    if (parts.length == 1) return true;
    final bits = int.tryParse(parts.last);
    return bits != null && bits >= 0 && bits <= (ip.type == InternetAddressType.IPv4 ? 32 : 128);
  }

  // ═══ Fake files (Discord / game UDP) ══════════════════════════════════

  /// Every `*.bin` in `bin/` except the two active ones.
  List<String> fakeFiles() {
    final dir = root;
    if (dir == null) return const [];
    final bin = Directory(p.join(dir.path, 'bin'));
    if (!bin.existsSync()) return const [];
    return bin
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.bin'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .where((name) => !name.toUpperCase().startsWith('ACTIVE_'))
        .toList()
      ..sort();
  }

  /// `discord` → bin/ACTIVE_DISCORD_UDP.bin, `game` → bin/ACTIVE_GAME_UDP.bin.
  String? activeFake(String kind) {
    final dir = root;
    if (dir == null) return null;
    final target = File(p.join(dir.path, 'bin', kind == 'game' ? 'ACTIVE_GAME_UDP.bin' : 'ACTIVE_DISCORD_UDP.bin'));
    if (!target.existsSync()) return null;
    final hash = _md5Of(target);
    for (final name in fakeFiles()) {
      final candidate = File(p.join(dir.path, 'bin', '$name.bin'));
      if (_md5Of(candidate) == hash) return name;
    }
    return null;
  }

  String _md5Of(File file) => md5.convert(file.readAsBytesSync()).toString();

  Future<void> setActiveFake(String kind, String name) async {
    if (!const ['discord', 'game'].contains(kind) || !fakeFiles().contains(name)) {
      throw ArgumentError('Unknown fake');
    }
    final bin = p.join(root!.path, 'bin');
    await File(p.join(bin, '$name.bin')).copy(p.join(bin, kind == 'game' ? 'ACTIVE_GAME_UDP.bin' : 'ACTIVE_DISCORD_UDP.bin'));
    notifyListeners();
  }

  Future<int?> _serviceState() async {
    final result = await Process.run('sc.exe', ['query', 'zapret']);
    if (result.exitCode == 1060) return null;
    if (result.exitCode != 0) throw ProcessException('sc.exe', ['query', 'zapret'], '${result.stderr} ${result.stdout}', result.exitCode);
    // STATE is followed by its numeric value even on localized Windows.
    final match = RegExp(r'^\s*[^:\r\n]+:\s+([1-7])\s+[A-Z_]+', multiLine: true).firstMatch('${result.stdout}');
    if (match == null) throw const FormatException('Unrecognized service state');
    return int.parse(match.group(1)!);
  }

  Future<bool> serviceInstalled() async {
    if (!Platform.isWindows) return false;
    final state = await _serviceState();
    servicePresent = state != null;
    serviceRunning = state == 4;
    if (serviceRunning && _runningStrategyId == null) {
      _runningStrategyId = StorageService.instance.read('zapret_service_strategy');
    }
    notifyListeners();
    return servicePresent;
  }

  Future<void> _sc(List<String> args) async {
    final result = await Process.run('sc.exe', args);
    if (result.exitCode != 0) throw ProcessException('sc.exe', args, '${result.stdout} ${result.stderr}', result.exitCode);
  }

  Future<void> _stopService() async {
    var state = await _serviceState();
    if (state == null || state == 1) { serviceRunning = false; return; }
    if (state != 3) await _sc(['stop', 'zapret']);
    final clock = Stopwatch()..start();
    while (state != 1 && state != null) {
      if (clock.elapsed > const Duration(seconds: 15)) throw StateError('Service did not stop');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = await _serviceState();
    }
    serviceRunning = false;
  }

  Future<void> _startService() async {
    await _sc(['start', 'zapret']);
    final clock = Stopwatch()..start();
    while (true) {
      final state = await _serviceState();
      if (state == 4) break;
      if (state == null || state == 1) throw StateError('zapret service stopped during startup');
      if (clock.elapsed > const Duration(seconds: 15)) throw StateError('zapret service did not reach RUNNING');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await serviceInstalled();
  }

  String _serviceCommand(ZapretStrategy strategy) {
    final args = parseArgs(strategy);
    if (args.isEmpty) throw StateError('Empty strategy');
    return '"${p.join(root!.path, 'bin', 'winws.exe')}" ${args.map((a) => '"$a"').join(' ')}';
  }

  Future<void> installService(ZapretStrategy strategy) async {
    await stop();
    _ensureUserLists();
    _writeUserList(loadDomains());
    await refreshGameLists();
    if (await serviceInstalled()) throw StateError('Service already installed');
    await _sc(['create', 'zapret', 'binPath=', _serviceCommand(strategy), 'start=', 'auto', 'DisplayName=', 'zapret (Nukefy VPN)']);
    servicePresent = true;
    await _startService();
    _runningStrategyId = strategy.id;
    await StorageService.instance.write('zapret_service_strategy', strategy.id);
  }

  Future<void> removeService() async {
    await _stopService();
    await _sc(['delete', 'zapret']);
    await StorageService.instance.remove('zapret_service_strategy');
    servicePresent = false;
    serviceRunning = false;
    _runningStrategyId = null;
    notifyListeners();
  }

  // ═══ Tools ════════════════════════════════════════════════════════════

  /// Opens the zapret folder in Explorer.
  Future<void> openFolder() async {
    final dir = root;
    if (dir == null) throw StateError('zapret-missing');
    await Process.run('explorer.exe', [dir.path]);
  }

  /// Save a reviewed proposal, never overwrite the system hosts file.
  Future<String> hostsProposal() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
    ));
    try {
      final response = await dio.get<String>(
        'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts',
        options: Options(responseType: ResponseType.plain),
      );
      final text = response.data!;
      for (final raw in text.split('\n')) {
        final line = raw.split('#').first.trim();
        if (line.isEmpty) continue;
        final items = line.split(RegExp(r'\s+'));
        if (items.length < 2 || InternetAddress.tryParse(items.first) == null || !items.skip(1).every(looksLikeDomain)) {
          throw const FormatException('Invalid hosts list');
        }
      }
      return text;
    } finally { dio.close(); }
  }

  /// Changes only our marked block, after the user reviews the proposal.
  /// A byte-for-byte backup of the original file is kept beside hosts.
  Future<void> applyHosts(String proposal) async {
    final entries = <String>[];
    for (final raw in proposal.split('\n')) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      final items = line.split(RegExp(r'\s+'));
      if (items.length < 2 || InternetAddress.tryParse(items.first) == null || !items.skip(1).every(looksLikeDomain)) {
        throw const FormatException('Invalid hosts list');
      }
      entries.add(items.join(' '));
    }
    if (entries.isEmpty) throw const FormatException('Empty hosts proposal');
    final windows = Platform.environment['SystemRoot'];
    if (windows == null) throw StateError('SystemRoot missing');
    final hosts = File(p.join(windows, 'System32', 'drivers', 'etc', 'hosts'));
    final original = await hosts.readAsBytes();
    const begin = '# BEGIN NUKEFY ZAPRET';
    const end = '# END NUKEFY ZAPRET';
    final text = latin1.decode(original);
    final clean = text.replaceAll(RegExp('$begin[\\s\\S]*?$end\\r?\\n?'), '');
    await File('${hosts.path}.nukefy-${DateTime.now().microsecondsSinceEpoch}.bak').writeAsBytes(original, flush: true);
    await hosts.writeAsString('$clean\r\n$begin\r\n${entries.join('\r\n')}\r\n$end\r\n', encoding: latin1, flush: true);
  }

  /// Applies an explicitly selected block list to the marked hosts section.
  /// This is deliberately separate from the downloaded Flowseal proposal so
  /// the user can see which domains are being blocked and confirm the admin
  /// operation. It never touches Defender or firewall policy.
  Future<void> applyHostBlock(List<String> domains) async {
    final clean = domains
        .map((domain) => domain.trim().toLowerCase())
        .where(looksLikeDomain)
        .toSet()
        .toList();
    if (clean.isEmpty) throw const FormatException('Empty hosts block');
    final windows = Platform.environment['SystemRoot'];
    if (windows == null) throw StateError('SystemRoot missing');
    final hosts = File(p.join(windows, 'System32', 'drivers', 'etc', 'hosts'));
    final original = await hosts.readAsBytes();
    const begin = '# BEGIN NUKEFY ZAPRET';
    const end = '# END NUKEFY ZAPRET';
    final text = latin1.decode(original);
    final cleanText = text.replaceAll(RegExp('$begin[\\s\\S]*?$end\r?\n?'), '');
    await File('${hosts.path}.nukefy-${DateTime.now().microsecondsSinceEpoch}.bak').writeAsBytes(original, flush: true);
    await hosts.writeAsString(
      '$cleanText\r\n$begin\r\n${clean.map((domain) => '0.0.0.0 $domain').join('\r\n')}\r\n$end\r\n',
      encoding: latin1,
      flush: true,
    );
  }

  /// Short health report: what is loaded, what is running, what is missing.
  Future<String> diagnostics() async {
    final lines = <String>[];
    final dir = root;
    lines.add('zapret: ${version ?? '—'}');
    lines.add('path: ${dir?.path ?? '—'}');
    if (dir == null) return lines.join('\n');
    lines.add('winws.exe: ${File(p.join(dir.path, 'bin', 'winws.exe')).existsSync() ? 'ok' : 'MISSING'}');
    final drivers = Directory(p.join(dir.path, 'bin')).existsSync()
        ? Directory(p.join(dir.path, 'bin')).listSync().whereType<File>().where((f) => f.path.endsWith('.sys')).length
        : 0;
    lines.add('WinDivert .sys: $drivers');
    lines.add('ipset filter: ${ipsetMode()}');
    lines.add('game filter: $gameMode (tcp: ${gameTcpRange.isEmpty ? '12' : gameTcpRange}, udp: ${gameUdpRange.isEmpty ? '12' : gameUdpRange})');
    lines.add('service: ${await serviceInstalled() ? 'installed' : 'not installed'}');
    lines.add('running: ${isRunning ? 'yes' : 'no'}');
    if (Platform.isWindows) {
      final ts = await Process.run('netsh', ['interface', 'tcp', 'show', 'global']);
      final text = '${ts.stdout}';
      lines.add('tcp timestamps: ${text.toLowerCase().contains('timestamps') && text.toLowerCase().contains('enabled') ? 'enabled' : 'disabled'}');
    }
    return lines.join('\n');
  }

  /// Mirrors utils/check_updates.enabled — zapret's own updater flag.
  bool get autoUpdateCheck {
    final dir = root;
    if (dir == null) return false;
    return File(p.join(dir.path, 'utils', 'check_updates.enabled')).existsSync();
  }

  Future<void> setAutoUpdateCheck(bool enabled) async {
    final dir = root;
    if (dir == null) return;
    final file = File(p.join(dir.path, 'utils', 'check_updates.enabled'));
    if (enabled) {
      await file.parent.create(recursive: true);
      await file.writeAsString('ENABLED');
    } else if (await file.exists()) {
      await file.delete();
    }
    notifyListeners();
  }

  /// winws refuses to start when a hostlist file is missing or empty, so the
  /// placeholder stays until the user adds a real domain.
  void _writeUserList(List<String> domains) {
    final path = _userListPath;
    if (path == null) return;
    final file = File(path);
    final body = StringBuffer('# Nukefy VPN — your domains (one per line)\n');
    if (domains.isEmpty) {
      body.writeln(_placeholder);
    } else {
      for (final domain in domains) {
        body.writeln(domain);
      }
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(body.toString());
  }

  static List<String> _tokenize(String input) {
    final out = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"') {
        quoted = !quoted;
        continue;
      }
      if (!quoted && (ch == ' ' || ch == '\t')) {
        if (current.isNotEmpty) {
          out.add(current.toString());
          current.clear();
        }
        continue;
      }
      current.write(ch);
    }
    if (current.isNotEmpty) out.add(current.toString());
    return out;
  }

  /// The user-list files referenced by the strategies must exist (winws
  /// exits when a --hostlist file is missing). Mirrors service.bat.
  void _ensureUserLists() {
    final lists = Directory(p.join(root!.path, 'lists'));
    final defaults = {
      'ipset-exclude-user.txt': '203.0.113.113/32\n',
      'list-general-user.txt': '# Never leave this file empty\ndomain.example.abc\n',
      'list-exclude-user.txt': 'domain.example.abc\n',
    };
    for (final entry in defaults.entries) {
      final f = File(p.join(lists.path, entry.key));
      if (!f.existsSync()) f.writeAsStringSync(entry.value);
    }
  }

  Future<bool> start(ZapretStrategy strategy) async {
    if (!isSupported || _closing) return false;
    await stop();
    if (_closing) return false;
    lastError = null;
    _append('> ${strategy.id}');
    try {
      _ensureUserLists();
      _writeUserList(loadDomains());
      await refreshGameLists();
      if (_closing) return false;
      if (servicePresent) {
        await _sc(['config', 'zapret', 'binPath=', _serviceCommand(strategy)]);
        await _startService();
        _runningStrategyId = strategy.id;
        await StorageService.instance.write('zapret_service_strategy', strategy.id);
        return serviceRunning;
      }
      final args = parseArgs(strategy);
      if (args.isEmpty) throw Exception('strategy has no winws arguments');
      final exe = p.join(root!.path, 'bin', 'winws.exe');
      final process = await Process.start(exe, args, workingDirectory: p.join(root!.path, 'bin'));
      if (_closing) { process.kill(); await process.exitCode; return false; }
      _process = process;
      _runningStrategyId = strategy.id;
      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_append);
      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_append);
      unawaited(process.exitCode.then((code) {
        if (_process == process) {
          _process = null;
          _runningStrategyId = null;
          if (code != 0) {
            lastError = _log.isEmpty ? 'winws exited with code $code' : _log.last;
          }
          notifyListeners();
        }
      }));
      // Give it a moment: a missing driver / no admin rights fails instantly.
      await Future.delayed(const Duration(milliseconds: 900));
      if (_process == null) {
        lastError ??= 'winws exited immediately';
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '$error';
      _process = null;
      _runningStrategyId = null;
      notifyListeners();
      return false;
    }
  }

  void _append(String line) {
    _log.add(line);
    if (_log.length > 200) _log.removeAt(0);
    logRevision.value++;
  }

  /// Prevent an in-flight analysis from spawning another child on exit.
  Future<void> shutdown() async {
    _closing = true;
    await stop();
  }

  /// Stops only our process or the explicitly managed zapret service.
  Future<void> stop() async {
    final process = _process;
    _process = null;
    _runningStrategyId = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 800));
      } on TimeoutException {
        final killed = await Process.run('taskkill', ['/F', '/PID', '${process.pid}']);
        if (killed.exitCode != 0) throw StateError('Cannot stop winws: ${killed.stdout}');
        await process.exitCode;
      }
    }
    if (servicePresent && serviceRunning) await _stopService();
    notifyListeners();
  }
}
