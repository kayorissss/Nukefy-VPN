import 'vpn_status.dart';

class SubscriptionModel {
  SubscriptionModel({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdated,
    this.autoUpdateInterval = UpdateInterval.manual,
    this.order = 0,
    this.isPinned = false,
    this.enabled = true,
    this.userAgent,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireAt,
    this.lastError,
  });

  final String id;
  String name;
  String url;
  DateTime? lastUpdated;
  UpdateInterval autoUpdateInterval;
  int order;
  bool isPinned;
  bool enabled;
  String? userAgent;
  int? uploadBytes;
  int? downloadBytes;
  int? totalBytes;
  DateTime? expireAt;
  String? lastError;

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
        'order': order,
        'isPinned': isPinned,
        'enabled': enabled,
        'userAgent': userAgent,
        'uploadBytes': uploadBytes,
        'downloadBytes': downloadBytes,
        'totalBytes': totalBytes,
        'expireAt': expireAt?.toIso8601String(),
        'lastError': lastError,
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
      order: (json['order'] as num?)?.toInt() ?? 0,
      isPinned: json['isPinned'] == true,
      enabled: json['enabled'] != false,
      userAgent: json['userAgent'] as String?,
      uploadBytes: (json['uploadBytes'] as num?)?.toInt(),
      downloadBytes: (json['downloadBytes'] as num?)?.toInt(),
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      expireAt: _date(json['expireAt']),
      lastError: json['lastError'] as String?,
    );
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
