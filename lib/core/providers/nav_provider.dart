import 'package:flutter/widgets.dart';
import '../services/storage_service.dart';

class NavProvider extends ChangeNotifier {
  int index = 0;
  bool collapsed = StorageService.instance.read('railCollapsed') == 'true';
  bool zapretExpanded = false;

  void setIndex(int value) {
    if (index == value) return;
    index = value;
    notifyListeners();
  }

  Future<void> toggleRail() async {
    collapsed = !collapsed;
    notifyListeners();
    await StorageService.instance.write('railCollapsed', '$collapsed');
  }

  void toggleZapret() { zapretExpanded = !zapretExpanded; notifyListeners(); }
}
