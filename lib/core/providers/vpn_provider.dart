import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';
import '../models/vpn_status.dart';
import '../services/clash_api.dart';
import '../services/singbox_config_builder.dart';
import '../services/xray_config_builder.dart';
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

  /// Engine serving the current session: 'singbox' or 'xray' (XHTTP).
  String engine = 'singbox';
  CoreInfo? core;
  bool coreBusy = false;

  StatsProvider? _stats;
  ServersProvider? _servers;
  SettingsProvider? _settings;
  Timer? _ticker;
  Timer? _xrayTicker;
  WebSocketChannel? _traffic;
  int _sessionUp = 0;
  int _sessionDown = 0;
  int _lastXrayUp = 0;
  int _lastXrayDown = 0;
  DateTime? _lastXrayPoll;

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

    // XHTTP/SplitHTTP servers cannot run on sing-box at all (no such
    // transport), so they are served by the bundled Xray engine.
    if (server.isXhttp) {
      await _connectXray(server, settings.settings);
      return;
    }

    final forceProxy = info == null || !info.libbox && Platform.isAndroid;
    if (info == null || !info.available) {
      status = VpnStatus.error;
      errorMessage = 'CORE_MISSING';
      mode = 'missing';
      notifyListeners();
      return;
    }
    engine = 'singbox';
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
    final fallbackJson = SingboxConfigBuilder.buildJson(
      server: server,
      detour: detour,
      settings: settings.settings,
      logPath: '${dir.path}/sing-box.log',
      cachePath: '${dir.path}/cache.db',
      desktopTun: !Platform.isAndroid,
      forceProxyOnly: forceProxy && !info.libbox,
      remoteRuleSets: false,
    );
    final result = await _platform.start(
      configJson: json,
      preferTun: settings.settings.tunEnabled && info.libbox || !Platform.isAndroid,
      fallbackConfigJson: fallbackJson,
    );
    if (!result.ok) {
      status = VpnStatus.error;
      errorMessage = result.error ?? 'core-failed';
      mode = result.mode;
      await _stats?.addLog(server.name, 'error', message: errorMessage);
      notifyListeners();
      return;
    }
    await _onConnected(server, result.mode);
    // Replace the TCP handshake number with the real through-tunnel delay
    // as soon as the core answers. Best effort: old cores keep the TCP one.
    unawaited(_measureTunnelDelay(server));
  }

  Future<void> _connectXray(ServerModel server, AppSettings settings) async {
    final info = core;
    if (info == null || !info.xray) {
      status = VpnStatus.error;
      errorMessage = 'XRAY_MISSING';
      mode = 'missing';
      notifyListeners();
      return;
    }
    engine = 'xray';
    final String json;
    try {
      json = const JsonEncoder.withIndent('  ')
          .convert(XrayConfigBuilder.build(server: server, settings: settings));
    } on ArgumentError catch (error) {
      status = VpnStatus.error;
      errorMessage = '$error';
      notifyListeners();
      return;
    }
    final result = await _platform.start(
      configJson: json,
      preferTun: false,
      engine: 'xray',
    );
    if (!result.ok) {
      status = VpnStatus.error;
      errorMessage = result.error ?? 'core-failed';
      mode = result.mode;
      await _stats?.addLog(server.name, 'error', message: errorMessage);
      notifyListeners();
      return;
    }
    await _onConnected(server, result.mode);
    _listenXrayTraffic();
  }

  Future<void> _onConnected(ServerModel server, String resultMode) async {
    status = VpnStatus.connected;
    mode = resultMode;
    _sessionUp = 0;
    _sessionDown = 0;
    _lastXrayUp = 0;
    _lastXrayDown = 0;
    _lastXrayPoll = null;
    _stats?.startSession();
    await _stats?.addLog(server.name, 'connected', message: mode);
    if (engine == 'singbox') _listenTraffic();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _stats?.tickDuration();
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _measureTunnelDelay(ServerModel server) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (status != VpnStatus.connected || activeServerId != server.id) return;
    final delay = await ClashApi().proxyDelay();
    if (delay != null && status == VpnStatus.connected) {
      await _servers?.setPing(server.id, delay);
    }
  }

  void _listenXrayTraffic() {
    _xrayTicker?.cancel();
    _xrayTicker = Timer.periodic(const Duration(seconds: 2), (_) async {
      final totals = await _platform.xrayTrafficTotals();
      if (totals == null || status != VpnStatus.connected) return;
      final now = DateTime.now();
      final last = _lastXrayPoll;
      _lastXrayPoll = now;
      if (last == null) {
        _lastXrayUp = totals.up;
        _lastXrayDown = totals.down;
        return;
      }
      final seconds = now.difference(last).inMilliseconds / 1000;
      if (seconds <= 0) return;
      final upDelta = totals.up - _lastXrayUp;
      final downDelta = totals.down - _lastXrayDown;
      _lastXrayUp = totals.up;
      _lastXrayDown = totals.down;
      _sessionUp = totals.up;
      _sessionDown = totals.down;
      _stats?.applyTraffic(
        upBytesPerSecond: (upDelta / seconds).round(),
        downBytesPerSecond: (downDelta / seconds).round(),
        totalUp: totals.up,
        totalDown: totals.down,
      );
      notifyListeners();
    });
  }

  Future<void> disconnect() async {
    final name = activeServer?.name ?? '';
    await _platform.stop();
    await _traffic?.sink.close();
    _traffic = null;
    _ticker?.cancel();
    _xrayTicker?.cancel();
    engine = 'singbox';
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

  Future<String> downloadXray(void Function(DownloadProgress progress) onProgress) async {
    coreBusy = true;
    notifyListeners();
    try {
      final path = await _platform.downloadXray(onProgress: onProgress);
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
    if (server.isXhttp) {
      return const JsonEncoder.withIndent('  ')
          .convert(XrayConfigBuilder.build(server: server, settings: settings));
    }
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
    _xrayTicker?.cancel();
    _traffic?.sink.close();
    super.dispose();
  }
}
