import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/tg_ws_proxy_service.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_background.dart';
import 'home_screen.dart';
import 'jammers_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'dns_screen.dart';
import 'speed_test_screen.dart';
import 'stats_screen.dart';
import 'telegram_proxy_screen.dart';
import 'addons_screen.dart';
import 'autotune_screen.dart';
import 'karing_screen.dart';
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
      _TabSpec(Icons.route_rounded, Icons.route_outlined, s.t('tabKaring'), NavDestination.karing),
      _TabSpec(Icons.speed_rounded, Icons.speed_outlined, s.t('speedTest'), NavDestination.speedTest),
      if (zapret) _TabSpec(Icons.send_rounded, Icons.send_outlined, s.t('tgProxy'), NavDestination.telegramProxy),
      _TabSpec(Icons.radar_rounded, Icons.radar_outlined, s.t('jammers'), NavDestination.jammers),
      _TabSpec(Icons.insights_rounded, Icons.insights_outlined, s.t('stats'), NavDestination.stats),
      _TabSpec(Icons.extension_rounded, Icons.extension_outlined, s.t('tabAddons'), NavDestination.addons),
      _TabSpec(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, s.t('tabAuto'), NavDestination.autotune),
      _TabSpec(Icons.dns_rounded, Icons.dns_outlined, s.t('dnsTitle'), NavDestination.dns),
      _TabSpec(Icons.settings_rounded, Icons.settings_outlined, s.t('settings'), NavDestination.settings),
    ];

    final pages = <Widget>[
      for (final tab in tabs) _pageFor(tab.destination, destination, desktop: desktop),
      if (zapret) ZapretGamesScreen(active: destination == NavDestination.zapretApps, embedded: true),
      if (zapret) ZapretScreen(active: destination == NavDestination.zapretSettings, settingsOnly: true),
      if (desktop) SettingsScreen(initialSection: 1, showSubtabs: false),
      if (desktop) SettingsScreen(initialSection: 2, showSubtabs: false),
    ];
    final pageIndex = switch (destination) {
      NavDestination.zapretApps => tabs.length,
      NavDestination.zapretSettings => tabs.length + 1,
      NavDestination.settingsGeneral => tabs.indexWhere((tab) => tab.destination == NavDestination.settings),
      NavDestination.settingsAppearance => tabs.length + (zapret ? 2 : 0),
      NavDestination.settingsAbout => tabs.length + (zapret ? 2 : 0) + 1,
      // DNS is a first-class tab now; the legacy settings child route follows.
      NavDestination.settingsDns => tabs.indexWhere((tab) => tab.destination == NavDestination.dns),
      _ => tabs.indexWhere((tab) => tab.destination == destination),
    };
    final activeTab = switch (destination) {
      // Child destinations own the highlight. Keeping the parent selected at
      // the same time made Zapret look like two active tabs, especially on
      // the mobile bottom bar.
      NavDestination.zapretApps || NavDestination.zapretSettings || NavDestination.settingsGeneral || NavDestination.settingsAppearance || NavDestination.settingsAbout => -1,
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
      // Keep the page host itself stable.  Keying an IndexedStack by the
      // destination rebuilt every screen on each tap (and discarded the
      // entered server when returning from the tray).  The lazy host below
      // creates a screen only on first visit and keeps it alive afterwards.
      child: _LazyPageStack(index: pageIndex, pages: pages),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).appBarTheme.systemOverlayStyle ?? SystemUiOverlayStyle.light,
      child: NukefyBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // The mobile rail is a real layout region. Let the Scaffold reserve
          // its height instead of painting pages underneath it: music controls
          // and the last settings row must never be hidden behind navigation.
          extendBody: false,
          extendBodyBehindAppBar: false,
          body: Column(
            children: [
              Expanded(
                child: desktop
                    ? Column(
                        children: [
                          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) const DesktopTitleBar(),
                          Expanded(
                            child: Row(
                              children: [
                                _SideRail(destination: destination),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      const Positioned.fill(child: _MascotBackdrop()),
                                      Align(
                                        alignment: Alignment.topCenter,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 2200),
                                          child: SizedBox(width: double.infinity, child: body),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : body,
              ),
            ],
          ),
          bottomNavigationBar: desktop ? null : _BottomBar(tabs: tabs, index: activeTab),
        ),
      ),
    );
  }

  Widget _pageFor(NavDestination tab, NavDestination active, {required bool desktop}) => switch (tab) {
        NavDestination.home => const HomeScreen(),
        NavDestination.servers => const ServersScreen(),
        NavDestination.zapret => ZapretScreen(active: active == NavDestination.zapret),
        NavDestination.karing => KaringScreen(active: active == NavDestination.karing),
        NavDestination.addons => const AddonsScreen(),
        NavDestination.autotune => const AutoTuneScreen(),
        NavDestination.dns => const DnsScreen(),
        NavDestination.speedTest => const SpeedTestScreen(),
        NavDestination.telegramProxy => const TelegramProxyScreen(),
        NavDestination.jammers => const JammersScreen(),
        NavDestination.stats => const StatsScreen(),
        NavDestination.settings => SettingsScreen(showSubtabs: !desktop),
        _ => const SizedBox.shrink(),
      };
}

