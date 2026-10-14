import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/nav_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../dialogs/auto_setup_dialog.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/sidebar.dart';
import 'connections_screen.dart';
import 'extras_screen.dart';
import 'home_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  double _sidebarWidth = 232;
  VpnStatus? _lastStatus;
  String? _lastError;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vpn = context.read<VpnProvider>();
    vpn.removeListener(_onVpnChanged);
    vpn.addListener(_onVpnChanged);
  }

  @override
  void dispose() {
    try {
      context.read<VpnProvider>().removeListener(_onVpnChanged);
    } catch (_) {}
    super.dispose();
  }

  /// Errors and successful connections become corner notifications instead
  /// of red text glued under the power button.
  void _onVpnChanged() {
    if (!mounted) return;
    final vpn = context.read<VpnProvider>();
    final s = context.read<SettingsProvider>().strings;
    final center = context.read<NotificationsProvider>();
    if (vpn.status == VpnStatus.error && vpn.errorMessage != _lastError) {
      _lastError = vpn.errorMessage;
      final coreIssue = vpn.errorMessage == 'XRAY_MISSING' ||
          vpn.errorMessage == 'CORE_MISSING';
      center.push(
        title: s.t('connectionError'),
        body: humanVpnError(s, vpn.errorMessage),
        kind: AppNotificationKind.error,
        routeIndex: coreIssue ? NavTabs.settings : NavTabs.servers,
        actionLabel: coreIssue ? s.t('openSettings') : s.t('details'),
      );
    }
    if (vpn.status == VpnStatus.connected && _lastStatus != VpnStatus.connected) {
      final server = vpn.activeServer;
      center.push(
        title: s.t('connected'),
        body: server == null ? '' : '${s.t('connectedTo')} ${server.name}',
        kind: AppNotificationKind.success,
        routeIndex: NavTabs.analysis,
        actionLabel: s.t('analysis'),
      );
    }
    _lastStatus = vpn.status;
  }

  void _openExtras() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExtrasScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = context.watch<NavProvider>().index;
    final s = context.watch<SettingsProvider>().strings;
    final pages = const [
      HomeScreen(),
      ServersScreen(),
      ConnectionsScreen(),
      StatsScreen(),
      SettingsScreen(),
    ];
    final titles = [
      s.t('home'),
      s.t('servers'),
      s.t('analysis'),
      s.t('stats'),
      s.t('settings'),
    ];
    return NukefyBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = _isDesktop && constraints.maxWidth >= 860;
          if (desktop) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Column(
                    children: [
                      _TitleBar(title: titles[index]),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSidebar(
                              width: _sidebarWidth,
                              selected: index,
                              onSelect: (i) =>
                                  context.read<NavProvider>().setIndex(i),
                              onResize: (w) => setState(() =>
                                  _sidebarWidth = w.clamp(68, 288)),
                              onToggleCollapse: () => setState(() =>
                                  _sidebarWidth =
                                      _sidebarWidth < 110 ? 232 : 76),
                              items: [
                                SidebarItem(icon: Icons.home_rounded, label: s.t('home')),
                                SidebarItem(icon: Icons.public_rounded, label: s.t('servers')),
                                SidebarItem(icon: Icons.hub_rounded, label: s.t('analysis')),
                                SidebarItem(icon: Icons.query_stats_rounded, label: s.t('stats')),
                                SidebarItem(icon: Icons.settings_rounded, label: s.t('settings')),
                              ],
                              autoSetupLabel: s.t('autoSetup'),
                              addonsLabel: s.t('addons'),
                              onAutoSetup: () => showAutoSetupDialog(context),
                              onAddons: _openExtras,
                              collapseLabel: s.t('menuCollapse'),
                              expandLabel: s.t('menuExpand'),
                            ),
                            Expanded(
                              child: IndexedStack(index: index, children: pages),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const NotificationOverlay(),
                ],
              ),
            );
          }
          // Mobile / narrow window: bottom navigation, compact labels.
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                IndexedStack(index: index, children: pages),
                const NotificationOverlay(),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    _Tab(icon: Icons.home_rounded, label: s.t('home'), selected: index == 0, onTap: () => context.read<NavProvider>().setIndex(0)),
                    _Tab(icon: Icons.public_rounded, label: s.t('servers'), selected: index == 1, onTap: () => context.read<NavProvider>().setIndex(1)),
                    _Tab(icon: Icons.hub_rounded, label: s.t('analysis'), selected: index == 2, onTap: () => context.read<NavProvider>().setIndex(2)),
                    _Tab(icon: Icons.query_stats_rounded, label: s.t('stats'), selected: index == 3, onTap: () => context.read<NavProvider>().setIndex(3)),
                    _Tab(icon: Icons.settings_rounded, label: s.t('settings'), selected: index == 4, onTap: () => context.read<NavProvider>().setIndex(4)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slim custom title bar: section name on the left, notifications and the
/// window buttons on the right — minimize (the stripe), maximize, close.
class _TitleBar extends StatefulWidget {
  const _TitleBar({required this.title});

  final String title;

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> {
  bool _maximized = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: AppTextStyles.headline.copyWith(fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
          const NotificationBell(),
          const SizedBox(width: 4),
          // Minimize — the stripe next to the close button.
          _WindowButton(
            tooltip: s.t('hideWindow'),
            onTap: () => windowManager.minimize(),
            child: Container(width: 12, height: 2, color: AppColors.textSecondary),
          ),
          _WindowButton(
            tooltip: _maximized ? s.t('restoreWindow') : s.t('maxWindow'),
            onTap: () async {
              if (_maximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
              await _refresh();
            },
            child: Icon(
              _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              size: 13,
              color: AppColors.textSecondary,
            ),
          ),
          _WindowButton(
            tooltip: s.t('closeWindow'),
            danger: true,
            onTap: () => windowManager.close(),
            child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.danger = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: danger
              ? AppColors.error.withValues(alpha: 0.85)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 32,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = selected ? onSurface : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySecondary.copyWith(color: color, fontSize: 10),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 14 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: onSurface,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
