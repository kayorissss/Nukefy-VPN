import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models/vpn_status.dart';
import '../core/services/app_perf.dart';
import '../core/providers/servers_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/vpn_provider.dart';
import '../core/services/tg_ws_proxy_service.dart';
import '../core/services/vpn_platform.dart';
import '../core/services/zapret_service.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child, this.navigatorKey});

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    context.read<VpnProvider>().addListener(_queueMenu);
    context.read<ServersProvider>().addListener(_queueMenu);
    context.read<TgWsProxyService>().addListener(_queueMenu);
    ZapretService.instance.addListener(_queueMenu);
    windowManager.addListener(this);
    trayManager.addListener(this);
    _init();
  }

  void _queueMenu() {
    if (mounted) {
      unawaited(_menu());
      unawaited(_syncTrayIcon());
    }
  }

  /// The tray icon carries a status dot so the user sees at a glance whether
  /// the tunnel is up, dialing or down, even with the window hidden.
  Future<void> _syncTrayIcon() async {
    if (!mounted) return;
    final vpn = context.read<VpnProvider>();
    final s = context.read<SettingsProvider>().strings;
    final name = switch (vpn.status) {
      VpnStatus.connected => 'tray_on',
      VpnStatus.connecting => 'tray_connecting',
      VpnStatus.error => 'tray_error',
      VpnStatus.disconnected => 'tray_off',
    };
    final label = switch (vpn.status) {
      VpnStatus.connected => s.t('connected'),
      VpnStatus.connecting => s.t('connecting'),
      VpnStatus.error => s.t('error'),
      VpnStatus.disconnected => s.t('disconnected'),
    };
    try {
      final ext = Platform.isWindows ? 'ico' : 'png';
      final dir = await getApplicationSupportDirectory();
      final icon = File('${dir.path}/tray_status_$name.$ext');
      if (!icon.existsSync()) {
        final data = await rootBundle.load('assets/icons/$name.$ext');
        await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      await trayManager.setIcon(icon.path);
      await trayManager.setToolTip('Nukefy VPN — $label');
    } catch (_) {}
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    final dir = await getApplicationSupportDirectory();
    // One monochrome icon for tray, taskbar and window. A fixed file name is
    // fine now that there are no variants to switch between.
    final asset = Platform.isWindows ? 'assets/icons/app_icon.ico' : 'assets/icons/tray_icon.png';
    final icon = File('${dir.path}/${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}');
    try {
      final data = await rootBundle.load(asset);
      await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } catch (_) {
      if (!icon.existsSync()) return;
    }
    await trayManager.setIcon(icon.path);
    await _syncTrayIcon();
    if (Platform.isWindows) {
      // window_manager applies the same ICO to the taskbar/window, not only
      // the tray. Linux and macOS keep their native bundle icon and use the
      // PNG above for the tray.
      await windowManager.setIcon(icon.path);
    }
    await trayManager.setToolTip('Nukefy VPN');
    await _menu();
  }

  Future<void> _menu() async {
    if (!mounted) return;
    final s = context.read<SettingsProvider>().strings;
    final vpn = context.read<VpnProvider>();
    final servers = context.read<ServersProvider>();
    final tg = context.read<TgWsProxyService>();
    final tgInstalled = await tg.binaryFile();
    final zapret = ZapretService.instance;
    final connected = vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting;
    final connectable = servers.servers.where((server) => !server.isInformational).take(12).toList();
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: s.t('open')),
          MenuItem(key: 'toggle', label: connected ? s.t('trayDisconnect') : s.t('trayConnect')),
          for (final server in connectable)
            MenuItem(key: 'connect:${server.id}', label: '  ${server.displayName} · ${server.protocol.toUpperCase()}'),
          MenuItem.separator(),
          MenuItem(key: 'zapret', label: zapret.isRunning ? s.t('trayZapretOff') : s.t('trayZapretOn')),
          if (tg.supported && tgInstalled != null)
            MenuItem(key: 'tg', label: tg.running ? s.t('trayTgOff') : s.t('trayTgOn')),
          MenuItem.separator(),
          MenuItem(key: 'restart', label: s.t('restart')),
          MenuItem(key: 'exit', label: s.t('exit')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      context.read<VpnProvider>().removeListener(_queueMenu);
      context.read<ServersProvider>().removeListener(_queueMenu);
      context.read<MusicService>().removeListener(_queueMenu);
      context.read<TgWsProxyService>().removeListener(_queueMenu);
      ZapretService.instance.removeListener(_queueMenu);
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  bool _asking = false;

  // A minimized or hidden window must not keep repainting: the traffic
  // ticker and log tail consult AppPerf.visible before notifying listeners.
  @override
  void onWindowMinimize() => AppPerf.visible = false;

  @override
  void onWindowRestore() => AppPerf.visible = true;

  @override
  void onWindowMaximize() => AppPerf.visible = true;

  @override
  void onWindowUnmaximize() => AppPerf.visible = true;

  @override
  void onWindowClose() async {
    final settings = context.read<SettingsProvider>();
    var action = settings.settings.closeAction;
    if (action == 'ask') {
      if (_asking) return;
      _asking = true;
      action = await _askClose(settings) ?? 'cancel';
      _asking = false;
    }
    switch (action) {
      case 'tray':
        await windowManager.hide();
        AppPerf.visible = false;
      case 'exit':
        await _quit();
      default:
        return;
    }
  }

  /// Close (X / Alt+F4): minimize to tray or exit, with "remember".
  Future<String?> _askClose(SettingsProvider settings) async {
    final s = settings.strings;
    var remember = false;
    final dialogContext = widget.navigatorKey?.currentContext;
    if (dialogContext == null) return 'tray';
    await windowManager.show();
    await windowManager.focus();
    return showDialog<String>(
      context: dialogContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.t('closeTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('closeBody')),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: Text(s.t('closeRemember')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
            TextButton(
              onPressed: () async {
                if (remember) await settings.update((v) => v.closeAction = 'exit');
                if (context.mounted) Navigator.pop(context, 'exit');
              },
              child: Text(s.t('closeExit')),
            ),
            FilledButton(
              onPressed: () async {
                if (remember) await settings.update((v) => v.closeAction = 'tray');
                if (context.mounted) Navigator.pop(context, 'tray');
              },
              child: Text(s.t('closeTray')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    AppPerf.visible = true;
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key == 'show') {
      unawaited(_showWindow());
      return;
    }
    if (key == 'toggle') {
      unawaited(context.read<VpnProvider>().toggle().then((_) => _menu()));
      return;
    }
    if (key.startsWith('connect:')) {
      final id = key.substring('connect:'.length);
      final server = context.read<ServersProvider>().byId(id);
      if (server != null) {
        unawaited(context.read<VpnProvider>().connect(server).then((_) => _menu()));
      }
      return;
    }

    if (key == 'zapret') {
      unawaited(_toggleZapret());
      return;
    }
    if (key == 'tg') {
      unawaited(_toggleTelegramProxy());
      return;
    }
    if (key == 'restart') {
      unawaited(_restart());
      return;
    }
    if (key == 'exit') unawaited(_quit());
  }

  Future<void> _showWindow() async {
    AppPerf.visible = true;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _toggleZapret() async {
    final zapret = ZapretService.instance;
    if (zapret.isRunning) {
      await zapret.stop();
    } else {
      final settings = context.read<SettingsProvider>();
      final strategies = zapret.strategies();
      final strategy = strategies.where((item) => item.id == settings.settings.zapretStrategy).firstOrNull ?? strategies.firstOrNull;
      if (strategy != null) {
        zapret.configure(settings.settings);
        await zapret.start(strategy);
      }
    }
    await _menu();
  }

  Future<void> _toggleTelegramProxy() async {
    final service = context.read<TgWsProxyService>();
    try {
      if (service.running) {
        await service.stop();
      } else {
        await service.start();
      }
    } catch (error) {
      // The screen exposes the detailed error.  Keep tray actions non-fatal
      // and make the raw failure available in the app log.
      VpnPlatform().appendLog('tray telegram proxy: $error');
    }
    await _menu();
  }

  Future<void> _restart() async {
    // The replacement waits for this process to release the single-instance
    // listener (see DesktopInstanceGuard.acquire), so the hand-off order is:
    // hide → bounded cleanup → spawn → exit. Nothing here may await longer
    // than a couple of seconds or the user sees two windows.
    await windowManager.hide();
    final vpn = context.read<VpnProvider>();
    await Future.wait<void>([
      _bounded(() => ZapretService.instance.shutdown(), seconds: 1),
      _bounded(vpn.disconnect, seconds: 1),
    ]);
    await windowManager.setPreventClose(false);
    // restartApp exits this process only after the replacement was started.
    // If spawning fails it returns, so keep the current window usable.
    await VpnPlatform().restartApp(exitCurrent: true);
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  /// Hiding the window first makes the exit feel instant; the cleanup below
  /// (winws, sing-box) runs while it is already gone and is bounded, so a
  /// stuck helper process can never hold the quit for long.
  Future<void> _quit() async {
    await windowManager.hide();
    final vpn = context.read<VpnProvider>();
    await Future.wait<void>([
      _bounded(() => ZapretService.instance.shutdown()),
      _bounded(vpn.disconnect),
    ]);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    // The window is gone; make sure the process goes with it instead of
    // lingering until the engine winds down.
    exit(0);
  }

  /// Runs [run] but never longer than [seconds] — a helper that refuses to
  /// die must not block the exit.
  Future<void> _bounded(Future<void> Function() run, {int seconds = 3}) {
    return run().timeout(Duration(seconds: seconds), onTimeout: () => Future<void>.value());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
