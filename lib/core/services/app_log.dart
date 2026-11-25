import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny append-only log for desktop diagnostics (startup steps, uncaught
/// errors). Lives in the app support directory as `nukefy.log`.
class AppLog {
  AppLog._();
  static File? _file;
  static final List<String> _buffer = [];

  /// Keeps the diagnostic log bounded. Long uptimes with a chatty core used to
  /// turn it into a multi-megabyte file that was re-read on every crash report.
  static const int maxBytes = 512 * 1024;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}nukefy.log');
      if (file.existsSync() && file.lengthSync() > maxBytes) file.writeAsStringSync('');
      _file = file;
      for (final line in _buffer) {
        file.writeAsStringSync('$line\n', mode: FileMode.append);
      }
      _buffer.clear();
    } catch (_) {}
  }

  static void log(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    // debugPrint in release builds still formats and forwards every line to
    // the platform log; a chatty session paid for it on the UI isolate.
    if (kDebugMode) debugPrint(line);
    final file = _file;
    if (file == null) {
      _buffer.add(line);
      return;
    }
    try {
      if (file.lengthSync() > maxBytes) file.writeAsStringSync('');
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  static String? get path => _file?.path;

  static String read() {
    try {
      return _file?.readAsStringSync() ?? _buffer.join('\n');
    } catch (_) {
      return '';
    }
  }
}
