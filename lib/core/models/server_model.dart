class ServerModel {
  ServerModel({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    this.countryCode,
    this.pingMs,
    this.isPinned = false,
    this.isNew = false,
    this.tags = const [],
    this.subscriptionId,
    this.rawLink,
    this.outbound,
    this.endpoint,
    this.detourServerId,
    this.lastPingAt,
    this.createdAt,
  });

  final String id;
  String name;
  String address;
  int port;
  String protocol;
  String? countryCode;
  int? pingMs;
  bool isPinned;
  bool isNew;
  List<String> tags;
  String? subscriptionId;
  String? rawLink;
  Map<String, dynamic>? outbound;
  Map<String, dynamic>? endpoint;
  String? detourServerId;
  DateTime? lastPingAt;
  DateTime? createdAt;

  bool get isAvailable => pingMs != null && pingMs! >= 0;
  bool get isTimeout => pingMs != null && pingMs! < 0;
  bool get isBridge =>
      tags.contains('bridge') || tags.contains('antiblock');
  bool get isWireGuard =>
      protocol == 'wireguard' || protocol == 'amneziawg';

  String get fingerprint =>
      '$protocol|${address.toLowerCase()}|$port|${name.toLowerCase()}';

  ServerModel copyWith({
    String? name,
    String? address,
    int? port,
    String? protocol,
    String? countryCode,
    int? pingMs,
    bool clearPing = false,
    bool? isPinned,
    bool? isNew,
    List<String>? tags,
    String? subscriptionId,
    String? rawLink,
    Map<String, dynamic>? outbound,
    Map<String, dynamic>? endpoint,
    String? detourServerId,
    bool clearDetour = false,
    DateTime? lastPingAt,
  }) {
    return ServerModel(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      countryCode: countryCode ?? this.countryCode,
      pingMs: clearPing ? null : (pingMs ?? this.pingMs),
      isPinned: isPinned ?? this.isPinned,
      isNew: isNew ?? this.isNew,
      tags: tags ?? List<String>.from(this.tags),
      subscriptionId: subscriptionId ?? this.subscriptionId,
      rawLink: rawLink ?? this.rawLink,
      outbound: outbound ??
          (this.outbound == null
              ? null
              : Map<String, dynamic>.from(this.outbound!)),
      endpoint: endpoint ??
          (this.endpoint == null
              ? null
              : Map<String, dynamic>.from(this.endpoint!)),
      detourServerId: clearDetour ? null : (detourServerId ?? this.detourServerId),
      lastPingAt: lastPingAt ?? this.lastPingAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'port': port,
        'protocol': protocol,
        'countryCode': countryCode,
        'pingMs': pingMs,
        'isPinned': isPinned,
        'isNew': isNew,
        'tags': tags,
        'subscriptionId': subscriptionId,
        'rawLink': rawLink,
        'outbound': outbound,
        'endpoint': endpoint,
        'detourServerId': detourServerId,
        'lastPingAt': lastPingAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
      };

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    return ServerModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Server',
      address: (json['address'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 443,
      protocol: (json['protocol'] as String?) ?? 'unknown',
      countryCode: json['countryCode'] as String?,
      pingMs: (json['pingMs'] as num?)?.toInt(),
      isPinned: json['isPinned'] == true,
      isNew: json['isNew'] == true,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      subscriptionId: json['subscriptionId'] as String?,
      rawLink: json['rawLink'] as String?,
      outbound: _map(json['outbound']),
      endpoint: _map(json['endpoint']),
      detourServerId: json['detourServerId'] as String?,
      lastPingAt: _date(json['lastPingAt']),
      createdAt: _date(json['createdAt']),
    );
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
