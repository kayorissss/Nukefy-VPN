import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage_service.dart';

/// One `general*.bat` from Flowseal/zapret-discord-youtube, reduced to the
/// arguments it passes to `winws.exe`.
class ZapretStrategy {
  const ZapretStrategy({required this.id, required this.title, required this.file});
  final String id;
  final String title;
  final File file;
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
  bool gameFilter = false;

  /// Name of the list winws reads user domains from.
  static const String userListName = 'list-general-user.txt';
  /// The distributed list every strategy already points at.
  static const String defaultListName = 'list-general.txt';
  static const String _domainsKey = 'zapret_domains';
  static const String _placeholder = 'domain.example.abc';

  bool get isSupported => Platform.isWindows && root != null;
  bool get isRunning => _process != null;
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
      for (final f in files)
        ZapretStrategy(
          id: p.basenameWithoutExtension(f.path),
          title: _title(p.basenameWithoutExtension(f.path)),
          file: f,
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
    final gameTcp = gameFilter ? '1024-65535' : '12';
    final gameUdp = gameFilter ? '1024-65535' : '12';
    command = command
        .replaceAll('%BIN%', bin)
        .replaceAll('%LISTS%', lists)
        .replaceAll('%GameFilterTCP%', gameTcp)
        .replaceAll('%GameFilterUDP%', gameUdp)
        .replaceAll('%GameFilter%', gameTcp);
    final args = _tokenize(command);
    if (!withUserList || _userListPath == null) return args;
    if (args.any((a) => a.toLowerCase().contains(userListName.toLowerCase()))) return args;
    final out = <String>[];
    for (final arg in args) {
      out.add(arg);
      // `--hostlist="...\list-general.txt"` → also load the user domains.
      final lower = arg.toLowerCase();
      final isHostlist = lower.startsWith('--hostlist=') || lower.startsWith('--hostlist-domains=');
      if (isHostlist && lower.contains(defaultListName.toLowerCase())) {
        out.add('${arg.split('=').first}=$_userListPath');
      }
    }
    return out;
  }

  /// Absolute path of the user domain list, or null when zapret is absent.
  String? get _userListPath {
    final dir = root;
    if (dir == null) return null;
    return p.join(dir.path, 'lists', userListName);
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
    if (!isSupported) return false;
    await stop();
    lastError = null;
    _log.clear();
    try {
      _ensureUserLists();
      _writeUserList(loadDomains());
      final args = parseArgs(strategy);
      if (args.isEmpty) throw Exception('strategy has no winws arguments');
      final exe = p.join(root!.path, 'bin', 'winws.exe');
      // Any stale instance (started by the .bat manually) would hold the
      // WinDivert filter; take it over.
      await Process.run('taskkill', ['/F', '/IM', 'winws.exe']);
      final process = await Process.start(exe, args, workingDirectory: p.join(root!.path, 'bin'));
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
  }

  /// Stops winws. [sweep] also kills a stray winws started outside the app
  /// (or left over from a previous run); it costs one extra process spawn,
  /// so it is skipped when the caller knows nothing is running.
  Future<void> stop({bool sweep = true}) async {
    final process = _process;
    _process = null;
    _runningStrategyId = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 800));
      } catch (_) {}
    }
    // WinDivert driver handles survive a plain kill sometimes; make sure no
    // winws is left behind.
    if (sweep) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'winws.exe']).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    notifyListeners();
  }
}
