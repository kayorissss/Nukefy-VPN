import '../constants/app_constants.dart';
import 'vpn_status.dart';

class RoutingRule {
  RoutingRule({
    required this.id,
    required this.value,
    required this.kind,
    required this.action,
  });

  final String id;
  String value;
  String kind;
  String action;

  Map<String, dynamic> toJson() => {
        'id': id,
        'value': value,
        'kind': kind,
        'action': action,
      };

  factory RoutingRule.fromJson(Map<String, dynamic> json) {
    return RoutingRule(
      id: json['id'] as String,
      value: (json['value'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'domain_suffix',
      action: (json['action'] as String?) ?? 'proxy',
    );
  }
}

class AppSettings {
  AppSettings({
    this.theme = ThemePreference.dark,
    this.accent = 'cyan',
    this.appIcon = 'default',
    this.language = LanguagePreference.ru,
    this.seenWelcome = false,
    this.autoConnect = false,
    this.launchOnBoot = false,
    this.notifications = true,
    this.minimizeToTray = true,
    this.checkUpdatesOnStart = true,
    this.sendHwid = true,
    this.clientIdentity = 'nukefy',
    this.lastUpdateCheck,
    this.skippedVersion,
    this.routingMode = RoutingMode.bypassRu,
    this.rules = const [],
    this.blockAds = true,
    this.proxyDns = AppConstants.defaultProxyDns,
    this.directDns = AppConstants.defaultDirectDns,
    this.tunEnabled = true,
    this.tunStack = 'mixed',
    this.mtu = AppConstants.defaultMtu,
    this.localProxyEnabled = true,
    this.socksPort = AppConstants.defaultSocksPort,
    this.httpPort = AppConstants.defaultHttpPort,
    this.allowLan = false,
    this.blockQuic = false,
    this.blockIpv6 = true,
    this.logLevel = 'info',
    this.antiblock = false,
    this.preferBridge = true,
    this.tlsFragment = false,
    this.recordFragment = false,
    this.fragmentFallbackMs = 50,
    this.muxEnabled = false,
    this.muxProtocol = 'h2mux',
    this.muxMaxConnections = 4,
    this.muxPadding = false,
    this.perAppMode = PerAppMode.off,
    this.perAppPackages = const [],
    this.subscriptionUserAgent = AppConstants.userAgent,
    this.selectedServerId,
    this.allTimeUp = 0,
    this.allTimeDown = 0,
  });

  ThemePreference theme;
  String accent;
  String appIcon;
  LanguagePreference language;
  bool seenWelcome;
  bool autoConnect;
  bool launchOnBoot;
  bool notifications;
  bool minimizeToTray;
  bool checkUpdatesOnStart;
  /// Send an anonymous device id to subscription panels with device limits.
  bool sendHwid;
  /// Which client to present to subscription panels: nukefy | happ | v2rayng | hiddify | streisand.
  String clientIdentity;
  DateTime? lastUpdateCheck;
  String? skippedVersion;
  RoutingMode routingMode;
  List<RoutingRule> rules;
  bool blockAds;
  String proxyDns;
  String directDns;
  bool tunEnabled;
  String tunStack;
  int mtu;
  bool localProxyEnabled;
  int socksPort;
  int httpPort;
  bool allowLan;
  bool blockQuic;
  bool blockIpv6;
  String logLevel;
  bool antiblock;
  bool preferBridge;
  bool tlsFragment;
  bool recordFragment;
  int fragmentFallbackMs;
  bool muxEnabled;
  String muxProtocol;
  int muxMaxConnections;
  bool muxPadding;
  PerAppMode perAppMode;
  List<String> perAppPackages;
  String subscriptionUserAgent;
  String? selectedServerId;
  int allTimeUp;
  int allTimeDown;

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'accent': accent,
        'appIcon': appIcon,
        'language': language.name,
        'seenWelcome': seenWelcome,
        'autoConnect': autoConnect,
        'launchOnBoot': launchOnBoot,
        'notifications': notifications,
        'minimizeToTray': minimizeToTray,
        'checkUpdatesOnStart': checkUpdatesOnStart,
        'sendHwid': sendHwid,
        'clientIdentity': clientIdentity,
        'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
        'skippedVersion': skippedVersion,
        'routingMode': routingMode.name,
        'rules': rules.map((e) => e.toJson()).toList(),
        'blockAds': blockAds,
        'proxyDns': proxyDns,
        'directDns': directDns,
        'tunEnabled': tunEnabled,
        'tunStack': tunStack,
        'mtu': mtu,
        'localProxyEnabled': localProxyEnabled,
        'socksPort': socksPort,
        'httpPort': httpPort,
        'allowLan': allowLan,
        'blockQuic': blockQuic,
        'blockIpv6': blockIpv6,
        'logLevel': logLevel,
        'antiblock': antiblock,
        'preferBridge': preferBridge,
        'tlsFragment': tlsFragment,
        'recordFragment': recordFragment,
        'fragmentFallbackMs': fragmentFallbackMs,
        'muxEnabled': muxEnabled,
        'muxProtocol': muxProtocol,
        'muxMaxConnections': muxMaxConnections,
        'muxPadding': muxPadding,
        'perAppMode': perAppMode.name,
        'perAppPackages': perAppPackages,
        'subscriptionUserAgent': subscriptionUserAgent,
        'selectedServerId': selectedServerId,
        'allTimeUp': allTimeUp,
        'allTimeDown': allTimeDown,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      theme: _enum(ThemePreference.values, json['theme'], ThemePreference.dark),
      accent: (json['accent'] as String?) ?? 'cyan',
      appIcon: (json['appIcon'] as String?) ?? 'default',
      language: _enum(
        LanguagePreference.values,
        json['language'],
        LanguagePreference.ru,
      ),
      seenWelcome: json['seenWelcome'] == true,
      autoConnect: json['autoConnect'] == true,
      launchOnBoot: json['launchOnBoot'] == true,
      notifications: json['notifications'] != false,
      minimizeToTray: json['minimizeToTray'] != false,
      checkUpdatesOnStart: json['checkUpdatesOnStart'] != false,
      sendHwid: json['sendHwid'] != false,
      clientIdentity: (json['clientIdentity'] as String?) ?? 'nukefy',
      lastUpdateCheck: _date(json['lastUpdateCheck']),
      skippedVersion: json['skippedVersion'] as String?,
      routingMode: _enum(
        RoutingMode.values,
        json['routingMode'],
        RoutingMode.bypassRu,
      ),
      rules: (json['rules'] as List?)
              ?.whereType<Map>()
              .map((e) => RoutingRule.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v)),
                  ))
              .toList() ??
          const [],
      blockAds: json['blockAds'] != false,
      proxyDns: (json['proxyDns'] as String?) ?? AppConstants.defaultProxyDns,
      directDns:
          (json['directDns'] as String?) ?? AppConstants.defaultDirectDns,
      tunEnabled: json['tunEnabled'] != false,
      tunStack: (json['tunStack'] as String?) ?? 'mixed',
      mtu: (json['mtu'] as num?)?.toInt() ?? AppConstants.defaultMtu,
      localProxyEnabled: json['localProxyEnabled'] != false,
      socksPort:
          (json['socksPort'] as num?)?.toInt() ?? AppConstants.defaultSocksPort,
      httpPort:
          (json['httpPort'] as num?)?.toInt() ?? AppConstants.defaultHttpPort,
      allowLan: json['allowLan'] == true,
      blockQuic: json['blockQuic'] == true,
      blockIpv6: json['blockIpv6'] != false,
      logLevel: (json['logLevel'] as String?) ?? 'info',
      antiblock: json['antiblock'] == true,
      preferBridge: json['preferBridge'] != false,
      tlsFragment: json['tlsFragment'] == true,
      recordFragment: json['recordFragment'] == true,
      fragmentFallbackMs: (json['fragmentFallbackMs'] as num?)?.toInt() ?? 50,
      muxEnabled: json['muxEnabled'] == true,
      muxProtocol: (json['muxProtocol'] as String?) ?? 'h2mux',
      muxMaxConnections: (json['muxMaxConnections'] as num?)?.toInt() ?? 4,
      muxPadding: json['muxPadding'] == true,
      perAppMode:
          _enum(PerAppMode.values, json['perAppMode'], PerAppMode.off),
      perAppPackages: (json['perAppPackages'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      subscriptionUserAgent: (json['subscriptionUserAgent'] as String?) ??
          AppConstants.userAgent,
      selectedServerId: json['selectedServerId'] as String?,
      allTimeUp: (json['allTimeUp'] as num?)?.toInt() ?? 0,
      allTimeDown: (json['allTimeDown'] as num?)?.toInt() ?? 0,
    );
  }

  static T _enum<T extends Enum>(List<T> values, dynamic name, T fallback) {
    if (name is! String) return fallback;
    return values.cast<T?>().firstWhere(
          (e) => e!.name == name,
          orElse: () => fallback,
        )!;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
