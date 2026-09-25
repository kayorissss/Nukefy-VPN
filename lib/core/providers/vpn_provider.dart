import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../models/server_model.dart';
import '../models/vpn_status.dart';
import '../services/singbox_config_builder.dart';
import '../services/vpn_platform.dart';
import 'servers_provider.dart';
import 'settings_provider.dart';
import 'stats_provider.dart';

class VpnProvider extends ChangeNotifier {
  VpnProvider(this._platform);

  final VpnPlatform _platform;
  VpnStatus status = VpnStatus.disconnected;
  String? errorMessage;
  String? activeServerId;
  String mode = 'missing';
  CoreInfo? core;
  bool coreBusy = false;

  StatsProvider? _stats;
  ServersProvider? _servers;
  SettingsProvider? _settings;
  Timer? _ticker;
  WebSocketChannel? _traffic;
  int _sessionUp = 0;
  int _sessionDown = 0;

  ServerModel? get activeServer => _servers?.byId(activeServerId);
  String get logs => _platform.logText;

  void bind({
    required StatsProvider stats,
    required ServersProvider servers,
    required SettingsProvider settings,
  }) {
    _stats = stats;
    _servers = servers;
    _settings = settings;
    activeServerId = settings.settings.selectedServerId;
  }

  Future<void> refreshCore() async {
    core = await _platform.coreInfo();
    notifyListeners();
  }

  Future<void> toggle() async {
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect(activeServer);
    }
  }

  Future<void> connect(ServerModel? server) async {
    final settings = _settings;
    final servers = _servers;
    if (server == null || settings == null || servers == null) {
      status = VpnStatus.error;
      errorMessage = 'need-server';
      notifyListeners();
      return;
    }
    activeServerId = server.id;
    await settings.update((s) => s.selectedServerId = server.id);
    status = VpnStatus.connecting;
    errorMessage = null;
    notifyListeners();
    await refreshCore();
    final info = core;
    final forceProxy = info == null || !info.libbox && Platform.isAndroid;
    if (info == null || !info.available) {
      status = VpnStatus.error;
      errorMessage = 'CORE_MISSING';
      mode = 'missing';
      notifyListeners();
      return;
    }
    if (Platform.isAndroid && settings.settings.tunEnabled && info.libbox) {
      final ready = await _platform.prepareVpn();
      if (!ready) {
        status = VpnStatus.disconnected;
        notifyListeners();
        return;
      }
    }
    final dir = await _platform.configDirectory();
    ServerModel? detour;
    if (server.detourServerId != null) {
      detour = servers.byId(server.detourServerId);
    }
    final json = SingboxConfigBuilder.buildJson(
      server: server,
      detour: detour,
      settings: settings.settings,
      logPath: '${dir.path}/sing-box.log',
      cachePath: '${dir.path}/cache.db',
      desktopTun: !Platform.isAndroid,
      forceProxyOnly: forceProxy && !info.libbox,
    );
    final result = await _platform.start(
      configJson: json,
      preferTun: settings.settings.tunEnabled && info.libbox || !Platform.isAndroid,
    );
    if (!result.ok) {
      status = VpnStatus.error;
      errorMessage = result.error ?? 'core-failed';
      mode = result.mode;
      await _stats?.addLog(server.name, 'error', message: errorMessage);
      notifyListeners();
      return;
    }
    status = VpnStatus.connected;
    mode = result.mode;
    _sessionUp = 0;
    _sessionDown = 0;
    _stats?.startSession();
    await _stats?.addLog(server.name, 'connected', message: mode);
    _listenTraffic();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _stats?.tickDuration();
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> disconnect() async {
    final name = activeServer?.name ?? '';
    await _platform.stop();
    await _traffic?.sink.close();
    _traffic = null;
    _ticker?.cancel();
    final settings = _settings;
    if (settings != null && (_sessionUp > 0 || _sessionDown > 0)) {
      await settings.addTraffic(_sessionUp, _sessionDown);
    }
    status = VpnStatus.disconnected;
    _stats?.resetSession();
    if (name.isNotEmpty) {
      await _stats?.addLog(name, 'disconnected');
    }
    notifyListeners();
  }

  void _listenTraffic() {
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${AppConstants.clashApiPort}/traffic'),
      );
      _traffic = channel;
      channel.stream.listen((event) {
        final text = event is List<int> ? utf8.decode(event) : '$event';
        final json = jsonDecode(text);
        if (json is! Map) return;
        final up = (json['up'] as num?)?.toInt() ?? 0;
        final down = (json['down'] as num?)?.toInt() ?? 0;
        _sessionUp += up;
        _sessionDown += down;
        _stats?.applyTraffic(
          upBytesPerSecond: up,
          downBytesPerSecond: down,
          totalUp: _sessionUp,
          totalDown: _sessionDown,
        );
        if (Platform.isAndroid) {
          // Notification text is updated by the native service on the next poll.
        }
        notifyListeners();
      }, onError: (Object error) {
        _platform.appendLog('traffic: $error');
      });
    } catch (error) {
      _platform.appendLog('traffic connect: $error');
    }
  }

  Future<String> downloadCore(void Function(DownloadProgress progress) onProgress) async {
    coreBusy = true;
    notifyListeners();
    try {
      final path = await _platform.downloadCore(onProgress: onProgress);
      await refreshCore();
      return path;
    } finally {
      coreBusy = false;
      notifyListeners();
    }
  }

  Future<String> currentConfig() async {
    final server = activeServer;
    final settings = _settings?.settings;
    if (server == null || settings == null) return '{}';
    final dir = await _platform.configDirectory();
    return SingboxConfigBuilder.buildJson(
      server: server,
      detour: _servers?.byId(server.detourServerId),
      settings: settings,
      logPath: '${dir.path}/sing-box.log',
      cachePath: '${dir.path}/cache.db',
      desktopTun: !Platform.isAndroid,
      forceProxyOnly: false,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _traffic?.sink.close();
    super.dispose();
  }
}
