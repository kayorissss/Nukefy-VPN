import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Paint, Rect, FilterQuality;
import 'package:flutter/foundation.dart' show Uint8List;

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

  /// Curated artwork for popular catalog entries, keyed by a name/id
  /// substring. `top` crops the square from the top edge (logos with a
  /// colour stripe at the bottom), otherwise the crop is centred.
  static const remoteArt = <String, (String, bool)>{
    'apex': ('https://i.pinimg.com/originals/a5/1c/07/a51c07c69088aad62886a12ac8ab957e.jpg', false),
    'rocket': ('https://avatars.mds.yandex.net/i?id=825d64e82a8701bd46d71f1adf9a5f6d_l-5228069-images-thumbs&n=13', false),
    'arkn': ('https://i.pinimg.com/originals/af/81/5f/af815f2a852beeca3ae5c161c085be7f.jpg', false),
    'arma': ('https://avatars.mds.yandex.net/i?id=269f4a013a2513e8d386b028a928b534_l-12511685-images-thumbs&n=13', false),
    'battlenet': ('https://avatars.mds.yandex.net/get-games/16511813/2a000001a00fc10182eafb6de4ecff592960/pjpg928x522', true),
    'battle.net': ('https://avatars.mds.yandex.net/get-games/16511813/2a000001a00fc10182eafb6de4ecff592960/pjpg928x522', true),
    'battlefield': ('https://yandex-images.clstorage.net/5I2aZg149/57f4e2w6BgD/ZjY9MCc5E90B3BLBfkdrQeRYA_jiyG-0MJn6GeEIZzeNGkRAoTzGM5V53C2INqL6yG94CktLmtf0dWX6pm2LEWO073YzaAWNAUxAE2iSOlLx24T7okGz__mUZhPsxz2-gp5E0PUolXQE6AdxjLy3IFwwapsVUFOFovAyZHonlkcooOUq7r2aGIyY09-0DS0cbhuA_K7DPbY3mOiWa0D_eItah119qBelTCvDsp41uKBQOeBUGNlWwm9wfCc479tGpqJj6u8w2xFFndVWeQ9lm24YBnVvzDeyMRUiGWwP9_iCGUXVNW_aLQpmy3wQM3WuVnXn1R4W0YqgdPNk_umcDuNmJGarsN3aTBnW0LgMpFQm3Y187kx9__TcJFThx_69TZyIm_hkWewIJAo9Ffe6qNT1bhTbGdnOZfd7oHZkncIk4CPqpjhfGsIZHlF2S-dY5BKFN2hD_3S6neRZ7MG3vgpUBNOyrRsnA6QBs9x1PyuY9iXb0F5Zza15PGuzY5xKa6OvLeS8XxXHmd1Sd0ep3O-TxD9uBjIyOZQtmqyLfb7CHo7SuilabojgwDXU_bDonzau1FxUF8DrObqrduTdyikoJyunuFkTQJJcFzFGppDv3IO1ZwD8_HycoBijSTgygZFIX35tHePG4wJ-EDp4otZx7Fhcn1ZFqb94ZDvlWEavKW3ubL9W201YGxz9ROkYbxgKOSoEN7f1UKQZ6I92sIhYzZn8pN3tge9JNhh1NaIdee4cltfXziqyPKq_Kd-LoW7rqqF401DKXRfffwzh1qHRTfQlzfE8u51km2kG_PKAno-S_qpf5oVsC34W9LDr2LCqGJjXl4W0YqgdPNk', false),
    'bluearchive': ('https://avatars.mds.yandex.net/i?id=c5ab58034a02c42081e8e2d304acf73b_l-8082760-images-thumbs&n=13', false),
    'blue': ('https://avatars.mds.yandex.net/i?id=c5ab58034a02c42081e8e2d304acf73b_l-8082760-images-thumbs&n=13', false),
    'dayby': ('https://avatars.mds.yandex.net/get-mpic/5366523/2a00000194d4c010c644b41d954be5c5445c/orig', false),
    'epic': ('https://avatars.mds.yandex.net/i?id=b443684fb958c5369d39920ea0522f71_l-4420863-images-thumbs&n=13', false),
    'goose': ('https://images.steamusercontent.com/ugc/1807656577914639143/7BEFB25058211979A3A44A910077120ADF49BD8E/?imw=512&imh=512&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true', false),
    'league': ('https://i.pinimg.com/originals/d1/b1/1d/d1b11d5e4dbae547ac0d651476cec488.png', false),
    'minecraft': ('https://i.pinimg.com/736x/36/ce/e4/36cee4e319e84e1640c5ae60ac1fda13.jpg', false),
    'mortal': ('https://upload.wikimedia.org/wikipedia/ru/0/0f/Mortal_kombat_logo.png', false),
    'photon': ('https://forum.godotengine.org/uploads/default/original/2X/a/aec520092bcae7ac8695f0abcb802fb4f9bb5e0d.png', false),
    'valorant': ('https://yandex-images.clstorage.net/5I2aZg149/57f4e2hPt1C/4qWup2OvENkFSxBSvodu1HGbwTzwTCv18Mu9zaDMYTVJTBHHYalFM5T4yGpd4je6nW14y4mLzxc3Ij_tIbtLEjY2uzb0PtDYQFnSwbgEatEinJH6dNoo-H4UoZCvhrj-gNJPFTRqUmbGfsw7E3km5J217FUbmNOOKTIzqjCnVc3poOSjrLWaWQgYGxK4yyaZIJZMeiMLMXrwXW-cIQM_eUIURtH359rmRK-E-Ne6NG2SNeBckVfeByx1_ip-5BcFpKFqoSp1m9RJEdIXvkLrm2gRTHmlgvB1-llpEeuMODZKlE-SNW-SIYknwrXfdLprXzvmEJbW2MirPTEu8afRA-PpL2Vt-d9UT9rbk73EKpip3gS8Lotx9bAUrNjtwbX-Q9GAF_ghXyoK5sD3HjW_r5A9ZJAfFx3Ho3n0rXljWY7iJejjanXS3M0aVZN1ReTf6tLGcybA9_oyn-KZLcy4-ArSx990aRXjSC3LdxW7di0VviiTVNgWgCN6PCM-qJyJ462noOaykFjNFVATtkbl06RWzfJnyPG__9lhkOQP-LLA0g-V_mgdZwlkQDPUPX6lmn0vU9_Xmoptd3pjuGhZDqIt5StutNNcyxPXGDcDo9KrGs29IEL4uTEXJJhpjfdwhV5MGjjl2SNO6Q4wFna6YlI3ZhSdW5pBLPI45XqnFA8noWMqJHEYW8Tb2tJwCG_Q5JJNeanOtb36XK1UbYy8tsvcRdO9I1vqjudJPF0-si0fN60cnx9QCa15u-g-aZDDoGxtbaI11ZxBUF3XfMvtmOxcg7DuA7p0PNfjma0OPT9Bnk0V_yhZ5AzsTb8fdrysmn5o1dsbXgntPHugeSYZieDqaqukNdWRjRgUUr4GqpEkWYQ4qyOn1M', true),
    'roblox': ('https://yandex-images.clstorage.net/5I2aZg149/57f4e2hPt1C/4qWup2OvENkFSxBSvodu1HGbwTzwTCv18MuojfZbYeGdmNDG9H-H89S43Ghc4-C7CHptnlwdD4L0dP_tIbiJkTe2urb0PtDYQFnSwbgEatEinJH5oMpq9CaIvRfvhTw8RtPIGT3jmOHALsm_GqVya5O0vBRc01uIp_E4Y7qrHoNgquYpbDzZ2EpRn9P0huKSJ9UJcqEAcDRxWaSVYczyMMhWT57_JZElA6NBP5h0OqhXd66dU1NXgS0-Neq_7NMDLumk4SE9V9rMkZ5etY8rlyFcxHDph3A399BlmmvI9L0C2UjR96WYZsErCfhV_HzlX7kgm55dUc0qvzMlOKQcB6GqYudmdRIeix3a3rNEIhMi2gVzKEg48nzZ5BohhTF0BJTFGf7gV-MMZcTz1j1-p574JV9RW9NNo372KjDg2YQpbupqZ7nVmIyR11YxhKwT6lvLNGtE-j10kmIVow5_NcSZyB-34xArgC2OOpT2dSeVduzd1NifTuix_W2w4xEKbqUvbWYxmtsAVpXSMYupkylYyjglwPG8NZpkUG5I_DwNWohVfePYYQoshr7Vv_5jVPDkVVsbmI5jvnFn_u5XSuhl6uonsdhQiFDW1jeNLpioHYw5Kozx83IQbVaghrk0gNiHlzhvm-7MoUL6kjKwYJa7IJKTUdHJITJxrL9rFcwqqqfroj1eUcKVHdE4RSNS7xZAO2UEcTf7nCBSa80w-ITZzFF27ZInSWfAM1I892zd8yjd3lEawSN2u-Q-4JbBbmQjJyXwUBZE0dAWvc6kV-PVwnNtyr_-vFEvm61GfjVEW03Y_K-a4Qtswj3QN_Pvn7smXFsY3whncrXkfqVWiSkrqm1ldlfQQtHQG3GG7dIhGIV6pc-4dvhf59XrxvyyTFkE0nxiWy7Eoct33n8zI522b1sRUJOFrf-yrTBsVENoqicu5TVX20va31m4zKpfatNAM68MMn_0mmgdKM', false),
    'steam': ('https://images.steamusercontent.com/ugc/914674978442492164/234BCCA1FCE231306BA731CE1C55A6255F0268B2/?imw=512&imh=512&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true', false),
    'ubisoft': ('https://cdn2.steamgriddb.com/icon/ca22348465708ade49cc72519c0bf212/32/512x512.png', false),
    'vrchat': ('https://help.vrchat.com/hc/article_attachments/45880083394195', false),
    'warframe': ('https://images.steamusercontent.com/ugc/891014885189825126/94F21E372403257A9D05906C58CDE9C0A9E651A5/?imw=512&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false', false),
    'wuthering': ('https://i.pinimg.com/736x/f4/40/19/f44019beaad79caeee3c26281106f2fb.jpg', false),
  };

  (String, bool)? _remoteFor(String gameId, String gameName) {
    final hay = '${gameId}_${gameName}'.toLowerCase();
    for (final entry in remoteArt.entries) {
      if (hay.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Fires an async lookup; the widget rebuilds when the icon lands.
  Future<String?> iconFor(String gameId, String gameName) async {
    if (_iconPathByGame.containsKey(gameId)) return _iconPathByGame[gameId];
    final cached = await _cachedIcon(gameId);
    if (cached.existsSync()) {
      _iconPathByGame[gameId] = cached.path;
      return cached.path;
    }
    final remote = _remoteFor(gameId, gameName);
    if (remote != null) {
      final out = await _cachedIcon('$gameId-remote');
      if (out.existsSync()) {
        _iconPathByGame[gameId] = out.path;
        return out.path;
      }
      final ok = await _download(remote.$1, out, topCrop: remote.$2);
      if (ok) {
        _iconPathByGame[gameId] = out.path;
        return out.path;
      }
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

  Future<bool> _download(String url, File out, {required bool topCrop}) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      client.close(force: true);
      final bytes = builder.takeBytes();
      if (bytes.length < 400) return false;
      final squared = await _square(bytes, topCrop: topCrop);
      if (squared == null) return false;
      if (!out.parent.existsSync()) out.parent.createSync(recursive: true);
      await out.writeAsBytes(squared, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Centre- (or top-) crops any image into a 256 px square PNG.
  Future<Uint8List?> _square(Uint8List bytes, {required bool topCrop}) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final side = image.width < image.height ? image.width : image.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final src = Rect.fromLTWH(
        (image.width - side) / 2,
        topCrop ? 0 : (image.height - side) / 2,
        side.toDouble(),
        side.toDouble(),
      );
      canvas.drawImageRect(image, src, const Rect.fromLTWH(0, 0, 256, 256), Paint()..filterQuality = FilterQuality.medium);
      final picture = recorder.endRecording();
      final raster = await picture.toImage(256, 256);
      final data = await raster.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      raster.dispose();
      picture.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
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
