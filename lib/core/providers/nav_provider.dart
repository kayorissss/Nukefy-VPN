import 'package:flutter/widgets.dart';

/// Main tab indices, shared by the desktop sidebar and the mobile bar.
class NavTabs {
  static const int home = 0;
  static const int servers = 1;
  static const int analysis = 2;
  static const int stats = 3;
  static const int settings = 4;
}

class NavProvider extends ChangeNotifier {
  int index = 0;

  void setIndex(int value) {
    if (index == value) return;
    index = value;
    notifyListeners();
  }

  void goHome() => setIndex(NavTabs.home);
  void goServers() => setIndex(NavTabs.servers);
  void goAnalysis() => setIndex(NavTabs.analysis);
  void goStats() => setIndex(NavTabs.stats);
  void goSettings() => setIndex(NavTabs.settings);
}
