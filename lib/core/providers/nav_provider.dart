import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';

enum NavDestination {
  home,
  servers,
  zapret,
  speedTest,
  music,
  telegramProxy,
  jammers,
  stats,
  settings,
  settingsAppearance,
  settingsAbout,
  zapretApps,
  zapretSettings,
}

class NavProvider extends ChangeNotifier {
  NavDestination destination = NavDestination.home;
  bool collapsed = StorageService.instance.read('railCollapsed') == 'true';
  bool zapretExpanded = false;
  bool settingsExpanded = true;

  void go(NavDestination value) {
    if (destination == value) return;
    destination = value;
    if (value == NavDestination.zapretApps || value == NavDestination.zapretSettings) {
      zapretExpanded = true;
    }
    if (value == NavDestination.settingsAppearance || value == NavDestination.settingsAbout) {
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
