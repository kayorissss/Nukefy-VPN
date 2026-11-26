import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/vpn_status.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../utils/format_utils.dart';
import '../../l10n/strings.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._storage);

  static const _carbonThemeMigration = 'theme_default_carbon_v255';
  static const _crimsonThemeMigration = 'theme_default_crimson_v130';
  static const _mtuMigration = 'mtu_default_1500';

  final StorageService _storage;
  AppSettings settings = AppSettings();

  S get strings {
    final code = switch (settings.language) {
      LanguagePreference.en => 'en',
      LanguagePreference.ru => 'ru',
      LanguagePreference.system =>
        PlatformDispatcher.instance.locale.languageCode == 'ru' ? 'ru' : 'en',
    };
    FormatUtils.russian = code == 'ru';
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

    // Midnight was the old default and used a cyan/violet identity. Move
    // only that legacy default once; an explicitly chosen non-default skin is
    // preserved. Unknown values are also repaired so a stale release cannot
    // silently fall back to the coloured base palette.
    var changed = false;
    if (_storage.read(_carbonThemeMigration) != '1') {
      if (settings.visualTheme == 'midnight') {
        settings.visualTheme = 'carbon';
        changed = true;
      }
      await _storage.write(_carbonThemeMigration, '1');
    }
    // The shipped default moved from the monochrome carbon skin to crimson.
    // Only the untouched default is moved: any other skin the user picked on
    // purpose (aurora, ember, ocean, midnight) survives.
    if (_storage.read(_crimsonThemeMigration) != '1') {
      if (settings.visualTheme == 'carbon') {
        settings.visualTheme = 'crimson';
        changed = true;
      }
      await _storage.write(_crimsonThemeMigration, '1');
    }
    if (!ThemePresets.all.containsKey(settings.visualTheme)) {
      settings.visualTheme = 'crimson';
      changed = true;
    }
    // 9000 was only ever the shipped default, never a meaningful user choice.
    // Move it once; a deliberate value stays as the user set it.
    if (_storage.read(_mtuMigration) != '1') {
      if (settings.mtu >= 9000) {
        settings.mtu = AppConstants.defaultMtu;
        changed = true;
      }
      await _storage.write(_mtuMigration, '1');
    }
    // Older builds wrote a pinned client version into the saved agent string.
    // A user-chosen agent (Happ, v2rayNG, …) is kept exactly as it is.
    if (settings.subscriptionUserAgent.startsWith('NukefyVPN/')) {
      final current = AppConstants.clientUserAgent;
      if (settings.subscriptionUserAgent != current) {
        settings.subscriptionUserAgent = current;
        changed = true;
      }
    }
    if (changed) await _storage.writeJson('settings', settings.toJson());
    _mirror();
    await _storage.setBootFlags(
      launchOnBoot: settings.launchOnBoot,
      autoConnect: settings.autoConnect,
      startInTray: settings.startInTray,
    );
    notifyListeners();
  }

  void _mirror() {
    SubscriptionService.sendHwid = settings.sendHwid;
    SubscriptionService.clientIdentity = settings.clientIdentity;
  }

  Future<void> update(void Function(AppSettings settings) change) async {
    change(settings);
    _mirror();
    await _storage.writeJson('settings', settings.toJson());
    await _storage.setBootFlags(
      launchOnBoot: settings.launchOnBoot,
      autoConnect: settings.autoConnect,
      startInTray: settings.startInTray,
    );
    notifyListeners();
  }

  /// Puts a whole settings snapshot back in place (used by the auto-setup
  /// undo). Goes through the same persistence path as [update] so boot flags
  /// and the mirrors stay consistent.
  Future<void> restore(AppSettings snapshot) async {
    settings = AppSettings.fromJson(snapshot.toJson());
    _mirror();
    await _storage.writeJson('settings', settings.toJson());
    await _storage.setBootFlags(
      launchOnBoot: settings.launchOnBoot,
      autoConnect: settings.autoConnect,
      startInTray: settings.startInTray,
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