class _LazyPageStack extends StatefulWidget {
  const _LazyPageStack({required this.index, required this.pages});

  final int index;
  final List<Widget> pages;

  @override
  State<_LazyPageStack> createState() => _LazyPageStackState();
}

class _LazyPageStackState extends State<_LazyPageStack> {
  final Set<int> _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _visit(widget.index);
  }

  @override
  void didUpdateWidget(covariant _LazyPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visit(widget.index);
  }

  void _visit(int index) {
    if (index >= 0 && index < widget.pages.length) _visited.add(index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          if (_visited.contains(i))
            Offstage(
              offstage: i != widget.index,
              child: TickerMode(enabled: i == widget.index, child: widget.pages[i]),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }
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
    // Keep the bottom bar legible on a phone. Less common tools remain one
    // tap away in More instead of shrinking nine icons into unreadable slots.
    const primaryDestinations = <NavDestination>{
      NavDestination.home,
      NavDestination.servers,
      NavDestination.stats,
      NavDestination.settings,
    };
    final primary = tabs.where((tab) => primaryDestinations.contains(tab.destination)).toList();
    final extra = tabs.where((tab) => !primaryDestinations.contains(tab.destination)).toList();
    bool selected(_TabSpec tab) {
      if (tab.destination == NavDestination.settings) {
        return index == tabs.indexWhere((item) => item.destination == NavDestination.settings);
      }
      return index == tabs.indexOf(tab);
    }
    final extraSelected = extra.any((tab) => index == tabs.indexOf(tab));
    final more = _TabSpec(Icons.more_horiz_rounded, Icons.more_horiz_rounded, context.read<SettingsProvider>().strings.t('more'), NavDestination.speedTest);
    final visibleCount = primary.length + (extra.isEmpty ? 0 : 1);

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
            for (final spec in primary)
              _Tab(
                spec: spec,
                selected: selected(spec),
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.read<NavProvider>().go(spec.destination);
                },
              ),
            if (extra.isNotEmpty)
              _Tab(
                spec: more,
                selected: extraSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showMobileMore(context, extra, index >= 0 && index < tabs.length ? tabs[index].destination : null);
                },
              ),
          ].take(visibleCount).toList(),
        ),
      ),
    );
  }
}

