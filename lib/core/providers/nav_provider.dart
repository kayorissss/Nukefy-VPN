import 'package:flutter/widgets.dart';

class NavProvider extends ChangeNotifier {
  int index = 0;

  void setIndex(int value) {
    if (index == value) return;
    index = value;
    notifyListeners();
  }
}
