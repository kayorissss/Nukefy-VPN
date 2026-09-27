import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_logo.dart';
import 'home_screen.dart';
import 'jammers_screen.dart';
import 'music_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'speed_test_screen.dart';
import 'stats_screen.dart';
import 'telegram_proxy_screen.dart';
import 'zapret_screen.dart';
import 'zapret_games_screen.dart';

/// Width from which the app switches to the desktop layout: a side rail and
/// content centred with a comfortable maximum width.
const double kDesktopBreakpoint = 840;

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final destination = nav.destination;
    final s = context.watch<SettingsProvider>().strings;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS || width >= kDesktopBreakpoint;
    final zapret = Platform.isWindows;

    final tabs = <_TabSpec>[
      _TabSpec(Icons.home_rounded, Icons.home_outlined, s.t('home'), NavDestination.home),
      _TabSpec(Icons.public_rounded, Icons.public_outlined, s.t('servers'), NavDestination.servers),
      if (zapret) _TabSpec(Icons.shield_rounded, Icons.shield_outlined, s.t('zapret'), NavDestination.zapret),
      _TabSpec(Icons.speed_rounded, Icons.speed_outlined, s.t('speedTest'), NavDestination.speedTest),
      _TabSpec(Icons.library_music_rounded, Icons.library_music_outlined, s.t('music'), NavDestination.music),
      if (zapret) _TabSpec(Icons.send_rounded, Icons.send_outlined, s.t('tgProxy'), NavDestination.telegramProxy),
      _TabSpec(Icons.radar_rounded, Icons.radar_outlined, s.t('jammers'), NavDestination.jammers),
      _TabSpec(Icons.insights_rounded, Icons.insights_outlined, s.t('stats'), NavDestination.stats),
      _TabSpec(Icons.settings_rounded, Icons.settings_outlined, s.t('settings'), NavDestination.settings),
    ];

    final pages = <Widget>[
      for (final tab in tabs) _pageFor(tab.destination, destination),
      if (zapret) ZapretGamesScreen(active: destination == NavDestination.zapretApps, embedded: true),
      if (zapret) ZapretScreen(active: destination == NavDestination.zapretSettings, settingsOnly: true),
    ];
    final pageIndex = switch (destination) {
      NavDestination.zapretApps => tabs.length,
      NavDestination.zapretSettings => tabs.length + 1,
      _ => tabs.indexWhere((tab) => tab.destination == destination),
    };
    final activeTab = switch (destination) {
      NavDestination.zapretApps || NavDestination.zapretSettings => tabs.indexWhere((tab) => tab.destination == NavDestination.zapret),
      _ => pageIndex,
    };
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(.018, 0), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(destination), child: IndexedStack(index: pageIndex, children: pages)),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).appBarTheme.systemOverlayStyle ?? SystemUiOverlayStyle.light,
      child: NukefyBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: desktop
              ? Column(
                  children: [
                    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) const DesktopTitleBar(),
                    Expanded(
                      child: Row(
                        children: [
                          _SideRail(tabs: tabs, index: activeTab, destination: destination),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ],
                )
              : body,
          bottomNavigationBar: desktop ? null : _BottomBar(tabs: tabs, index: activeTab),
        ),
      ),
    );
  }

  Widget _pageFor(NavDestination tab, NavDestination active) => switch (tab) {
        NavDestination.home => const HomeScreen(),
        NavDestination.servers => const ServersScreen(),
        NavDestination.zapret => ZapretScreen(active: active == NavDestination.zapret),
        NavDestination.speedTest => const SpeedTestScreen(),
        NavDestination.music => const MusicScreen(),
        NavDestination.telegramProxy => const TelegramProxyScreen(),
        NavDestination.jammers => const JammersScreen(),
        NavDestination.stats => const StatsScreen(),
        NavDestination.settings => const SettingsScreen(),
        _ => const SizedBox.shrink(),
      };
}