Future<void> _showMobileMore(BuildContext context, List<_TabSpec> tabs, NavDestination? current) {
  final s = context.read<SettingsProvider>().strings;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.card,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('more'), style: AppTextStyles.headline),
          const SizedBox(height: 8),
          for (final spec in tabs)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(spec.icon, color: spec.destination == current ? context.palette.accent : context.palette.textSecondary),
              title: Text(spec.label),
              trailing: spec.destination == current ? Icon(Icons.check_rounded, color: context.palette.accent) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<NavProvider>().go(spec.destination);
              },
            ),
        ],
      ),
    ),
  );
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
    final running = switch (spec.destination) {
      NavDestination.home => context.watch<VpnProvider>().status == VpnStatus.connected,
      NavDestination.zapret => context.watch<ZapretService>().isRunning,
      NavDestination.telegramProxy => context.watch<TgWsProxyService>().running,
      _ => false,
    };
    // Icon-only: labels in five slots were being clipped. The tooltip keeps
    // the name available on desktop / long press.
    return Expanded(
      child: Tooltip(
        message: spec.label,
        waitDuration: const Duration(milliseconds: 800),
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
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1.12 : 1,
                    child: Icon(selected ? spec.icon : spec.outlined, color: color, size: 24),
                  ),
                  if (running)
                    Positioned(
                      top: 1,
                      right: 8,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: p.success,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: p.success.withValues(alpha: .55), blurRadius: 5)],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailLeaf {
  const _RailLeaf({required this.icon, required this.label, required this.destination});
  final IconData icon;
  final String label;
  final NavDestination destination;
}

class _RailGroup {
  const _RailGroup({required this.key, required this.icon, required this.label, this.destination, required this.leaves});
  final String key;
  final IconData icon;
  final String label;
  final NavDestination? destination;
  final List<_RailLeaf> leaves;
}

