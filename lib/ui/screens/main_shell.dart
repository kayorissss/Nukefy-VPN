import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_background.dart';
import 'home_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final index = context.watch<NavProvider>().index;
    final s = context.watch<SettingsProvider>().strings;
    final pages = const [
      HomeScreen(),
      ServersScreen(),
      StatsScreen(),
      SettingsScreen(),
    ];
    return NukefyBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                _Tab(icon: Icons.home_rounded, label: s.t('home'), selected: index == 0, onTap: () => context.read<NavProvider>().setIndex(0)),
                _Tab(icon: Icons.public_rounded, label: s.t('servers'), selected: index == 1, onTap: () => context.read<NavProvider>().setIndex(1)),
                _Tab(icon: Icons.query_stats_rounded, label: s.t('stats'), selected: index == 2, onTap: () => context.read<NavProvider>().setIndex(2)),
                _Tab(icon: Icons.settings_rounded, label: s.t('settings'), selected: index == 3, onTap: () => context.read<NavProvider>().setIndex(3)),
              ],
            ),
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
    final color = selected ? AppColors.cyan : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.bodySecondary.copyWith(color: color, fontSize: 11)),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 14 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: AppColors.cyan.withValues(alpha: 0.7), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
