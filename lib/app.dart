import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/servers_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_text_styles.dart';
import 'core/utils/format_utils.dart';
import 'ui/screens/main_shell.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/widgets/nukefy_logo.dart';

class NukefyApp extends StatefulWidget {
  const NukefyApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<NukefyApp> createState() => _NukefyAppState();
}

class _NukefyAppState extends State<NukefyApp> {
  bool _splashDone = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Short branded splash. Strictly monochrome: no coloured stripes or
    // accents under the text, whatever theme the system uses.
    _timer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final servers = context.watch<ServersProvider>();
    FormatUtils.ruUnits = settings.strings.code == 'ru';
    final empty = servers.servers.isEmpty && servers.subscriptions.isEmpty;
    final welcome = !settings.settings.seenWelcome && empty;
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'Nukefy Client',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      builder: (context, child) {
        // Clamp system font scaling so layout never overlaps itself on
        // phones with huge accessibility fonts.
        final media = MediaQuery.of(context);
        final scale = media.textScaler.scale(1).clamp(0.85, 1.15);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: !_splashDone
          ? const _SplashScreen()
          : welcome
              ? const WelcomeScreen()
              : const MainShell(),
    );
  }
}

/// Monochrome launch splash: black background, logo, name, one thin
/// loading line. Nothing yellow, nothing coloured under the text.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final strings = context.watch<SettingsProvider>().strings;
    final background = dark ? AppColors.background : AppColors.lightBackground;
    final text = dark ? AppColors.textPrimary : AppColors.lightText;
    final secondary =
        dark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NukefyLogo(size: 92, glow: false),
            const SizedBox(height: 20),
            Text(
              'Nukefy Client',
              style: AppTextStyles.title.copyWith(color: text, fontSize: 26),
            ),
            const SizedBox(height: 8),
            Text(
              strings.t('splashTagline'),
              style: AppTextStyles.bodySecondary.copyWith(color: secondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 168,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: secondary.withValues(alpha: 0.18),
                color: text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
