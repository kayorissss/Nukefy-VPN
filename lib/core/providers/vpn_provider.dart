import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';
import '../models/vpn_status.dart';
import '../services/app_perf.dart';
import '../services/karing_service.dart';
import '../services/singbox_config_builder.dart';
import '../services/vpn_platform.dart';
import '../services/xray_config_builder.dart';
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
  XrayCoreInfo? xrayCore;
  bool coreBusy = false;
  bool xrayCoreBusy = false;

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
    _startWatch();
  }

  Future<void> refreshCore() async {
    core = await _platform.coreInfo();
    xrayCore = await _platform.xrayCoreInfo();
    notifyListeners();
  }

  Future<void> deleteCore() async {
    if (status != VpnStatus.disconnected) await disconnect();
    await _platform.deleteCore();
    await refreshCore();
  }

  Future<void> deleteXrayCore() async {
    if (status != VpnStatus.disconnected) await disconnect();
    await _platform.deleteXrayCore();
    await refreshCore();
  }

  /// Removes a server without leaving a stale selected/active id behind.
  /// Subscription entries use the same path so a deleted active node cannot
  /// be auto-connected again after the next refresh.
  Future<void> deleteServer(String id) async {
    if (activeServerId == id) {
      if (status != VpnStatus.disconnected) await disconnect();
      activeServerId = null;
      await _settings?.update((value) {
        if (value.selectedServerId == id) value.selectedServerId = null;
      });
    }
    await _servers?.deleteServer(id);
  }

  Future<void> deleteSubscription(String id) async {
    if (activeServer?.subscriptionId == id) {
      if (status != VpnStatus.disconnected) await disconnect();
      activeServerId = null;
    }
    final selected = _servers?.byId(_settings?.settings.selectedServerId);
    if (selected?.subscriptionId == id) {
      await _settings?.update((value) => value.selectedServerId = null);
    }
    await _servers?.deleteSubscription(id);
  }

  Future<bool> downloadXrayCore(void Function(DownloadProgress progress) onProgress) async {
    xrayCoreBusy = true;
    notifyListeners();
    try {
      await _platform.downloadXrayCore(onProgress: onProgress);
      xrayCore = await _platform.xrayCoreInfo();
      return xrayCore?.available ?? false;
    } finally {
      xrayCoreBusy = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect(activeServer);
    }
  }

  /// Home-page picker: switch the pending server without dialing yet.
  void selectServer(String id) {
    activeServerId = id;
    notifyListeners();
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
    if (server.isInformational) {
      errorMessage = 'information-entry';
      notifyListeners();
      return;
    }
    activeServerId = server.id;
    await settings.update((s) => s.selectedServerId = server.id);
    status = VpnStatus.connecting;
    errorMessage = null;
    notifyListeners();
    await refreshCore();
    if (server.usesXhttp) {
      await _connectViaXray(server, settings.settings);
      return;
    }
    final validation = SingboxConfigBuilder.validationError(server);
    if (validation == 'XRAY_TRANSPORT_REQUIRED') {
      // sing-box cannot speak XHTTP/SplitHTTP, but the bundled Xray core
      // can: prefer a working tunnel over a refusal message.
      final xray = await _platform.xrayCoreInfo();
      if (xray.available) {
        await _connectViaXray(server, settings.settings);
        return;
      }
    }
    if (validation != null) {
      status = VpnStatus.error;
      mode = 'unsupported';
      errorMessage = validation;
      await _stats?.addLog(server.name, 'error', message: validation);
      notifyListeners();
      return;
    }
    final info = core;
    if (info == null || !info.available) {
      status = VpnStatus.error;
      // Android builds carry the core inside the APK; if it is absent the
      // user has a stripped build, which is a different problem from a
      // desktop that simply has not downloaded sing-box yet.
      errorMessage = Platform.isAndroid ? 'LIBBOX_MISSING' : 'CORE_MISSING';
      mode = 'missing';
      notifyListeners();
      return;
    }
    // Both platforms expose the same choice. Android uses VpnService for TUN;
    // proxy mode keeps the local SOCKS/HTTP inbound instead.
    final useTun = settings.settings.tunEnabled && (Platform.isAndroid ? info.libbox : true);
    if (Platform.isAndroid && useTun) {
      final ready = await _platform.prepareVpn();
      if (!ready) {
        status = VpnStatus.disconnected;
        notifyListeners();
        return;
      }
    }
    final dir = await _platform.configDirectory();
    try {
      SingboxConfigBuilder.rulesDir = (await _platform.ensureRuleSets()).path.replaceAll('\\', '/');
    } catch (_) {
      SingboxConfigBuilder.rulesDir = '';
    }
    ServerModel? detour;
    if (server.detourServerId != null) {
      detour = servers.byId(server.detourServerId);
    }
    // Windows excludes dynamic port ranges (Hyper-V, NAT): a perfectly
    // valid 10808 can be unbindable. Probe before handing the config over
    // and fall back to an ephemeral port instead of failing the session.
    final ports = await _resolvePorts(settings.settings);
    final json = SingboxConfigBuilder.buildJson(
      server: server,
      detour: detour,
      settings: settings.settings,
      logPath: '${dir.path}/sing-box.log',
      cachePath: '${dir.path}/cache.db',
      desktopTun: !Platform.isAndroid && useTun,
      forceProxyOnly: !useTun,
      balancerPool: KaringService.balancerPool(
        servers: servers.servers,
        subscriptions: servers.subscriptions,
        settings: settings.settings,
        activeSubscriptionId: server.subscriptionId,
      ),
      ports: ports,
    );
    await _platform.stopXray();
    var result = await _platform.start(
      configJson: json,
      preferTun: useTun,
      serverName: server.name,
      serverHost: server.address,
      serverPort: server.port,
    );
    if (!result.ok && (result.error ?? '').contains('bind')) {
      // Second attempt with purely ephemeral ports.
      final ephemeral = await _resolvePorts(settings.settings, ephemeral: true);
      final retryJson = SingboxConfigBuilder.buildJson(
        server: server,
        detour: detour,
        settings: settings.settings,
        logPath: '${dir.path}/sing-box.log',
        cachePath: '${dir.path}/cache.db',
        desktopTun: !Platform.isAndroid && useTun,
        forceProxyOnly: !useTun,
        balancerPool: KaringService.balancerPool(
          servers: servers.servers,
          subscriptions: servers.subscriptions,
          settings: settings.settings,
          activeSubscriptionId: server.subscriptionId,
        ),
        ports: ephemeral,
      );
      result = await _platform.start(
        configJson: retryJson,
        preferTun: useTun,
        serverName: server.name,
        serverHost: server.address,
        serverPort: server.port,
      );
    }
    if (!result.ok) {
      status = VpnStatus.error;
      final raw = result.error ?? 'core-failed';
      errorMessage = RegExp(r'xhttp|splithttp', caseSensitive: true).hasMatch(raw) ? 'XHTTP_UNSUPPORTED' : raw;
      mode = result.mode;
      await _stats?.addLog(server.name, 'error', message: errorMessage);
      notifyListeners();
      return;
    }
    status = VpnStatus.connected;
    mode = result.mode;
    _verifyTraffic(server.id);
    _sessionUp = 0;
    _sessionDown = 0;
    _stats?.startSession();
    // sing-box exposes the same traffic websocket on desktop and Android.
    // Start it for every successful session so Statistics is not a static
    // zero/empty screen on Windows.
    unawaited(_listenTraffic());
    await _stats?.addLog(server.name, 'connected', message: mode);
    _startTicker();
    notifyListeners();
  }

  /// Bind-probes the configured local ports; substitutes a free ephemeral
  /// port for every address Windows refuses to bind.
  static Future<LocalPorts> _resolvePorts(AppSettings settings, {bool ephemeral = false}) async {
    Future<int> probe(int preferred) async {
      if (!ephemeral) {
        try {
          final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferred);
          await socket.close();
          return preferred;
        } catch (_) {}
      }
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    }
    return LocalPorts(
      socks: await probe(settings.socksPort),
      http: await probe(settings.httpPort),
      clash: await probe(AppConstants.clashApiPort),
    );
  }

  static int _xrayInboundPort(int socksPort, int httpPort) {
    var candidate = socksPort + 10000;
    if (candidate > 65535 || candidate == httpPort) candidate = 18080;
    if (candidate == httpPort) candidate = 18081;
    return candidate;
  }

  Future<void> _connectViaXray(ServerModel server, AppSettings settings) async {
    if (!XrayConfigBuilder.supports(server)) {
      status = VpnStatus.error;
      mode = 'xray-unsupported';
      errorMessage = 'XRAY_UNSUPPORTED_PROTOCOL';
      notifyListeners();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS || !(xrayCore?.available ?? false)) {
      status = VpnStatus.error;
      mode = 'xray-missing';
      errorMessage = Platform.isAndroid || Platform.isIOS ? 'XRAY_PLATFORM_UNSUPPORTED' : 'XRAY_CORE_MISSING';
      notifyListeners();
      return;
    }
    final useTunFrontend = settings.tunEnabled && (core?.available ?? false);
    if (settings.tunEnabled && !useTunFrontend) {
      status = VpnStatus.error;
      mode = 'xray-frontend-missing';
      errorMessage = 'XRAY_FRONTEND_MISSING';
      notifyListeners();
      return;
    }
    final dir = await _platform.configDirectory();
    final xrayPorts = await _resolvePorts(settings);
    final xrayPort = useTunFrontend ? _xrayInboundPort(xrayPorts.socks, xrayPorts.http) : xrayPorts.socks;
    try {
      final config = XrayConfigBuilder.buildJson(
        server: server,
        settings: settings,
        logPath: '${dir.path}/xray.log',
        inboundPort: xrayPort,
        ports: xrayPorts,
      );
      await _platform.stop();
      final xrayResult = await _platform.startXray(configJson: config, workDir: dir.path);
      if (!xrayResult.ok) {
        status = VpnStatus.error;
        mode = 'xray-proxy';
        errorMessage = xrayResult.error ?? 'XRAY_START_FAILED';
        await _stats?.addLog(server.name, 'error', message: errorMessage);
        notifyListeners();
        return;
      }
      if (useTunFrontend) {
        final frontend = XrayConfigBuilder.buildSingboxFrontendJson(
          settings: settings,
          xrayPort: xrayPort,
          logPath: '${dir.path}/xray-frontend.log',
          cachePath: '${dir.path}/xray-cache.db',
          useTun: true,
          ports: xrayPorts,
        );
        final frontendResult = await _platform.start(
          configJson: frontend,
          preferTun: true,
          serverName: server.name,
          serverHost: server.address,
          serverPort: server.port,
        );
        if (!frontendResult.ok) {
          await _platform.stopXray();
          status = VpnStatus.error;
          mode = 'xray-frontend';
          errorMessage = frontendResult.error ?? 'XRAY_FRONTEND_FAILED';
          await _stats?.addLog(server.name, 'error', message: errorMessage);
          notifyListeners();
          return;
        }
      }
      // Xray owns the XHTTP protocol. When TUN is enabled, sing-box is only
      // the transparent front-end and forwards all traffic to Xray; when it is
      // disabled, the user gets an explicitly labelled local proxy instead.
      status = VpnStatus.connected;
      mode = useTunFrontend ? 'xray-tun' : 'xray-proxy';
      errorMessage = null;
      _sessionUp = 0;
      _sessionDown = 0;
      _stats?.startSession();
      if (useTunFrontend) unawaited(_listenTraffic());
      await _stats?.addLog(server.name, 'connected', message: mode);
      _startTicker();
      notifyListeners();
    } on XrayConfigException catch (error) {
      status = VpnStatus.error;
      mode = 'xray-proxy';
      errorMessage = error.code;
      notifyListeners();
    } catch (error) {
      status = VpnStatus.error;
      mode = 'xray-proxy';
      errorMessage = '$error';
      notifyListeners();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // A minimized window must not repaint the whole tree every second.
      if (!AppPerf.visible) return;
      _stats?.tickDuration();
      notifyListeners();
    });
  }

  Timer? _watch;
  bool _syncing = false;

  /// Android: the service lives its own life (quick tile, notification
  /// action, revive after boot, system "disconnect"). Poll it every 2 s and
  /// keep the UI truthful in both directions.
  void _startWatch() {
    if (!Platform.isAndroid) return;
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_syncing || status == VpnStatus.connecting) return;
      _syncing = true;
      try {
        final alive = await _platform.isRunning();
        if (!alive && status == VpnStatus.connected) {
          await _onExternalStop();
        } else if (alive && status != VpnStatus.connected) {
          await _onExternalStart();
        }
      } finally {
        _syncing = false;
      }
    });
  }

  /// Service was started outside the app (tile / boot): adopt the session.
  Future<void> _onExternalStart() async {
    activeServerId ??= _settings?.settings.selectedServerId;
    status = VpnStatus.connected;
    errorMessage = null;
    mode = 'tun';
    _sessionUp = 0;
    _sessionDown = 0;
    _stats?.startSession();
    unawaited(_listenTraffic());
    _startTicker();
    notifyListeners();
  }

  /// A lit VPN icon says nothing about whether packets actually get through.
  /// A few seconds after connecting, fetch a tiny page through the tunnel
  /// and tell the user plainly when the server accepts the handshake but
  /// passes no traffic (wrong transport, dead server, DNS through proxy…).
  Future<void> _verifyTraffic(String serverId) async {
    if (!Platform.isAndroid) return; // desktop routes the app itself direct.
    await Future.delayed(const Duration(seconds: 4));
    if (status != VpnStatus.connected || activeServerId != serverId) return;
    String? failure;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse('http://cp.cloudflare.com/generate_204')).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      if (response.statusCode >= 500) failure = 'HTTP ${response.statusCode}';
    } catch (error) {
      failure = error.toString().split('\n').first;
    } finally {
      client.close(force: true);
    }
    if (status != VpnStatus.connected || activeServerId != serverId) return;
    errorMessage = failure == null ? null : 'NO_TRAFFIC:$failure';
    notifyListeners();
  }

  /// Core died or was stopped outside the app: clean up without calling stop.
  Future<void> _onExternalStop() async {
    final name = activeServer?.name ?? '';
    await _traffic?.sink.close();
    _traffic = null;
    _ticker?.cancel();
    final settings = _settings;
    if (settings != null && (_sessionUp > 0 || _sessionDown > 0)) {
      await settings.addTraffic(_sessionUp, _sessionDown);
    }
    status = VpnStatus.disconnected;
    _stats?.resetSession();
    if (name.isNotEmpty) await _stats?.addLog(name, 'disconnected');
    notifyListeners();
  }

  Future<void> disconnect() async {
    final name = activeServer?.name ?? '';
    await _platform.stop();
    await _platform.stopXray();
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

  Future<void> _listenTraffic({int attempt = 0}) async {
    await _traffic?.sink.close();
    _traffic = null;
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${AppConstants.clashApiPort}/traffic'),
      );
      _traffic = channel;
      void retry() {
        if (status != VpnStatus.connected || attempt >= 4 || _traffic != channel) return;
        unawaited(Future<void>.delayed(const Duration(seconds: 1), () => _listenTraffic(attempt: attempt + 1)));
      }

      channel.stream.listen((event) {
        try {
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
          notifyListeners();
        } catch (error) {
          _platform.appendLog('traffic payload: $error');
        }
      }, onError: (Object error) {
        _platform.appendLog('traffic: $error');
        retry();
      }, onDone: retry);
    } catch (error) {
      _platform.appendLog('traffic connect: $error');
    }
  }

  /// Downloads and unpacks the official sing-box core.
  ///
  /// Returns `true` on success. Failures are re-thrown so the caller can show
  /// the real reason; the UI must not treat the returned binary path as an
  /// error.
  Future<bool> downloadCore(
    void Function(DownloadProgress progress) onProgress,
  ) async {
    coreBusy = true;
    notifyListeners();
    try {
      await _platform.downloadCore(onProgress: onProgress);
      await refreshCore();
      return core?.available ?? false;
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
