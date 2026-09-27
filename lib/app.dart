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
      // Everything below the navigator is wrapped in an animated theme, so
      // switching theme or accent colour glides instead of snapping, and a
      // short cross-fade hides the moment the system bars flip.
      builder: (context, child) => _ThemeTransition(
        theme: brightness == Brightness.dark
            ? AppTheme.dark(settings.settings.accent)
            : AppTheme.light(settings.settings.accent),
        child: child ?? const SizedBox.shrink(),
      ),
      home: welcome ? const WelcomeScreen() : const MainShell(),
      ),
    );
  }
}

/// Cross-fades between two themes.
///
/// `AnimatedTheme` interpolates every colour of the palette; the overlay adds
/// a short veil of the previous background on top, so a dark → light switch
/// reads as one movement rather than a flash of differently coloured widgets.
class _ThemeTransition extends StatefulWidget {
  const _ThemeTransition({required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  State<_ThemeTransition> createState() => _ThemeTransitionState();
}

class _ThemeTransitionState extends State<_ThemeTransition> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 340);

  late final AnimationController _fade = AnimationController(vsync: this, duration: _duration);
  ThemeData? _shown;
  Color? _from;

  @override
  void initState() {
    super.initState();
    _shown = widget.theme;
  }

  @override
  void didUpdateWidget(covariant _ThemeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _shown;
    if (previous != null && widget.theme != previous) {
      _from = previous.scaffoldBackgroundColor;
      _fade.forward(from: 0);
    }
    _shown = widget.theme;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedTheme(
      data: widget.theme,
      duration: _duration,
      curve: Curves.easeInOutCubic,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_from != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fade,
                  builder: (context, _) => Opacity(
                    opacity: (1 - _fade.value).clamp(0.0, 1.0),
                    child: ColoredBox(color: _from!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
