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
}
