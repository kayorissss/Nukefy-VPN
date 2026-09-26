import 'package:flutter/material.dart';

import '../../core/models/server_model.dart';
import '../screens/speed_test_screen.dart';

/// Kept for callers that still pass a server: the full-screen test measures
/// whatever is currently connected.
Future<void> showSpeedTest(BuildContext context, ServerModel server) {
  return Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeedTestScreen()));
}
