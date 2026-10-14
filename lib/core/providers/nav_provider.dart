import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';

enum NavDestination {
  home,
  servers,
  zapret,
  karing,
  speedTest,
  telegramProxy,
  jammers,
  diagnostics,
  stats,
  addons,
  autotune,
  dns,
  settings,
  settingsGeneral,
  settingsAppearance,
  settingsDns,
  settingsAbout,
  zapretApps,
  zapretSettings,
}

class NavProvider extends ChangeNotifier {
  NavProvider() {
    _pins = _readPins();
  }

  NavDestination destination = NavDestination.home;
  bool collapsed = StorageService.instance.read('railCollapsed') == 'true';
  bool zapretExpanded = false;
  bool settingsExpanded = false;

  /// How many pages the user can keep in the navigation bars by hand.
  static const int maxPins = 3;

  List<NavDestination> _pins = <NavDestination>[];

  /// Pages the user pinned from the section map, oldest first. The order is
  /// what the bars render, so pinning is a deliberate choice, not a set.
  List<NavDestination> get pins => List.unmodifiable(_pins);

  bool isPinned(NavDestination value) => _pins.contains(value);

  /// The label of a pinned destination is resolved by the shell (it owns the
  /// strings), so the index is what the bars use to keep pins in order.
  int pinIndex(NavDestination value) => _pins.indexOf(value);

  /// Returns false when the tap was rejected because the map is full.
  bool togglePin(NavDestination value) {
    if (_pins.contains(value)) {
      _pins.remove(value);
    } else {
      if (_pins.length >= maxPins) return false;
      _pins.add(value);
    }
    _writePins();
    notifyListeners();
    return true;
  }

  static List<NavDestination> _readPins() {
    final raw = StorageService.instance.read('pinnedNav');
    if (raw == null || raw.isEmpty) return <NavDestination>[];
    final out = <NavDestination>[];
    for (final name in raw.split(',')) {
      for (final value in NavDestination.values) {
        if (value.name == name && !out.contains(value) && out.length < maxPins) out.add(value);
      }
    }
    return out;
  }

  Future<void> _writePins() {
    return StorageService.instance.write('pinnedNav', _pins.map((value) => value.name).join(','));
  }

  void go(NavDestination value) {
    if (destination == value) {
      if (value == NavDestination.settings && !settingsExpanded) {
        settingsExpanded = true;
        notifyListeners();
      }
      return;
    }
    destination = value;
    if (value == NavDestination.zapretApps || value == NavDestination.zapretSettings) {
      zapretExpanded = true;
    }
    if (value == NavDestination.settings || value == NavDestination.settingsGeneral || value == NavDestination.settingsAppearance || value == NavDestination.settingsAbout) {
      settingsExpanded = true;
    }
    notifyListeners();
  }

  /// Kept as a small compatibility bridge for screens that receive an index
  /// from an older caller. New navigation uses named destinations.
  void setIndex(int value) {
    const legacy = <NavDestination>[
      NavDestination.home,
      NavDestination.servers,
      NavDestination.zapret,
      NavDestination.jammers,
      NavDestination.stats,
      NavDestination.settings,
      NavDestination.zapretApps,
      NavDestination.zapretSettings,
    ];
    if (value >= 0 && value < legacy.length) go(legacy[value]);
  }

  Future<void> toggleRail() async {
    collapsed = !collapsed;
    notifyListeners();
    await StorageService.instance.write('railCollapsed', '$collapsed');
  }

  void toggleZapret() {
    zapretExpanded = !zapretExpanded;
    notifyListeners();
  }

  void toggleSettings() {
    settingsExpanded = !settingsExpanded;
    notifyListeners();
  }
}
