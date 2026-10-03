import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves real desktop icons for catalog games.
///
/// The blocklist catalog only knows domain lists, so to show a genuine game
/// icon we locate the local installation through the Windows uninstall
/// registry (DisplayName + DisplayIcon), match it against the catalog name
/// and extract the embedded icon from the `.exe` with System.Drawing.
/// Everything is cached: the registry snapshot once per session, extracted
/// PNGs on disk forever (keyed by game id).
class GameIconService {
  GameIconService._();
  static final GameIconService instance = GameIconService._();

  /// game id -> resolved executable path (empty string = looked up, nothing found).
  final Map<String, String> _exeByGame = {};
  final Map<String, String?> _iconPathByGame = {};
  Future<List<Map<String, String>>>? _registry;

  Future<Directory> cacheDir() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'game_icons'));

  /// Fires an async lookup; the widget rebuilds when the icon lands.
  Future<String?> iconFor(String gameId, String gameName) async {
    if (_iconPathByGame.containsKey(gameId)) return _iconPathByGame[gameId];
    final cached = await _cachedIcon(gameId);
    if (cached.existsSync()) {
      _iconPathByGame[gameId] = cached.path;
      return cached.path;
    }
    if (!Platform.isWindows) {
      _iconPathByGame[gameId] = null;
      return null;
    }
    final exe = await _exeFor(gameId, gameName);
    if (exe == null || exe.isEmpty) {
      _iconPathByGame[gameId] = null;
      return null;
    }
    final out = await _cachedIcon(gameId);
    final ok = await _extract(exe, out);
    _iconPathByGame[gameId] = ok ? out.path : null;
    return _iconPathByGame[gameId];
  }

  Future<File> _cachedIcon(String gameId) async =>
      File(p.join((await cacheDir()).path, '${gameId.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}.png'));

  Future<String?> _exeFor(String gameId, String gameName) async {
    if (_exeByGame.containsKey(gameId)) {
      final hit = _exeByGame[gameId];
      return hit == null || hit.isEmpty ? null : hit;
    }
    final entries = await _registrySnapshot();
    final tokens = _tokens(gameName);
    String? best;
    var bestScore = 0;
    for (final entry in entries) {
      final name = (entry['DisplayName'] ?? '').toLowerCase();
      final icon = entry['DisplayIcon'] ?? '';
      if (name.isEmpty || icon.isEmpty) continue;
      final exe = icon.split(',').first.trim();
      if (!exe.toLowerCase().endsWith('.exe') || !File(exe).existsSync()) continue;
      final shared = _tokens(name).where(tokens.contains).length;
      if (shared > bestScore) {
        bestScore = shared;
        best = exe;
      }
    }
    _exeByGame[gameId] = best ?? '';
    return best;
  }

  Set<String> _tokens(String name) => name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 4)
      .toSet();

  Future<List<Map<String, String>>> _registrySnapshot() {
    _registry ??= _queryRegistry();
    return _registry!;
  }

  Future<List<Map<String, String>>> _queryRegistry() async {
    try {
      const script = r'''
$ErrorActionPreference='SilentlyContinue'
$keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
Get-ItemProperty $keys | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayIcon | ConvertTo-Json -Compress
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      ).timeout(const Duration(seconds: 20));
      final raw = (result.stdout as String?)?.trim() ?? '';
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', '${v ?? ''}')))
            .toList();
      }
      if (decoded is Map) return [decoded.map((k, v) => MapEntry('$k', '${v ?? ''}'))];
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _extract(String exe, File out) async {
    try {
      if (!out.parent.existsSync()) out.parent.createSync(recursive: true);
      final safeExe = exe.replaceAll("'", "''");
      final safeOut = out.path.replaceAll("'", "''");
      final script = 'Add-Type -AssemblyName System.Drawing; '
          r'$i=[System.Drawing.Icon]::ExtractAssociatedIcon('
          "'$safeExe'"
          r'); if ($i) { $b=$i.ToBitmap(); $b.Save('
          "'$safeOut'"
          r',[System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); $i.Dispose() }';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      ).timeout(const Duration(seconds: 20));
      return out.existsSync() && out.lengthSync() > 200 && result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
