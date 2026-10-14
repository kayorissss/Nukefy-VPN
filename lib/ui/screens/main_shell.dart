import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nukefy_vpn/ui/widgets/nukefy_logo.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tg_ws_proxy_service.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_feedback.dart';
import 'home_screen.dart';
import 'jammers_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'diagnostics_screen.dart';
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
      // Without an entry here the analyzer had no page slot at all: every
      // tap on «Анализ соединения» landed on index -1 and painted nothing.
      _TabSpec(Icons.health_and_safety_rounded, Icons.health_and_safety_outlined, s.t('diagTitle'), NavDestination.diagnostics),
      _TabSpec(Icons.insights_rounded, Icons.insights_outlined, s.t('stats'), NavDestination.stats),
      _TabSpec(Icons.extension_rounded, Icons.extension_outlined, s.t('tabAddons'), NavDestination.addons),
      _TabSpec(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, s.t('tabAuto'), NavDestination.autotune),
      _TabSpec(Icons.dns_rounded, Icons.dns_outlined, s.t('dnsTitle'), NavDestination.dns),
      _TabSpec(Icons.settings_rounded, Icons.settings_outlined, s.t('settings'), NavDestination.settings),
    ];

    // Every page the app can show, in one list: the mobile bar and the
    // desktop rail both read it, so a page pinned on a phone appears in the
    // same place on the desktop rail and the other way round.
    final sitemap = <_TabSpec>[
      ...tabs,
      if (zapret) _TabSpec(Icons.sports_esports_rounded, Icons.sports_esports_outlined, s.t('zApps'), NavDestination.zapretApps),
      if (zapret) _TabSpec(Icons.settings_suggest_rounded, Icons.settings_suggest_outlined, s.t('zSettings'), NavDestination.zapretSettings),
    ];

    final pages = <Widget>[
      for (final tab in tabs) _pageFor(tab.destination, destination, desktop: desktop),
      if (zapret) ZapretGamesScreen(active: destination == NavDestination.zapretApps, embedded: true),
      if (zapret) ZapretScreen(active: destination == NavDestination.zapretSettings, settingsOnly: true),
      if (desktop) SettingsScreen(initialSection: 1, showSubtabs: true),
      if (desktop) SettingsScreen(initialSection: 2, showSubtabs: true),
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
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(.03, 0), end: Offset.zero).animate(animation),
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(animation),
            child: child,
          ),
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
                                _SideRail(destination: destination, sitemap: sitemap),
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
          bottomNavigationBar: desktop ? null : _BottomBar(sitemap: sitemap, destination: destination),
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
        NavDestination.diagnostics => const DiagnosticsScreen(),
        NavDestination.stats => const StatsScreen(),
        NavDestination.settings => const SettingsScreen(showSubtabs: true),
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
              child: TickerMode(
                enabled: i == widget.index,
                // Every visit plays a soft fade-and-lift, so switching tabs is
                // felt instead of the page just teleporting in.
                child: _PageReveal(active: i == widget.index, child: widget.pages[i]),
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

/// Fade + 10 px lift every time its page becomes the active one.
class _PageReveal extends StatefulWidget {
  const _PageReveal({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_PageReveal> createState() => _PageRevealState();
}

class _PageRevealState extends State<_PageReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);

  @override
  void didUpdateWidget(covariant _PageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween<double>(begin: .45, end: 1).animate(curve),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .012), end: Offset.zero).animate(curve),
        child: widget.child,
      ),
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
  const _BottomBar({required this.sitemap, required this.destination});

  final List<_TabSpec> sitemap;
  final NavDestination destination;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final nav = context.watch<NavProvider>();
    final s = context.read<SettingsProvider>().strings;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    _TabSpec? specOf(NavDestination value) {
      for (final spec in sitemap) {
        if (spec.destination == value) return spec;
      }
      return null;
    }

    final home = specOf(NavDestination.home);
    final servers = specOf(NavDestination.servers);
    final settings = specOf(NavDestination.settings);

    // The bar never scrolls and never swipes: three fixed keys, then the pages
    // the user pinned (in pin order). With nothing pinned the free slot shows
    // the page you are actually on, so the bar stays useful out of the box.
    final pinned = <_TabSpec>[];
    for (final value in nav.pins) {
      final spec = specOf(value);
      if (spec != null && !pinned.contains(spec)) pinned.add(spec);
    }
    if (pinned.isEmpty) {
      final here = specOf(destination);
      if (here != null && here.destination != NavDestination.home && here.destination != NavDestination.servers && here.destination != NavDestination.settings) {
        pinned.add(here);
      }
    }

    final slots = <_TabSpec>[
      if (home != null) home,
      if (servers != null) servers,
      ...pinned,
      if (settings != null) settings,
    ];
    final more = _TabSpec(Icons.more_horiz_rounded, Icons.more_horiz_rounded, s.t('sitemap'), NavDestination.speedTest);

    return Padding(
      // Sits above the gesture bar; the background continues underneath.
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 10),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(22),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = slots.length + 1;
            final slotWidth = constraints.maxWidth / count;
            return Row(
              children: [
                for (final spec in slots)
                  _Tab(
                    spec: spec,
                    selected: spec.destination == destination,
                    maxWidth: slotWidth,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<NavProvider>().go(spec.destination);
                    },
                  ),
                _Tab(
                  spec: more,
                  selected: false,
                  maxWidth: slotWidth,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showSitemap(context, sitemap, desktop: false);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The section map: every page of the app, with a pin for the ones the user
/// wants in the bar. It is a bottom sheet on phones and a compact card on the
/// desktop, where it opens from the three-dot button in the rail header.
Future<void> _showSitemap(BuildContext context, List<_TabSpec> entries, {required bool desktop}) {
  if (desktop) {
    return showDialog<void>(
      context: context,
      builder: (_) => _SitemapCard(entries: entries),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.card,
    builder: (_) => _SitemapCard(entries: entries, sheet: true),
  );
}

class _SitemapCard extends StatelessWidget {
  const _SitemapCard({required this.entries, this.sheet = false});

  final List<_TabSpec> entries;
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.map_rounded, size: 18, color: p.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('sitemap'), style: AppTextStyles.headline)),
            Text('${s.t('pinnedOf')} ${nav.pins.length}/${NavProvider.maxPins}',
                style: AppTextStyles.bodySecondary.copyWith(fontSize: 12, color: p.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        Text(s.t('sitemapHint'), style: AppTextStyles.bodySecondary.copyWith(fontSize: 12.5, color: p.textSecondary)),
        const SizedBox(height: 10),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final spec in entries) _SitemapRow(spec: spec),
              ],
            ),
          ),
        ),
      ],
    );
    if (!sheet) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 560),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.border),
            ),
            child: body,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 520), child: body),
    );
  }
}

