import 'vpn_status.dart';

class SubscriptionModel {
  SubscriptionModel({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdated,
    this.autoUpdateInterval = UpdateInterval.manual,
    this.isPinned = false,
    this.enabled = true,
    this.userAgent,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireAt,
    this.lastError,
    this.hideNotices = false,
    this.receivedCount = 0,
    this.rejectedCount = 0,
    List<String>? suppressedFingerprints,
  }) : suppressedFingerprints = List<String>.from(suppressedFingerprints ?? const []);

  final String id;
  String name;
  String url;
  DateTime? lastUpdated;
  UpdateInterval autoUpdateInterval;
  bool isPinned;
  bool enabled;
  String? userAgent;
  int? uploadBytes;
  int? downloadBytes;
  int? totalBytes;
  DateTime? expireAt;
  String? lastError;
  bool hideNotices;
  int receivedCount;
  int rejectedCount;
  /// Subscription entries removed by the user stay hidden after refresh.
  /// Fingerprints are used instead of names because panel names can change.
  List<String> suppressedFingerprints;

  bool get isDue {
    if (!enabled || autoUpdateInterval == UpdateInterval.manual) return false;
    final last = lastUpdated;
    if (last == null) return true;
    return DateTime.now().difference(last).inMinutes >=
        autoUpdateInterval.minutes;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'autoUpdateInterval': autoUpdateInterval.minutes,
        'isPinned': isPinned,
        'enabled': enabled,
        'userAgent': userAgent,
        'uploadBytes': uploadBytes,
        'downloadBytes': downloadBytes,
        'totalBytes': totalBytes,
        'expireAt': expireAt?.toIso8601String(),
        'lastError': lastError,
        'hideNotices': hideNotices,
        'receivedCount': receivedCount,
        'rejectedCount': rejectedCount,
        'suppressedFingerprints': suppressedFingerprints,
      };

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Subscription',
      url: (json['url'] as String?) ?? '',
      lastUpdated: _date(json['lastUpdated']),
      autoUpdateInterval: UpdateInterval.fromMinutes(
        (json['autoUpdateInterval'] as num?)?.toInt() ?? 0,
      ),
      isPinned: json['isPinned'] == true,
      enabled: json['enabled'] != false,
      userAgent: json['userAgent'] as String?,
      uploadBytes: (json['uploadBytes'] as num?)?.toInt(),
      downloadBytes: (json['downloadBytes'] as num?)?.toInt(),
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      expireAt: _date(json['expireAt']),
      lastError: json['lastError'] as String?,
      hideNotices: json['hideNotices'] == true,
      receivedCount: (json['receivedCount'] as num?)?.toInt() ?? 0,
      rejectedCount: (json['rejectedCount'] as num?)?.toInt() ?? 0,
      suppressedFingerprints: (json['suppressedFingerprints'] as List?)
              ?.map((item) => '$item')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[],
    );
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
