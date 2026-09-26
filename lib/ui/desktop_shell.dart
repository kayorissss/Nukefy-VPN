import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers/settings_provider.dart';
import '../core/providers/vpn_provider.dart';
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
    windowManager.addListener(this);
    trayManager.addListener(this);
    _init();
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    final dir = await getApplicationSupportDirectory();
    final asset = Platform.isWindows ? 'assets/icons/app_icon.ico' : 'assets/icons/tray_icon.png';
    // New file name per icon revision so a stale cached copy is never reused.
    final icon = File('${dir.path}/${Platform.isWindows ? 'tray_icon_v2.ico' : 'tray_icon_v2.png'}');
    try {
      final data = await rootBundle.load(asset);
      await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } catch (_) {
      if (!icon.existsSync()) return;
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

  bool _asking = false;

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
    await ZapretService.instance.stop();
    await context.read<VpnProvider>().disconnect();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
