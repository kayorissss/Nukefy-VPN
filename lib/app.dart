import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/providers/servers_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/main_shell.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/widgets/notification_overlay.dart';
import 'ui/widgets/nukefy_feedback.dart';
import 'ui/widgets/nukefy_splash.dart';

class NukefyApp extends StatelessWidget {
  const NukefyApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final empty = context.select<ServersProvider, bool>((servers) => servers.servers.isEmpty && servers.subscriptions.isEmpty);
    final welcome = !settings.settings.seenWelcome && empty;
    final brightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay(brightness),
      child: MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Nukefy Client',
      // Without this, framework widgets (and anything reading the locale)
      // stay in the platform language while the UI is already translated.
      locale: Locale(settings.strings.code),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.settings.accent, settings.settings.visualTheme),
      darkTheme: AppTheme.dark(settings.settings.accent, settings.settings.visualTheme),
      themeMode: settings.themeMode,
      // PrintScreen has to be handled inside the app: an elevated window is
      // invisible to the shell's own screenshot keys.
      builder: (context, child) {
        // Phones with giant accessibility fonts used to stack every label
        // onto its neighbour. Clamp the scale to a range the layouts were
        // designed for; the app stays readable without breaking apart.
        final media = MediaQuery.of(context);
        final clamped = media.copyWith(
          textScaler: media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.2),
        );
        return PrintScreenCatcher(
          child: NotificationOverlay(
            child: MediaQuery(data: clamped, child: child ?? const SizedBox.shrink()),
          ),
        );
      },
      home: NukefySplash(child: welcome ? const WelcomeScreen() : const MainShell()),
      ),
    );
  }
}
