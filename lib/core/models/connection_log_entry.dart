class ConnectionLogEntry {
  ConnectionLogEntry({
    required this.time,
    required this.serverName,
    required this.status,
    this.message,
  });

  final DateTime time;
  final String serverName;
  final String status;
  final String? message;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'serverName': serverName,
        'status': status,
        'message': message,
      };

  factory ConnectionLogEntry.fromJson(Map<String, dynamic> json) {
    return ConnectionLogEntry(
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      serverName: (json['serverName'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      message: json['message'] as String?,
    );
  }
}

class TrafficSample {
  TrafficSample({
    required this.time,
    required this.upBps,
    required this.downBps,
  });

  final DateTime time;
  final int upBps;
  final int downBps;
}
