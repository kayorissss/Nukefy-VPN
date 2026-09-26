import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/providers/nav_provider.dart';
import 'core/providers/servers_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/stats_provider.dart';
import 'core/models/vpn_status.dart';
import 'core/providers/vpn_provider.dart';
import 'core/services/storage_service.dart';
import 'core/services/subscription_service.dart';
import 'core/services/vpn_platform.dart';
import 'ui/desktop_shell.dart';
import 'ui/screens/settings_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    // Draw behind the status and gesture bars; colours come from AppTheme.overlay.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1100, 760),
      minimumSize: Size(860, 640),
      center: true,
      title: 'Nukefy VPN',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFF0D0D0D),
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Every init step is bounded and non-fatal: a stuck storage read or a
  // hanging `sing-box version` must never leave the user with a blank window.
  Future<void> guard(String step, Future<void> Function() run, {int seconds = 8}) async {
    try {
      await run().timeout(Duration(seconds: seconds));
    } catch (error) {
      debugPrint('init: $step failed: $error');
    }
  }

  await guard('storage', StorageService.instance.init);
  final settings = SettingsProvider(StorageService.instance);
  final servers = ServersProvider(StorageService.instance, SubscriptionService());
  final stats = StatsProvider(StorageService.instance);
  final vpn = VpnProvider(VpnPlatform());
  await guard('load', () => Future.wait([settings.load(), servers.load(), stats.load()]));
  vpn.bind(stats: stats, servers: servers, settings: settings);
  await guard('core', vpn.refreshCore, seconds: 5);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: servers),
        ChangeNotifierProvider.value(value: stats),
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider(create: (_) => NavProvider()),
      ],
      child: DesktopShell(child: NukefyApp(navigatorKey: navigatorKey)),
    ),
  );

  // Quick tile / notification can bring an already running app to front with
  // an action attached; pick it up on every resume, not only at cold start.
  WidgetsBinding.instance.addObserver(_ResumeActions(() async {
    final action = await VpnPlatform().consumeLaunchAction();
    if (action == null) return;
    final selected = servers.byId(settings.settings.selectedServerId);
    if (action == 'toggle') {
      await vpn.toggle();
    } else if (action == 'connect' && selected != null && vpn.status != VpnStatus.connected) {
      await vpn.connect(selected);
    }
  }));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Safety net: if waitUntilReadyToShow never fired, show the window now.
      try {
        if (!await windowManager.isVisible()) await windowManager.show();
      } catch (_) {}
    }
    final action = await VpnPlatform().consumeLaunchAction();
    final selected = servers.byId(settings.settings.selectedServerId);
    if (action == 'toggle') {
      await vpn.toggle();
    } else if ((action == 'connect' || settings.settings.autoConnect) && selected != null) {
      await vpn.connect(selected);
    }
    final context = navigatorKey.currentContext;
    if (context != null && settings.settings.checkUpdatesOnStart) {
      await checkUpdatesFlow(context, silentIfCurrent: true);
    }
  });
}

class _ResumeActions extends WidgetsBindingObserver {
  _ResumeActions(this.onResume);
  final Future<void> Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
