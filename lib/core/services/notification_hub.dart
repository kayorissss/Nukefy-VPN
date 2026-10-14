import 'package:flutter/foundation.dart';

import '../providers/nav_provider.dart';

/// One entry in the notification centre: something the app wants the user
/// to notice without gluing the text under a button forever.
class AppNotice {
  AppNotice({required this.title, required this.body, this.error = false, this.destination})
      : id = ++_seq,
        time = DateTime.now();

  static int _seq = 0;

  final int id;
  final String title;
  final String body;
  final bool error;
  final NavDestination? destination;
  final DateTime time;
}

/// In-app notification centre. Toasts appear in the top-right corner, can be
/// dismissed, and stay readable afterwards behind the bell icon — including
/// a tap-through to the page the notice is about.
class NotificationHub extends ChangeNotifier {
  NotificationHub._();

  static final NotificationHub instance = NotificationHub._();

  final List<AppNotice> items = [];
  int unread = 0;

  void show({required String title, required String body, bool error = false, NavDestination? destination}) {
    items.insert(0, AppNotice(title: title, body: body, error: error, destination: destination));
    if (items.length > 40) items.removeRange(40, items.length);
    unread++;
    notifyListeners();
  }

  void markRead() {
    if (unread == 0) return;
    unread = 0;
    notifyListeners();
  }

  void dismiss(AppNotice notice) {
    if (items.remove(notice)) notifyListeners();
  }

  void clear() {
    items.clear();
    unread = 0;
    notifyListeners();
  }
}
