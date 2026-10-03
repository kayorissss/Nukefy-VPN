import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/music_service.dart';
import '../../core/services/tg_ws_proxy_service.dart';
import '../../core/services/zapret_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/music_visualizer.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_logo.dart';
import 'home_screen.dart';
import 'jammers_screen.dart';
import 'music_screen.dart';
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
      if (context.watch<SettingsProvider>().settings.musicUnlocked || context.watch<MusicService>().tracks.isNotEmpty)
        _TabSpec(Icons.library_music_rounded, Icons.library_music_outlined, s.t('music'), NavDestination.music),
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
                                _SideRail(tabs: tabs, index: activeTab, destination: destination),
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
              // Desktop has the compact player in the left rail.  Keeping a
              // second full-width bar here wasted vertical space and made
              // navigation look like a duplicated Music screen.  Mobile
              // retains the larger touch-friendly controls.
              if (!desktop)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: context.watch<MusicService>().currentTrack == null
                      ? const SizedBox(key: ValueKey('music-player-hidden'))
                      : const _GlobalMusicBar(key: ValueKey('music-player-visible')),
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
        NavDestination.music => const MusicScreen(),
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

class _GlobalMusicBar extends StatelessWidget {
  const _GlobalMusicBar({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicService>();
    final track = music.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final artworkSize = compact ? 50.0 : 58.0;
    final total = music.duration.inMilliseconds <= 0 ? 1.0 : music.duration.inMilliseconds.toDouble();
    final position = music.position.inMilliseconds.clamp(0, total.toInt()).toDouble();
    final artwork = track.artworkPath;

    Widget artworkView() {
      final fallback = Container(
        width: artworkSize,
        height: artworkSize,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.accent.withValues(alpha: .3), p.accent2.withValues(alpha: .22)],
          ),
        ),
        child: Icon(Icons.music_note_rounded, color: p.accent, size: artworkSize * .42),
      );
      return Container(
        width: artworkSize,
        height: artworkSize,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: p.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: artwork == null
              ? fallback
              : Image.file(
                  File(artwork),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  color: p.surface,
                  colorBlendMode: BlendMode.dstOver,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      );
    }

    Widget playButton() => IconButton(
          tooltip: music.isPlaying ? s.t('musicPause') : s.t('musicPlay'),
          onPressed: music.toggle,
          icon: Icon(
            music.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
            color: p.accent,
            size: compact ? 30 : 34,
          ),
        );

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 18, 5, compact ? 10 : 18, 10),
        child: Align(
          alignment: AlignmentDirectional.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Material(
              color: p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: p.accent.withValues(alpha: .38)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 9 : 14, compact ? 8 : 10, compact ? 9 : 14, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        artworkView(),
                        SizedBox(width: compact ? 9 : 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(track.title.trim().isEmpty ? s.t('musicUntitled') : track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(track.artist.trim().isEmpty ? s.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.secondaryStyle),
                            ],
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 12),
                          MusicVisualizer(active: music.isPlaying, color: p.accent, height: 22, barCount: 12),
                          const SizedBox(width: 6),
                        ],
                        IconButton(tooltip: s.t('musicPrevious'), onPressed: music.previous, icon: const Icon(Icons.skip_previous_rounded)),
                        playButton(),
                        IconButton(tooltip: s.t('musicNext'), onPressed: music.next, icon: const Icon(Icons.skip_next_rounded)),
                        if (!compact)
                          IconButton(tooltip: s.t('musicStop'), onPressed: music.stop, icon: const Icon(Icons.stop_rounded))
                        else
                          PopupMenuButton<String>(
                            tooltip: s.t('musicStop'),
                            onSelected: (_) => music.stop(),
                            itemBuilder: (_) => [PopupMenuItem(value: 'stop', child: Text(s.t('musicStop')))],
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 3),
                        Text(_globalMusicDuration(music.position), style: p.captionStyle),
                        Expanded(
                          child: Slider(
                            value: position,
                            max: total,
                            onChanged: (value) => music.seek(Duration(milliseconds: value.round())),
                          ),
                        ),
                        Text(_globalMusicDuration(music.duration), style: p.captionStyle),
                        const SizedBox(width: 3),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _globalMusicDuration(Duration value) => '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

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
      NavDestination.music,
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
                      // A Zapret child page is its own destination.  Do not
                      // paint the parent as selected at the same time.
                      selected: i == index &&
                          !(tabs[i].destination == NavDestination.zapret &&
                              (destination == NavDestination.zapretApps || destination == NavDestination.zapretSettings)) &&
                          !(tabs[i].destination == NavDestination.settings &&
                              (destination == NavDestination.settingsGeneral || destination == NavDestination.settingsAppearance || destination == NavDestination.settingsAbout)),
                      collapsed: collapsed,
                      onTap: () => nav.go(
                        tabs[i].destination == NavDestination.settings ? NavDestination.settingsGeneral : tabs[i].destination,
                      ),
                      onDoubleTap: Platform.isWindows && tabs[i].destination == NavDestination.zapret
                          ? nav.toggleZapret
                          : (tabs[i].destination == NavDestination.settings ? nav.toggleSettings : null),
                      trailing: Platform.isWindows && tabs[i].destination == NavDestination.zapret && !collapsed
                          ? IconButton(
                              tooltip: s.t('zApps'),
                              onPressed: nav.toggleZapret,
                              icon: Icon(
                                nav.zapretExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                size: 20,
                              ),
                            )
                          : tabs[i].destination == NavDestination.settings && !collapsed
                              ? IconButton(
                                  tooltip: s.t('settingsTab'),
                                  onPressed: nav.toggleSettings,
                                  icon: Icon(
                                    nav.settingsExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
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
                            // Use spacing and the selected pill as the
                            // hierarchy cue.  The permanent one-pixel rail
                            // looked like a broken tab underline and made a
                            // child appear to belong to two active tabs.
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
                          secondChild: const SizedBox.shrink(),
                        ),
                      ),
                    if (tabs[i].destination == NavDestination.settings && !collapsed)
                      ClipRect(
                        child: AnimatedCrossFade(
                          duration: const Duration(milliseconds: 180),
                          firstCurve: Curves.easeOutCubic,
                          secondCurve: Curves.easeInCubic,
                          sizeCurve: Curves.easeOutCubic,
                          crossFadeState: nav.settingsExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          firstChild: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 22),
                            child: Column(
                              children: [
                                _RailItem(
                                  spec: _TabSpec(Icons.tune_rounded, Icons.tune_outlined, s.t('general'), NavDestination.settingsGeneral),
                                  selected: destination == NavDestination.settingsGeneral,
                                  collapsed: false,
                                  nested: true,
                                  onTap: () => nav.go(NavDestination.settingsGeneral),
                                ),
                                _RailItem(
                                  spec: _TabSpec(Icons.palette_outlined, Icons.palette_rounded, s.t('appearanceTab'), NavDestination.settingsAppearance),
                                  selected: destination == NavDestination.settingsAppearance,
                                  collapsed: false,
                                  nested: true,
                                  onTap: () => nav.go(NavDestination.settingsAppearance),
                                ),
                                _RailItem(
                                  spec: _TabSpec(Icons.info_outline_rounded, Icons.info_rounded, s.t('aboutTab'), NavDestination.settingsAbout),
                                  selected: destination == NavDestination.settingsAbout,
                                  collapsed: false,
                                  nested: true,
                                  onTap: () => nav.go(NavDestination.settingsAbout),
                                ),
                              ],
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
          if (!collapsed) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: const _RailMusicMini(),
            ),
            const SizedBox(height: 10),
            Text('v${AppConstants.version}', style: p.captionStyle),
          ],
        ],
      ),
    );
  }
}

