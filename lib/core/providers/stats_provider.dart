import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../models/connection_log_entry.dart';
import '../services/storage_service.dart';

class StatsProvider extends ChangeNotifier {
  StatsProvider(this._storage);

  final StorageService _storage;
  final List<TrafficSample> samples = [];
  final List<ConnectionLogEntry> logs = [];
  int sessionUp = 0;
  int sessionDown = 0;
  int upBps = 0;
  int downBps = 0;
  DateTime? sessionStarted;

  Duration get sessionDuration {
    final start = sessionStarted;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  Future<void> load() async {
    final raw = _storage.read('logs');
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      logs
        ..clear()
        ..addAll(decoded.whereType<Map>().map(
              (e) => ConnectionLogEntry.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ));
    }
  }

  void startSession() {
    sessionStarted = DateTime.now();
    sessionUp = 0;
    sessionDown = 0;
    samples.clear();
    notifyListeners();
  }

  void applyTraffic({
    required int upBytesPerSecond,
    required int downBytesPerSecond,
    int? totalUp,
    int? totalDown,
  }) {
    upBps = upBytesPerSecond;
    downBps = downBytesPerSecond;
    if (totalUp != null) sessionUp = totalUp;
    if (totalDown != null) sessionDown = totalDown;
    samples.add(TrafficSample(
      time: DateTime.now(),
      upBps: upBytesPerSecond,
      downBps: downBytesPerSecond,
    ));
    if (samples.length > 120) samples.removeAt(0);
    notifyListeners();
  }

  void tickDuration() {
    if (sessionStarted != null) notifyListeners();
  }

  Future<void> addLog(String serverName, String status, {String? message}) async {
    logs.insert(
      0,
      ConnectionLogEntry(
        time: DateTime.now(),
        serverName: serverName,
        status: status,
        message: message,
      ),
    );
    if (logs.length > 50) logs.removeRange(50, logs.length);
    await _storage.write(
      'logs',
      jsonEncode(logs.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> clearLogs() async {
    logs.clear();
    await _storage.write('logs', '[]');
    notifyListeners();
  }

  void resetSession() {
    sessionStarted = null;
    upBps = 0;
    downBps = 0;
    notifyListeners();
  }
}
