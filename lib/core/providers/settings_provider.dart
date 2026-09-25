import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/vpn_status.dart';
import '../services/storage_service.dart';
import '../../l10n/strings.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._storage);

  final StorageService _storage;
  AppSettings settings = AppSettings();

  S get strings {
    final code = switch (settings.language) {
      LanguagePreference.en => 'en',
      LanguagePreference.ru => 'ru',
      LanguagePreference.system =>
        PlatformDispatcher.instance.locale.languageCode == 'ru' ? 'ru' : 'en',
    };
    return S(code);
  }

  Locale? get locale {
    return switch (settings.language) {
      LanguagePreference.en => const Locale('en'),
      LanguagePreference.ru => const Locale('ru'),
      LanguagePreference.system => null,
    };
  }

  ThemeMode get themeMode {
    return switch (settings.theme) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };
  }

  bool get isRu => strings.code == 'ru';

  Future<void> load() async {
    final json = _storage.readJson('settings');
    if (json != null) settings = AppSettings.fromJson(json);
    await _storage.setBootFlags(
      launchOnBoot: settings.launchOnBoot,
      autoConnect: settings.autoConnect,
    );
    notifyListeners();
  }

  Future<void> update(void Function(AppSettings settings) change) async {
    change(settings);
    await _storage.writeJson('settings', settings.toJson());
    await _storage.setBootFlags(
      launchOnBoot: settings.launchOnBoot,
      autoConnect: settings.autoConnect,
    );
    notifyListeners();
  }

  Future<void> addTraffic(int up, int down) async {
    settings.allTimeUp += up;
    settings.allTimeDown += down;
    await _storage.writeJson('settings', settings.toJson());
    notifyListeners();
  }

  Future<void> reset({bool keepServers = true}) async {
    final selected = keepServers ? settings.selectedServerId : null;
    final up = keepServers ? settings.allTimeUp : 0;
    final down = keepServers ? settings.allTimeDown : 0;
    settings = AppSettings(
      seenWelcome: true,
      selectedServerId: selected,
      allTimeUp: up,
      allTimeDown: down,
    );
    await _storage.writeJson('settings', settings.toJson());
    notifyListeners();
  }
}