class _RailMusicMini extends StatelessWidget {
  const _RailMusicMini();

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicService>();
    final track = music.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final total = music.duration.inMilliseconds <= 0 ? 1.0 : music.duration.inMilliseconds.toDouble();
    final position = music.position.inMilliseconds.clamp(0, total.toInt()).toDouble();
    final artwork = track.artworkPath;
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.accent.withValues(alpha: .3)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blown-up artwork as a soft backdrop; gradient when absent.
              if (artwork != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Image.file(File(artwork), fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.accent.withValues(alpha: .25), p.accent2.withValues(alpha: .15)],
                    ),
                  ),
                ),
              Container(color: p.background.withValues(alpha: .72)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _RailArtwork(path: artwork, size: 42),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(track.title.trim().isEmpty ? s.t('musicUntitled') : track.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800, fontSize: 12)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(track.artist.trim().isEmpty ? s.t('musicUnknownArtist') : track.artist,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: p.captionStyle),
                                  ),
                                  const SizedBox(width: 6),
                                  MusicVisualizer(active: music.isPlaying, color: p.accent, height: 14, barCount: 5),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Visible progress with timestamps on both sides.
                    Row(
                      children: [
                        Text(_railMusicDuration(music.position), style: p.captionStyle.copyWith(fontSize: 8)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            ),
                            child: Slider(
                              value: position,
                              max: total,
                              onChanged: (value) => music.seek(Duration(milliseconds: value.round())),
                            ),
                          ),
                        ),
                        Text(_railMusicDuration(music.duration), style: p.captionStyle.copyWith(fontSize: 8)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Pressable(onTap: music.previous, child: const Icon(Icons.skip_previous_rounded, size: 20)),
                        const SizedBox(width: 6),
                        _Pressable(
                          onTap: music.toggle,
                          child: Icon(music.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                              color: p.accent, size: 30),
                        ),
                        const SizedBox(width: 6),
                        _Pressable(onTap: music.next, child: const Icon(Icons.skip_next_rounded, size: 20)),
                        const SizedBox(width: 10),
                        _Pressable(onTap: music.stop, child: Icon(Icons.stop_rounded, size: 16, color: p.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buttons must feel like buttons: a quick scale dip on press.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.86 : 1,
        duration: const Duration(milliseconds: 90),
        child: Padding(padding: const EdgeInsets.all(4), child: widget.child),
      ),
    );
  }
}

class _RailArtwork extends StatelessWidget {
  const _RailArtwork({required this.path, required this.size});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [p.accent.withValues(alpha: .3), p.accent2.withValues(alpha: .22)]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.music_note_rounded, color: p.accent, size: size * .45),
    );
    final file = path;
    if (file == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(File(file), width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback),
    );
  }
}

String _railMusicDuration(Duration value) => '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

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
    final vpnRunning = context.watch<VpnProvider>().status == VpnStatus.connected;
    final zapretRunning = context.watch<ZapretService>().isRunning;
    final tgRunning = context.watch<TgWsProxyService>().running;
    final processRunning = switch (spec.destination) {
      NavDestination.home => vpnRunning,
      NavDestination.zapret => zapretRunning,
      NavDestination.telegramProxy => tgRunning,
      _ => false,
    };
    final dot = processRunning ? Container(width: 7, height: 7, decoration: BoxDecoration(color: p.success, shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.success.withValues(alpha: .55), blurRadius: 6)])) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: spec.label,
        waitDuration: const Duration(milliseconds: 800),
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
                ? Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(selected ? spec.icon : spec.outlined, size: 22, color: color),
                        if (dot != null) Positioned(top: -2, right: -5, child: dot),
                      ],
                    ),
                  )
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
                      if (dot != null) ...[const SizedBox(width: 7), dot],
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