/// Grouped navigation: four sections with sub-pages, plus a fixed bottom
/// row for auto-tune, add-ons and the wide settings button.
class _SideRail extends StatefulWidget {
  const _SideRail({required this.destination});
  final NavDestination destination;
  @override
  State<_SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<_SideRail> {
  static final Map<String, bool> _open = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final collapsed = nav.collapsed;
    final zapret = Platform.isWindows;
    final destination = widget.destination;

    final groups = <_RailGroup>[
      _RailGroup(key: 'home', icon: Icons.home_rounded, label: s.t('home'), destination: NavDestination.home, leaves: [
        _RailLeaf(icon: Icons.public_rounded, label: s.t('servers'), destination: NavDestination.servers),
        _RailLeaf(icon: Icons.insights_rounded, label: s.t('stats'), destination: NavDestination.stats),
      ]),
      if (zapret)
        _RailGroup(key: 'zapret', icon: Icons.shield_rounded, label: s.t('zapret'), destination: NavDestination.zapret, leaves: [
          _RailLeaf(icon: Icons.sports_esports_rounded, label: s.t('zApps'), destination: NavDestination.zapretApps),
          _RailLeaf(icon: Icons.dns_rounded, label: s.t('dnsTitle'), destination: NavDestination.dns),
          _RailLeaf(icon: Icons.settings_suggest_rounded, label: s.t('zSettings'), destination: NavDestination.zapretSettings),
        ]),
      _RailGroup(key: 'bypass', icon: Icons.alt_route_rounded, label: s.t('railBypasses'), leaves: [
        _RailLeaf(icon: Icons.route_rounded, label: s.t('tabKaring'), destination: NavDestination.karing),
        _RailLeaf(icon: Icons.send_rounded, label: s.t('tgProxy'), destination: NavDestination.telegramProxy),
      ]),
      _RailGroup(key: 'monitor', icon: Icons.monitor_heart_rounded, label: s.t('railMonitoring'), leaves: [
        _RailLeaf(icon: Icons.speed_rounded, label: s.t('speedTest'), destination: NavDestination.speedTest),
        _RailLeaf(icon: Icons.radar_rounded, label: s.t('jammers'), destination: NavDestination.jammers),
      ]),
    ];

    bool openOf(_RailGroup g) =>
        _open[g.key] ?? (g.destination == destination || g.leaves.any((l) => l.destination == destination));

    bool segSelected(NavDestination dest) =>
        dest == destination ||
        (dest == NavDestination.settingsGeneral &&
            (destination == NavDestination.settingsAppearance || destination == NavDestination.settingsAbout));

    Widget _wideButton(NavDestination dest, IconData icon, String label) => SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => nav.go(dest),
            style: OutlinedButton.styleFrom(
              backgroundColor: segSelected(dest) ? p.accent.withValues(alpha: .12) : null,
              foregroundColor: segSelected(dest) ? p.accent : p.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: Icon(icon, size: 17),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );

    Widget _segmentIcon(NavDestination dest, IconData icon, String label) => IconButton(
          tooltip: label,
          onPressed: () => nav.go(dest),
          icon: Icon(icon, size: 20, color: segSelected(dest) ? p.accent : p.textSecondary),
        );

    Widget iconButton(NavDestination dest, IconData icon, String label) {
      final selected = dest == destination;
      return IconButton(
        tooltip: label,
        onPressed: () => nav.go(dest),
        icon: Icon(icon, size: 21, color: selected ? p.accent : p.textSecondary),
        style: IconButton.styleFrom(
          backgroundColor: selected ? p.accent.withValues(alpha: .14) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? 82 : 272,
      margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: .82),
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
                  Expanded(
                    child: Text('NUKEFY CLIENT',
                        style: AppTextStyles.headline.copyWith(fontSize: 13, letterSpacing: 1.2)),
                  ),
                ],
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                  tooltip: s.t(collapsed ? 'zExpandMenu' : 'zCollapseMenu'),
                  onPressed: nav.toggleRail,
                  icon: Icon(collapsed ? Icons.menu_rounded : Icons.menu_open_rounded, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final g in groups) ...[
                    if (collapsed) ...[
                      if (g.destination != null) iconButton(g.destination!, g.icon, g.label),
                      for (final l in g.leaves) iconButton(l.destination, l.icon, l.label),
                    ] else ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() {
                          final next = !openOf(g);
                          _open[g.key] = next;
                          if (g.destination != null) nav.go(g.destination!);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: g.destination == destination ? p.accent.withValues(alpha: .14) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(g.icon, size: 20, color: g.destination == destination ? p.accent : p.text),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(g.label.toUpperCase(),
                                    style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .8,
                                        color: g.destination == destination ? p.accent : p.text)),
                              ),
                              Icon(Icons.expand_more_rounded, size: 18, color: p.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      if (openOf(g))
                        for (final l in g.leaves)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => nav.go(l.destination),
                            child: Container(
                              margin: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: l.destination == destination ? p.accent.withValues(alpha: .14) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(l.icon, size: 17, color: l.destination == destination ? p.accent : p.textSecondary),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(l.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodyRegular.copyWith(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: l.destination == destination ? p.accent : p.textSecondary)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ],
              ),
            ),
          ),
          // One wide pill, three independent segments: auto-tune, add-ons
          // and settings. Collapsed rail stacks them vertically.
          if (collapsed)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _segmentIcon(NavDestination.autotune, Icons.auto_awesome_rounded, s.t('tabAuto')),
                  Container(height: 1, color: p.border),
                  _segmentIcon(NavDestination.addons, Icons.extension_rounded, s.t('tabAddons')),
                  Container(height: 1, color: p.border),
                  _segmentIcon(NavDestination.settingsGeneral, Icons.settings_rounded, s.t('settings')),
                ],
              ),
            )
          else ...[
            _wideButton(NavDestination.autotune, Icons.auto_awesome_rounded, s.t('tabAuto')),
            const SizedBox(height: 6),
            _wideButton(NavDestination.addons, Icons.extension_rounded, s.t('tabAddons')),
            const SizedBox(height: 6),
            _wideButton(NavDestination.settingsGeneral, Icons.settings_rounded, s.t('settings')),
          ],
        ],
      ),
    );
  }
}

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
            ? p.error.withValues(alpha: 0.85)
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

/// The mascot artwork pinned to the right edge of the page area. It fades
/// into the background on the left/top, never captures pointer events and
/// dims itself in the dark theme so cards stay readable.
class _MascotBackdrop extends StatelessWidget {
  const _MascotBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: FractionallySizedBox(
          heightFactor: 0.96,
          child: Opacity(
            opacity: dark ? 0.14 : 0.92,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.transparent, Colors.white],
                stops: const [0.0, 0.22],
              ).createShader(bounds),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [Colors.transparent, Colors.white],
                  stops: const [0.04, 0.5],
                ).createShader(bounds),
                child: Image.asset('assets/rkntyan.png', fit: BoxFit.contain, alignment: Alignment.bottomRight, gaplessPlayback: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