class _SitemapRow extends StatelessWidget {
  const _SitemapRow({required this.spec});

  final _TabSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final destination = nav.destination;
    final selected = spec.destination == destination;
    final fixed = _isFixedSlot(spec.destination);
    final pinned = nav.isPinned(spec.destination);
    final index = nav.pinIndex(spec.destination);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).pop();
        nav.go(spec.destination);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(selected ? spec.icon : spec.outlined, size: 18, color: selected ? p.accent : p.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? p.accent : p.text)),
            ),
            if (fixed)
              Tooltip(
                message: s.t('alwaysInBar'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.vertical_align_bottom_rounded, size: 15, color: p.textSecondary),
                ),
              )
            else
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                tooltip: pinned ? s.t('unpin') : s.t('pin'),
                onPressed: () {
                  final ok = nav.togglePin(spec.destination);
                  if (!ok) showNukefySnack(context, s.t('pinLimit'), error: true);
                },
                icon: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 17,
                  color: pinned ? p.accent : p.textDisabled,
                ),
              ),
            if (pinned)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6),
                child: Text('${index + 1}',
                    style: AppTextStyles.bodySecondary.copyWith(fontSize: 11, color: p.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The three keys that are always on the bar, so pinning them would be a
/// no-op the user cannot explain.
bool _isFixedSlot(NavDestination value) =>
    value == NavDestination.home || value == NavDestination.servers || value == NavDestination.settings;

class _Tab extends StatelessWidget {
  const _Tab({required this.spec, required this.selected, required this.onTap, this.maxWidth = 60});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  /// Width of one bar slot. The pill shrinks instead of overflowing when the
  /// user pins pages on a narrow phone.
  final double maxWidth;

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
              width: (selected ? 60.0 : 44.0) < maxWidth ? (selected ? 60.0 : 44.0) : maxWidth,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
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
  const _RailGroup({required this.key, required this.icon, required this.label, this.destination, required this.leaves, this.alwaysOpen = false});
  final String key;
  final IconData icon;
  final String label;
  final NavDestination? destination;
  final List<_RailLeaf> leaves;

  /// Home is a permanent section: it has no chevron and never folds away.
  final bool alwaysOpen;
}

/// Grouped navigation: four sections with sub-pages, plus a fixed bottom
/// row for auto-tune, add-ons and the wide settings button.
class _SideRail extends StatefulWidget {
  const _SideRail({required this.destination, required this.sitemap});
  final NavDestination destination;
  final List<_TabSpec> sitemap;
  @override
  State<_SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<_SideRail> {
  static final Map<String, bool> _open = {};

  /// User-dragged rail width (expanded mode). Dragging the right edge is
  /// faster than hunting for the collapse button, and the choice persists.
  double _customWidth = (double.tryParse(StorageService.instance.read('railWidth') ?? '') ?? 272).clamp(220, 380).toDouble();
  bool _draggingRail = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<SettingsProvider>().strings;
    final nav = context.watch<NavProvider>();
    final collapsed = nav.collapsed;
    final zapret = Platform.isWindows;
    final destination = widget.destination;
    // Pinned pages keep their pin order here too, so the rail and the phone
    // bar never disagree about what sits where.
    final pinnedSpecs = <_TabSpec>[];
    for (final value in nav.pins) {
      for (final spec in widget.sitemap) {
        if (spec.destination == value && !pinnedSpecs.contains(spec)) pinnedSpecs.add(spec);
      }
    }

    final groups = <_RailGroup>[
      _RailGroup(key: 'home', alwaysOpen: true, icon: Icons.home_rounded, label: s.t('home'), destination: NavDestination.home, leaves: [
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
        // The connection analyzer used to hide behind a button on the home
        // screen, which is exactly where nobody looks when the tunnel fails.
        _RailLeaf(icon: Icons.health_and_safety_rounded, label: s.t('diagTitle'), destination: NavDestination.diagnostics),
      ]),
    ];

    // Every section starts open so the whole map is visible at once; the
    // chevron folds the ones the user does not need. Home never folds.
    bool openOf(_RailGroup g) => g.alwaysOpen || (_open[g.key] ?? true);

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    final rail = AnimatedContainer(
      duration: _draggingRail ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? 82 : _customWidth,
      margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          // Header: the brand lives here, next to the collapse toggle. The
          // toggle used to float alone in an empty strip above "ГЛАВНАЯ".
          if (collapsed)
            Column(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  tooltip: s.t('zExpandMenu'),
                  onPressed: nav.toggleRail,
                  icon: const Icon(Icons.menu_rounded, size: 19),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  tooltip: s.t('sitemap'),
                  onPressed: () => _showSitemap(context, widget.sitemap, desktop: true),
                  icon: Icon(Icons.more_horiz_rounded, size: 19, color: p.textSecondary),
                ),
                const SizedBox(height: 2),
              ],
            )
          else
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  // No brand glyph here: it sat above «ГЛАВНАЯ» as a stray
                  // icon with no job. The sections start immediately.
                  const Spacer(),
                  // Right side of the header: the pinned pages as plain icons,
                  // then the three-dot map of everything else.
                  for (final pin in pinnedSpecs)
                    Tooltip(
                      message: pin.label,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        onPressed: () => nav.go(pin.destination),
                        icon: Icon(pin.icon,
                            size: 16, color: pin.destination == destination ? p.accent : p.textSecondary),
                      ),
                    ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    tooltip: s.t('sitemap'),
                    onPressed: () => _showSitemap(context, widget.sitemap, desktop: true),
                    icon: Icon(pinnedSpecs.isEmpty ? Icons.more_horiz_rounded : Icons.more_vert_rounded,
                        size: 19, color: p.textSecondary),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    tooltip: s.t('zCollapseMenu'),
                    onPressed: nav.toggleRail,
                    icon: const Icon(Icons.menu_rounded, size: 19),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final g in groups) ...[
                    if (collapsed) ...[
                      if (g != groups.first)
                        Container(
                          width: 30,
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          color: p.border,
                        ),
                      if (g.destination != null) iconButton(g.destination!, g.icon, g.label),
                      for (final l in g.leaves) iconButton(l.destination, l.icon, l.label),
                    ] else ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          if (!g.alwaysOpen) _open[g.key] = !openOf(g);
                          if (g.destination != null) nav.go(g.destination!);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: g.destination == destination ? p.accent.withValues(alpha: .14) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
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
                              if (!g.alwaysOpen)
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
    if (collapsed) return rail;
    // Drag handle on the right edge: grab and pull to resize the menu
    // instead of only toggling it with the collapse button.
    return Stack(
      children: [
        rail,
        Positioned(
          right: 0,
          top: 0,
          bottom: 12,
          width: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _draggingRail = true),
              onHorizontalDragUpdate: (details) {
                setState(() => _customWidth = (_customWidth + details.delta.dx).clamp(220, 380).toDouble());
              },
              onHorizontalDragEnd: (_) {
                setState(() => _draggingRail = false);
                StorageService.instance.write('railWidth', _customWidth.round().toString());
              },
            ),
          ),
        ),
      ],
    );
  }
}

