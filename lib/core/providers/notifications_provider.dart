import 'package:flutter/widgets.dart';

enum AppNotificationKind { info, success, error }

/// One entry in the notification center (top-right stack + history).
class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.time,
    this.routeIndex,
    this.actionLabel,
    this.read = false,
  });

  final int id;
  final String title;
  final String body;
  final AppNotificationKind kind;
  final DateTime time;

  /// Main tab to open when the user taps the notification, if any.
  final int? routeIndex;
  final String? actionLabel;
  bool read;
}

/// In-app notification center: transient cards appear in the top-right
/// corner, everything is kept in a readable history behind the bell icon.
class NotificationsProvider extends ChangeNotifier {
  final List<AppNotification> items = [];

  /// Cards currently shown as floating toasts (subset of [items]).
  final List<AppNotification> visible = [];
  int _nextId = 1;

  int get unread => items.where((e) => !e.read).length;

  void push({
    required String title,
    required String body,
    AppNotificationKind kind = AppNotificationKind.info,
    int? routeIndex,
    String? actionLabel,
  }) {
    final item = AppNotification(
      id: _nextId++,
      title: title,
      body: body,
      kind: kind,
      time: DateTime.now(),
      routeIndex: routeIndex,
      actionLabel: actionLabel,
    );
    items.insert(0, item);
    if (items.length > 40) items.removeRange(40, items.length);
    visible.insert(0, item);
    if (visible.length > 3) visible.removeRange(3, visible.length);
    notifyListeners();
    Future<void>.delayed(const Duration(seconds: 6), () {
      dismiss(item.id);
    });
  }

  void dismiss(int id) {
    visible.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void markRead(int id) {
    for (final item in items) {
      if (item.id == id) item.read = true;
    }
    notifyListeners();
  }

  void markAllRead() {
    for (final item in items) {
      item.read = true;
    }
    notifyListeners();
  }

  void clearAll() {
    items.clear();
    visible.clear();
    notifyListeners();
  }
}
