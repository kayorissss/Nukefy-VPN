import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _boxName = 'nukefy_vault';
  static const _keyPref = 'nkfy_vault_key';

  Box<String>? _box;
  SharedPreferences? _prefs;

  Future<void> init() async {
    await Hive.initFlutter();
    _prefs = await SharedPreferences.getInstance();
    final key = await _encryptionKey();
    try {
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(key),
      );
    } catch (_) {
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(key),
      );
    }
  }

  Box<String> get box {
    final current = _box;
    if (current == null) {
      throw StateError('StorageService.init() was not called');
    }
    return current;
  }

  Future<List<int>> _encryptionKey() async {
    final prefs = _prefs!;
    final existing = prefs.getString(_keyPref);
    if (existing != null && existing.isNotEmpty) {
      final decoded = base64Decode(existing);
      if (decoded.length == 32) return decoded;
    }
    final generated = Hive.generateSecureKey();
    await prefs.setString(_keyPref, base64Encode(generated));
    return generated;
  }

  String? read(String key) => box.get(key);

  Future<void> write(String key, String value) => box.put(key, value);

  Future<void> remove(String key) => box.delete(key);

  Map<String, dynamic>? readJson(String key) {
    final raw = read(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<void> writeJson(String key, Object value) {
    return write(key, jsonEncode(value));
  }

  Future<void> setBootFlags({
    required bool launchOnBoot,
    required bool autoConnect,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('flutter.launch_on_boot', launchOnBoot);
    await prefs.setBool('flutter.auto_connect', autoConnect);
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/boot_flags.json');
      await file.writeAsString(jsonEncode({
        'launchOnBoot': launchOnBoot,
        'autoConnect': autoConnect,
      }));
    } catch (_) {}
  }
}
