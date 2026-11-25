import 'package:flutter/foundation.dart';

/// Global rendering budget.
///
/// Repeating UI work (traffic ticker, log tail, pulsing indicators) is cheap
/// while the window is visible but keeps the CPU/GPU busy forever when the
/// app is minimized or in the background — the main reason an idle VPN client
/// was warming up laptops. Screens consult [visible] before scheduling
/// another repaint.
class AppPerf {
  AppPerf._();

  static bool visible = true;

  /// Mirrors the window's maximised state so the title bar can draw the right
  /// glyph. Updated by the single WindowListener in the desktop shell; the
  /// bar itself must not poll window_manager per frame.
  static final ValueNotifier<bool> maximized = ValueNotifier<bool>(false);
}
