import 'dart:io';

import 'package:flutter/services.dart';

/// Shows download progress on the OS taskbar/dock icon (like browsers do).
///
/// Uses the window_manager plugin channel directly so a missing
/// implementation on some platform degrades to a no-op instead of a crash.
class TaskbarProgress {
  static const _channel = MethodChannel('window_manager');

  static Future<void> set(double fraction) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setProgressBar', fraction.clamp(0, 1));
    } catch (_) {
      // Plugin without progress support: the in-app dialog still shows it.
    }
  }

  static Future<void> clear() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setProgressBar', -1.0);
    } catch (_) {}
  }
}
