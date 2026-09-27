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
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'zapret_screen.dart';
import 'zapret_games_screen.dart';

/// Width from which the app switches to the desktop layout: a side rail and
/// content centred with a comfortable maximum width.
const double kDesktopBreakpoint = 840;

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final index = context.watch<NavProvider>().index;
    final s = context.watch<SettingsProvider>().strings;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS || width >= kDesktopBreakpoint;

    final zapret = Platform.isWindows;
    final tabs = <_TabSpec>[
      _TabSpec(Icons.home_rounded, Icons.home_outlined, s.t('home')),
      _TabSpec(Icons.public_rounded, Icons.public_outlined, s.t('servers')),
      if (zapret) _TabSpec(Icons.shield_rounded, Icons.shield_outlined, s.t('zapret')),
      _TabSpec(Icons.radar_rounded, Icons.radar_outlined, s.t('jammers')),
      _TabSpec(Icons.insights_rounded, Icons.insights_outlined, s.t('stats')),
      _TabSpec(Icons.settings_rounded, Icons.settings_outlined, s.t('settings')),
    ];

    final pages = <Widget>[
      const HomeScreen(),
      const ServersScreen(),
      if (zapret) ZapretScreen(active: index == 2),
      const JammersScreen(),
      const StatsScreen(),
      const SettingsScreen(),
      if (zapret) ZapretGamesScreen(active: index == 6, embedded: true),
    ];

    final body = IndexedStack(index: index, children: pages);

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
                          _SideRail(tabs: tabs, index: index),
                          Expanded(
                            child: body,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : body,
          bottomNavigationBar: desktop ? null : _BottomBar(tabs: tabs, index: index),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.icon, this.outlined, this.label);
  final IconData icon;
  final IconData outlined;
  final String label;
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
                  context.read<NavProvider>().setIndex(i);
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
  const _SideRail({required this.tabs, required this.index});
  final List<_TabSpec> tabs;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final collapsed = nav.collapsed;
    return Container(
      width: collapsed ? 72 : 220,
      margin: const EdgeInsets.fromLTRB(12, 4, 0, 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: p.border)),
      child: Column(children: [
        Row(children: [
          if (!collapsed) ...[const NukefyLogo(size: 32), const Spacer()],
          IconButton(tooltip: s.t(nav.collapsed ? 'zExpandMenu' : 'zCollapseMenu'), onPressed: nav.toggleRail, icon: Icon(nav.collapsed ? Icons.menu : Icons.menu_open)),
        ]),
        const SizedBox(height: 16),
        Expanded(child: SingleChildScrollView(child: Column(children: [
          for (var i = 0; i < tabs.length; i++) ...[
            Row(children: [Expanded(child: _RailItem(
              spec: tabs[i], selected: i == index, collapsed: collapsed,
              onTap: () => nav.setIndex(i),
              onDoubleTap: Platform.isWindows && i == 2 ? nav.toggleZapret : null,
            )),
              if (Platform.isWindows && i == 2 && !collapsed) IconButton(
                tooltip: s.t('zApps'), onPressed: nav.toggleZapret,
                icon: Icon(nav.zapretExpanded ? Icons.expand_less : Icons.expand_more, size: 18)),
            ]),
            if (Platform.isWindows && i == 2)
              AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter,
                child: nav.zapretExpanded || collapsed
                  ? _RailItem(spec: _TabSpec(Icons.sports_esports, Icons.sports_esports_outlined, s.t('zApps')), selected: index == 6, collapsed: collapsed, onTap: () => nav.setIndex(6))
                  : const SizedBox(width: double.infinity)),
          ],
        ]))),
        if (!collapsed) Text('v${AppConstants.version}', style: p.captionStyle),
      ]),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.spec, required this.selected, required this.onTap, this.collapsed = false, this.onDoubleTap});
  final bool collapsed;
  final VoidCallback? onDoubleTap;

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(message: spec.label, child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(selected ? spec.icon : spec.outlined, size: 20, color: color),
                if (!collapsed) const SizedBox(width: 12),
                if (!collapsed) Expanded(
                  child: Text(
                    spec.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.tab.copyWith(color: selected ? p.text : p.textSecondary, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      )),
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
