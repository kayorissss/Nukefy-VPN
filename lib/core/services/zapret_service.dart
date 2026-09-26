import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
  List<String> parseArgs(ZapretStrategy strategy) {
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
    return _tokenize(command);
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

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _runningStrategyId = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    // WinDivert driver handles survive a plain kill sometimes; make sure no
    // winws is left behind.
    try {
      await Process.run('taskkill', ['/F', '/IM', 'winws.exe']);
    } catch (_) {}
    notifyListeners();
  }
}
