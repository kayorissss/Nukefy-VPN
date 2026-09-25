import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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

/// Width from which the app switches to the desktop layout: a side rail and
/// content centred with a comfortable maximum width.
const double kDesktopBreakpoint = 840;

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final index = context.watch<NavProvider>().index;
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= kDesktopBreakpoint;

    final tabs = <_TabSpec>[
      _TabSpec(Icons.home_rounded, Icons.home_outlined, s.t('home')),
      _TabSpec(Icons.public_rounded, Icons.public_outlined, s.t('servers')),
      _TabSpec(Icons.radar_rounded, Icons.radar_outlined, s.t('jammers')),
      _TabSpec(Icons.insights_rounded, Icons.insights_outlined, s.t('stats')),
      _TabSpec(Icons.settings_rounded, Icons.settings_outlined, s.t('settings')),
    ];

    const pages = [
      HomeScreen(),
      ServersScreen(),
      JammersScreen(),
      StatsScreen(),
      SettingsScreen(),
    ];

    // IndexedStack keeps every tab alive (jammer results, scroll offsets);
    // _TabFade adds a soft cross-fade on each switch without rebuilding them.
    final body = _TabFade(
      index: index,
      child: IndexedStack(index: index, children: pages),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).appBarTheme.systemOverlayStyle ?? SystemUiOverlayStyle.light,
      child: NukefyBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: desktop
              ? Row(
                  children: [
                    _SideRail(tabs: tabs, index: index),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: body,
                        ),
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
        height: 66,
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(selected ? spec.icon : spec.outlined, color: color, size: 21),
            ),
            const SizedBox(height: 4),
            Text(
              spec.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: AppTextStyles.tab.copyWith(color: color, fontSize: 8.5),
            ),
          ],
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
    return Container(
      width: 220,
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: p.isDark ? 0.9 : 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
            child: Row(
              children: [
                const NukefyLogo(size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.t('appTitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headline.copyWith(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < tabs.length; i++)
            _RailItem(
              spec: tabs[i],
              selected: i == index,
              onTap: () => context.read<NavProvider>().setIndex(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'v2.0.0',
              style: AppTextStyles.metricCaption.copyWith(color: p.textDisabled),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.spec, required this.selected, required this.onTap});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(selected ? spec.icon : spec.outlined, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
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
      ),
    );
  }
}

class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: 0.5 + 0.5 * curve.value,
        child: Transform.translate(offset: Offset(0, (1 - curve.value) * 10), child: child),
      ),
      child: widget.child,
    );
  }
}
