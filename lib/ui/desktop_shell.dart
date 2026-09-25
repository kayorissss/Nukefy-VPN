import 'dart:io';

import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers/settings_provider.dart';
import '../core/providers/vpn_provider.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    _init();
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    final dir = await getApplicationSupportDirectory();
    final asset = Platform.isWindows ? 'assets/icons/app_icon.ico' : 'assets/icons/app_icon.png';
    final icon = File('${dir.path}/${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}');
    if (!icon.existsSync()) {
      final data = await rootBundle.load(asset);
      await icon.writeAsBytes(data.buffer.asUint8List());
    }
    await trayManager.setIcon(icon.path);
    await trayManager.setToolTip('Nukefy VPN');
    await _menu();
  }

  Future<void> _menu() async {
    if (!mounted) return;
    final s = context.read<SettingsProvider>().strings;
    final connected = context.read<VpnProvider>().status.name == 'connected';
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: s.t('open')),
          MenuItem(key: 'toggle', label: connected ? s.t('trayDisconnect') : s.t('trayConnect')),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: s.t('exit')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final hide = context.read<SettingsProvider>().settings.minimizeToTray;
    if (hide) {
      await windowManager.hide();
      return;
    }
    await _quit();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'toggle':
        context.read<VpnProvider>().toggle().then((_) => _menu());
      case 'exit':
        _quit();
    }
  }

  Future<void> _quit() async {
    await context.read<VpnProvider>().disconnect();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
