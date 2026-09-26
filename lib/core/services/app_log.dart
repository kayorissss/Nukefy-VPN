import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny append-only log for desktop diagnostics (startup steps, uncaught
/// errors). Lives in the app support directory as `nukefy.log`.
class AppLog {
  AppLog._();
  static File? _file;
  static final List<String> _buffer = [];

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}nukefy.log');
      if (file.existsSync() && file.lengthSync() > 512 * 1024) file.writeAsStringSync('');
      _file = file;
      for (final line in _buffer) {
        file.writeAsStringSync('$line\n', mode: FileMode.append);
      }
      _buffer.clear();
    } catch (_) {}
  }

  static void log(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    debugPrint(line);
    final file = _file;
    if (file == null) {
      _buffer.add(line);
      return;
    }
    try {
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
