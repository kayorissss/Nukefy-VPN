import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/providers/nav_provider.dart';
import 'core/providers/servers_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/stats_provider.dart';
import 'core/constants/app_constants.dart';
import 'core/models/vpn_status.dart';
import 'core/providers/vpn_provider.dart';
import 'core/services/app_log.dart';
import 'core/services/app_perf.dart';
import 'core/services/desktop_instance_guard.dart';
import 'core/services/music_audio_handler.dart';
import 'core/services/music_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/subscription_service.dart';
import 'core/services/tg_ws_proxy_service.dart';
import 'core/services/vpn_platform.dart';
import 'core/services/zapret_service.dart';
import 'ui/desktop_shell.dart';
import 'ui/screens/settings_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// The exe identity changed (kayorisan/Nukefy VPN -> KAYORI-SAN/Nukefy
/// Client), which moves the Windows roaming support directory. Carry the
/// old subscriptions, settings and caches over on first launch.
void _migrateLegacyData() {
  if (!Platform.isWindows) return;
  try {
    final root = Platform.environment['APPDATA'];
    if (root == null) return;
    final fresh = Directory(p.join(root, 'KAYORI-SAN', 'Nukefy Client'));
    if (fresh.existsSync() && fresh.listSync().isNotEmpty) return;
    for (final old in [
      Directory(p.join(root, 'kayorisan', 'Nukefy VPN')),
      Directory(p.join(root, 'kayorisan', 'Nukefy Client')),
      Directory(p.join(root, 'KAYORI-SAN', 'Nukefy VPN')),
    ]) {
      if (!old.existsSync()) continue;
      for (final entity in old.listSync(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: old.path);
        final target = File(p.join(fresh.path, rel));
        if (target.existsSync()) continue;
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
      }
      return;
    }
  } catch (_) {}
}

Future<void> main() async {
  runZonedGuarded(_main, (error, stack) => AppLog.log('uncaught: $error\n$stack'));
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _migrateLegacyData();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.log('flutter: ${details.exceptionAsString()}');
  };
  final startedAt = DateTime.now();
  await AppLog.init();
  AppLog.log('start ${AppConstants.version} ${Platform.operatingSystem} ${Platform.operatingSystemVersion} args=${Platform.executableArguments}');
  if (Platform.isAndroid || Platform.isIOS) {
    // Music, file pickers and the VPN controls keep a single stable layout.
    // Never let a sensor rotation move the app into landscape.
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    // Draw behind the status and gesture bars; colours come from AppTheme.overlay.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  DesktopInstanceGuard? desktopGuard;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    desktopGuard = DesktopInstanceGuard();
    // A replacement process spawned by an in-app restart waits for the dying
    // parent to release the single-instance listener instead of racing it:
    // binding too early used to open a second, half-dead window.
    final restarting = Platform.executableArguments.contains('--nukefy-restart');
    final primary = await desktopGuard.acquire(
      retry: restarting ? const Duration(seconds: 8) : Duration.zero,
      onShow: () async {
        // A second taskbar/tray launch talks to the existing process instead
        // of creating a second Flutter engine and losing the entered server.
        await windowManager.show();
        await windowManager.focus();
      },
    );
    if (!primary) {
      AppLog.log('second desktop launch forwarded to the existing window');
      exit(0);
    }
    const options = WindowOptions(
      // Give the desktop layout enough horizontal room for the rail and two
      // balanced content columns; this no longer opens as a shrunken mobile
      // canvas on a normal monitor.
      size: Size(1280, 820),
      minimumSize: Size(980, 680),
      center: true,
      title: 'Nukefy VPN',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFF0D0D0D),
    );
    windowManager.waitUntilReadyToShow(options, () async {
      // The app lives maximized: a small floating window wasted screen room
      // and the user asked for "always maximal, no mini window".
      try {
        await windowManager.maximize();
      } catch (error) {
        AppLog.log('window maximize failed: $error');
        try {
          await windowManager.setSize(options.size!);
          await windowManager.center();
        } catch (_) {}
      }
      windowManager.addListener(_MaximizeGuard());
      _MaximizeGuard.start();
      await windowManager.show();
      await windowManager.focus();
      AppLog.log('window shown at normal size');
    });
  }

  // Every init step is bounded and non-fatal: a stuck storage read or a
  // hanging `sing-box version` must never leave the user with a blank window.
  Future<void> guard(String step, Future<void> Function() run, {int seconds = 8}) async {
    final sw = Stopwatch()..start();
    try {
      await run().timeout(Duration(seconds: seconds));
      AppLog.log('init $step ok ${sw.elapsedMilliseconds}ms');
    } catch (error) {
      AppLog.log('init $step FAILED after ${sw.elapsedMilliseconds}ms: $error');
    }
  }

  await guard('storage', StorageService.instance.init);
  final settings = SettingsProvider(StorageService.instance);
  final servers = ServersProvider(StorageService.instance, SubscriptionService());
  final stats = StatsProvider(StorageService.instance);
  AudioHandler? musicHandler;
  if (Platform.isAndroid) {
    try {
      musicHandler = await AudioService.init(
        builder: MusicAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.nukefy.vpn.music',
          androidNotificationChannelName: 'Nukefy music',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidResumeOnClick: true,
          androidNotificationClickStartsActivity: true,
        ),
      );
    } catch (error) {
      AppLog.log('music background init failed: $error');
    }
  }
  final music = MusicService(StorageService.instance, backgroundHandler: musicHandler);
  final vpn = VpnProvider(VpnPlatform());
  await guard('load', () => Future.wait([settings.load(), servers.load(), stats.load(), music.load()]));
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Match the window to the saved theme: a light-theme start used to flash
    // a dark rectangle before the first frame.
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final dark = settings.themeMode == ThemeMode.dark || (settings.themeMode == ThemeMode.system && systemDark);
    try {
      await windowManager.setBackgroundColor(dark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F4F8));
    } catch (_) {}
  }
  vpn.bind(stats: stats, servers: servers, settings: settings);
  // Windows ships sing-box and Xray inside the installer/portable exe: the
  // cores are copied into the user directory on first launch, so a fresh
  // install connects without any download (GitHub is blocked for many users).
  await guard('bundle-cores', () async {
    final seeded = await VpnPlatform().seedBundledCores();
    if (seeded.isNotEmpty) AppLog.log('bundle cores installed: ${seeded.join(', ')}');
  }, seconds: 15);
  await guard('core', vpn.refreshCore, seconds: 5);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: servers),
        ChangeNotifierProvider.value(value: stats),
        ChangeNotifierProvider.value(value: music),
        ChangeNotifierProvider.value(value: TgWsProxyService.instance),
        ChangeNotifierProvider.value(value: ZapretService.instance),
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider(create: (_) => NavProvider()),
      ],
      child: DesktopShell(navigatorKey: navigatorKey, child: NukefyApp(navigatorKey: navigatorKey)),
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
    AppLog.log('first frame after ${DateTime.now().difference(startedAt).inMilliseconds}ms');
    if (Platform.isWindows) {
      final zapret = ZapretService.instance;
      try {
        await zapret.exclusive(() async {
          await zapret.refreshGameLists();
          await zapret.serviceInstalled();
          if (settings.settings.zapretAutoStart && !zapret.servicePresent) {
            final list = zapret.strategies();
            final chosen = list.where((e) => e.id == settings.settings.zapretStrategy).firstOrNull ?? list.firstOrNull;
            if (chosen != null) {
              zapret.configure(settings.settings);
              final ok = await zapret.start(chosen);
              AppLog.log('zapret autostart ok=$ok ${zapret.lastError ?? ''}');
            }
          }
        });
      } catch (error) {
        zapret.lastError = '$error';
        AppLog.log('zapret startup failed: $error');
      }
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Safety net: if waitUntilReadyToShow never fired, show the window now.
      try {
        final loginLaunch = Platform.executableArguments.contains('--autostart');
        if (loginLaunch && settings.settings.startInTray) {
          await windowManager.hide();
        } else if (!await windowManager.isVisible()) {
          await windowManager.show();
          await windowManager.focus();
        }
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
    if (context != null) {
      await _ensureNotificationPermission(context, settings);
      if (settings.settings.checkUpdatesOnStart) {
        await checkUpdatesFlow(context, silentIfCurrent: true);
      }
    }
  });
}