class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.watch<SettingsProvider>().strings;
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
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const NukefyLogo(size: 18),
                      const SizedBox(width: 8),
                      Text('Nukefy Client',
                          style: AppTextStyles.headline.copyWith(fontSize: 12, letterSpacing: .8, color: p.textSecondary)),
                      const SizedBox(width: 8),
                      // The installed version, right where people look for it.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.accent.withValues(alpha: .35)),
                        ),
                        child: Text(AppConstants.version,
                            style: AppTextStyles.headline.copyWith(fontSize: 10.5, letterSpacing: .4, color: p.accent)),
                      ),
                      const SizedBox(width: 6),
                      // Public beta: state it right next to the number instead
                      // of pretending this is a finished release.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.text.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.border),
                        ),
                        child: Text(s.t('betaTag').toUpperCase(),
                            style: AppTextStyles.headline.copyWith(fontSize: 9.5, letterSpacing: 1.1, color: p.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Minimize + Close. The shell still lives maximized (the guard in
          // main.dart re-maximizes on restore and explicitly leaves a
          // minimized window alone), but the user asked for the minimize
          // dash back next to the cross — minimizing to the taskbar is a
          // real, working action, not a restore that snaps back.
          _WindowButton(icon: Icons.remove_rounded, onTap: windowManager.minimize),
          _WindowButton(icon: Icons.close_rounded, danger: true, onTap: windowManager.close),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({required this.icon, required this.onTap, this.danger = false});
  final IconData icon;
  final Future<void> Function() onTap;
  final bool danger;

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
          child: Icon(widget.icon, size: 16, color: fg),
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
            // Kept visible as brand art, but never strong enough to fight the
            // text: at 0.92 in the light theme the mascot showed through the
            // (then translucent) cards and read as overlapping ghost text.
            opacity: dark ? 0.12 : 0.25,
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