class _TabSpec {
  const _TabSpec(this.icon, this.outlined, this.label, this.destination);
  final IconData icon;
  final IconData outlined;
  final String label;
  final NavDestination destination;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tabs, required this.index});
  final List<_TabSpec> tabs;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      // Sits above the gesture bar; the background continues underneath.
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 10),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: p.isDark ? 0.92 : 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _Tab(
                spec: tabs[i],
                selected: index == i,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<NavProvider>().go(tabs[i].destination);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.spec, required this.selected, required this.onTap});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    // Icon-only: labels in five slots were being clipped. The tooltip keeps
    // the name available on desktop / long press.
    return Expanded(
      child: Tooltip(
        message: spec.label,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              width: selected ? 60 : 44,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                scale: selected ? 1.12 : 1,
                child: Icon(selected ? spec.icon : spec.outlined, color: color, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.tabs, required this.index, required this.destination});
  final List<_TabSpec> tabs;
  final int index;
  final NavDestination destination;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final collapsed = nav.collapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? 76 : 244,
      margin: const EdgeInsets.fromLTRB(12, 4, 0, 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!collapsed) ...[
                  const NukefyLogo(size: 32),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Nukefy', style: AppTextStyles.headline.copyWith(fontSize: 14))),
                ],
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                  tooltip: s.t(collapsed ? 'zExpandMenu' : 'zCollapseMenu'),
                  onPressed: nav.toggleRail,
                  icon: Icon(collapsed ? Icons.menu_rounded : Icons.menu_open_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    _RailItem(
                      spec: tabs[i],
                      selected: i == index,
                      collapsed: collapsed,
                      onTap: () => nav.go(tabs[i].destination),
                      onDoubleTap: Platform.isWindows && tabs[i].destination == NavDestination.zapret ? nav.toggleZapret : null,
                      trailing: Platform.isWindows && tabs[i].destination == NavDestination.zapret && !collapsed
                          ? IconButton(
                              tooltip: s.t('zApps'),
                              onPressed: nav.toggleZapret,
                              icon: Icon(
                                nav.zapretExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                size: 20,
                              ),
                            )
                          : null,
                    ),
                    if (Platform.isWindows && tabs[i].destination == NavDestination.zapret && !collapsed)
                      ClipRect(
                        child: AnimatedCrossFade(
                          duration: const Duration(milliseconds: 180),
                          firstCurve: Curves.easeOutCubic,
                          secondCurve: Curves.easeInCubic,
                          sizeCurve: Curves.easeOutCubic,
                          crossFadeState: nav.zapretExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          firstChild: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 22),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: BorderDirectional(start: BorderSide(color: p.accent.withValues(alpha: .35), width: 1)),
                              ),
                              child: Column(
                                children: [
                                  _RailItem(
                                    spec: _TabSpec(Icons.sports_esports_rounded, Icons.sports_esports_outlined, s.t('zApps'), NavDestination.zapretApps),
                                    selected: destination == NavDestination.zapretApps,
                                    collapsed: false,
                                    nested: true,
                                    onTap: () => nav.go(NavDestination.zapretApps),
                                  ),
                                  _RailItem(
                                    spec: _TabSpec(Icons.settings_suggest_rounded, Icons.settings_suggest_outlined, s.t('zSettings'), NavDestination.zapretSettings),
                                    selected: destination == NavDestination.zapretSettings,
                                    collapsed: false,
                                    nested: true,
                                    onTap: () => nav.go(NavDestination.zapretSettings),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          secondChild: const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (!collapsed) Text('v${AppConstants.version}', style: p.captionStyle),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.spec,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
    this.onDoubleTap,
    this.trailing,
    this.nested = false,
  });

  final bool collapsed;
  final VoidCallback? onDoubleTap;
  final Widget? trailing;
  final bool nested;
  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: spec.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            height: nested ? 42 : 48,
            decoration: BoxDecoration(
              color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(nested ? 12 : 16),
            ),
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : (nested ? 10 : 12)),
            child: collapsed
                ? Center(child: Icon(selected ? spec.icon : spec.outlined, size: 22, color: color))
                : Row(
                    children: [
                      Icon(selected ? spec.icon : spec.outlined, size: 21, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          spec.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.tab.copyWith(color: selected ? p.text : p.textSecondary, fontSize: nested ? 10 : 10.5),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Frameless-window title bar: drag area, app name and window controls.
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'NUKEFY VPN',
                      style: AppTextStyles.tab.copyWith(fontSize: 10, color: p.textDisabled, letterSpacing: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(icon: Icons.remove_rounded, onTap: windowManager.minimize),
          _WindowButton(
            icon: _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: _maximized ? 13 : 16,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowButton(icon: Icons.close_rounded, danger: true, onTap: windowManager.close),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({required this.icon, required this.onTap, this.danger = false, this.iconSize = 16});
  final IconData icon;
  final Future<void> Function() onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? AppColors.error.withValues(alpha: 0.85)
            : p.text.withValues(alpha: 0.08);
    final fg = _hover && widget.danger ? Colors.white : p.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: 40,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
