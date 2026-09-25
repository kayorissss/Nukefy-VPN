import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Settings card with an uppercase Unbounded caption and optional lead text.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.description,
    this.icon,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? description;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: p.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AppTextStyles.section.copyWith(color: p.textSecondary),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: p.accent, size: 19),
      ),
      title: Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
      trailing: trailing ??
          (onTap == null ? null : Icon(Icons.chevron_right_rounded, color: p.textSecondary)),
      onTap: onTap,
    );
  }
}

/// Toggle row used across settings.
class SwitchTile extends StatelessWidget {
  const SwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SwitchListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: icon == null ? 2 : 2),
      secondary: icon == null
          ? null
          : Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: p.accent, size: 19),
            ),
      title: Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Styled dropdown that matches the cards (no underline, rounded menu).
class NukefyDropdown<T> extends StatelessWidget {
  const NukefyDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopupMenuButton<T>(
      initialValue: value,
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final entry in items.entries)
          PopupMenuItem<T>(
            value: entry.key,
            child: Row(
              children: [
                Expanded(child: Text(entry.value)),
                if (entry.key == value) Icon(Icons.check_rounded, size: 18, color: p.accent),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(items[value] ?? '', style: AppTextStyles.bodyRegular.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}
