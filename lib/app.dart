import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/providers/servers_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/main_shell.dart';
import 'ui/screens/welcome_screen.dart';

class NukefyApp extends StatelessWidget {
  const NukefyApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final servers = context.watch<ServersProvider>();
    final empty = servers.servers.isEmpty && servers.subscriptions.isEmpty;
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
      title: 'Nukefy VPN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.settings.accent),
      darkTheme: AppTheme.dark(settings.settings.accent),
      themeMode: settings.themeMode,
      home: welcome ? const WelcomeScreen() : const MainShell(),
      ),
    );
  }
}
