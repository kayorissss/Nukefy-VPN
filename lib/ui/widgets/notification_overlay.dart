import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/nav_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';

IconData _kindIcon(AppNotificationKind kind) {
  return switch (kind) {
    AppNotificationKind.success => Icons.check_circle_rounded,
    AppNotificationKind.error => Icons.error_rounded,
    AppNotificationKind.info => Icons.info_rounded,
  };
}

Color _kindColor(AppNotificationKind kind) {
  return switch (kind) {
    AppNotificationKind.success => AppColors.success,
    AppNotificationKind.error => AppColors.error,
    AppNotificationKind.info => AppColors.cyan,
  };
}

/// Floating cards in the top-right corner. They can be closed, and every
/// one of them stays readable later in the history behind the bell.
class NotificationOverlay extends StatelessWidget {
  const NotificationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final center = context.watch<NotificationsProvider>();
    if (center.visible.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      right: 12,
      child: SizedBox(
        width: 330,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in center.visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ToastCard(item: item),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final center = context.read<NotificationsProvider>();
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          center.markRead(item.id);
          center.dismiss(item.id);
          final route = item.routeIndex;
          if (route != null) context.read<NavProvider>().setIndex(route);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_kindIcon(item.kind), color: _kindColor(item.kind), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySecondary,
                    ),
                    if (item.actionLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.actionLabel!,
                        style: AppTextStyles.bodySecondary.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => center.dismiss(item.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bell button with an unread badge; opens the full history.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final center = context.watch<NotificationsProvider>();
    final s = context.watch<SettingsProvider>().strings;
    return IconButton(
      tooltip: s.t('notifTitle'),
      onPressed: () => _openHistory(context),
      icon: Badge(
        isLabelVisible: center.unread > 0,
        label: Text('${center.unread}'),
        child: const Icon(Icons.notifications_rounded),
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    final s = context.read<SettingsProvider>().strings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final center = context.watch<NotificationsProvider>();
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                  child: Row(
                    children: [
                      Text(s.t('notifTitle'), style: AppTextStyles.headline),
                      const Spacer(),
                      if (center.items.isNotEmpty)
                        TextButton(
                          onPressed: center.clearAll,
                          child: Text(s.t('notifClear')),
                        ),
                    ],
                  ),
                ),
                if (center.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.t('notifEmpty'), style: AppTextStyles.bodySecondary),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in center.items)
                          ListTile(
                            leading: Icon(
                              _kindIcon(item.kind),
                              color: _kindColor(item.kind),
                            ),
                            title: Text(
                              item.title,
                              style: AppTextStyles.bodyRegular.copyWith(
                                fontWeight: item.read ? FontWeight.w400 : FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${FormatUtils.clock(item.time)} · ${item.body}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySecondary,
                            ),
                            onTap: () {
                              center.markRead(item.id);
                              Navigator.pop(context);
                              final route = item.routeIndex;
                              if (route != null) {
                                context.read<NavProvider>().setIndex(route);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (context.mounted) context.read<NotificationsProvider>().markAllRead();
  }
}