Future<void> _ensureNotificationPermission(BuildContext context, SettingsProvider settings) async {
  if (!Platform.isAndroid || !settings.settings.notifications) return;
  final current = await Permission.notification.status;
  if (current.isGranted || current.isLimited) return;
  final marker = StorageService.instance.readJson('notification_permission_prompt');
  final alreadyPrompted = marker?['version'] == AppConstants.version;
  var status = current;
  if (!alreadyPrompted) {
    if (status.isDenied) status = await Permission.notification.request();
    await StorageService.instance.writeJson('notification_permission_prompt', {
      'version': AppConstants.version,
    });
  }
  if (status.isGranted || status.isLimited || alreadyPrompted || !context.mounted) return;
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(settings.strings.t('notificationPermissionTitle')),
      content: Text(settings.strings.t('notificationPermissionBody')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(settings.strings.t('notificationPermissionLater'))),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(settings.strings.t('notificationPermissionSettings'))),
      ],
    ),
  );
  if (openSettings == true) await openAppSettings();
}


class _ResumeActions extends WidgetsBindingObserver {
  _ResumeActions(this.onResume);
  final Future<void> Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppPerf.visible = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// The desktop app exists only maximized: restoring or dragging the window
/// back to a floating state immediately re-maximizes it.
class _MaximizeGuard extends WindowListener {
  static Timer? _enforcer;

  /// Belt and braces: a periodic check re-maximizes the window on setups
  /// where the event callbacks never fire (DPI-scaled multi-monitor shells).
  static void start() {
    _enforcer?.cancel();
    _enforcer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        if (!await windowManager.isMaximized() && !await windowManager.isMinimized()) {
          await windowManager.maximize();
        }
      } catch (_) {}
    });
  }

  @override
  void onWindowRestore() {
    windowManager.maximize();
  }

  @override
  void onWindowMaximize() {}

  @override
  void onWindowResized() async {
    if (!await windowManager.isMaximized()) await windowManager.maximize();
  }
}
