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
        color: p.card.withValues(alpha: .82),
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
    this.below,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Extra content rendered under the row, indented to the title column, so
  /// dropdowns and choosers line up with every other card instead of being
  /// hand-padded at random offsets.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A dropdown or a long action label must not steal the title's width
        // on a phone. The old ListTile left a 40–60 px text column, which is
        // why Russian words were rendered one character per line.
        // Wide trailing controls (button pairs, dropdowns) move under the title
        // when the card is narrow, so nothing ever clips on a phone.
        final stacked = constraints.maxWidth < 400 && trailing != null;
        final lead = Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: p.accent, size: 19),
        );
        // Descriptions live behind a "?" hint so tiles stay one clean line;
        // hovering the icon reveals the full explanation.
        final copy = Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                HintBadge(message: subtitle!),
              ],
            ],
          ),
        );
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            lead,
            const SizedBox(width: 12),
            copy,
            if (!stacked) ...[
              const SizedBox(width: 8),
              trailing ?? (onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_right_rounded, color: p.textSecondary)),
            ],
          ],
        );
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stacked) ...[
                    row,
                    const SizedBox(height: 8),
                    Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
                  ] else
                    row,
                  if (below != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(50, 6, 0, 2),
                      child: below!,
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
    this.subtitleAsHint = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Static explanations go behind the "?" badge so every switch row is one
  /// clean line. Set to false when the subtitle is live state the user must
  /// see at a glance (ports, addresses, counters).
  final bool subtitleAsHint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, _) {
        final lead = icon == null
            ? null
            : Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: p.accent, size: 19),
              );
        final text = Expanded(
          child: subtitle != null && subtitleAsHint
              ? Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    HintBadge(message: subtitle!),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                    ],
                  ],
                ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 12)],
              text,
              const SizedBox(width: 8),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        );
      },
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    final buttonWidth = compact ? 190.0 : 240.0;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 5)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: p.border))),
      ),
      menuChildren: [
        for (final entry in items.entries)
          MenuItemButton(
            onPressed: () => onChanged(entry.key),
            child: SizedBox(
              width: compact ? 230 : 290,
              child: Row(
                children: [
                  Expanded(child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (entry.key == value) Icon(Icons.check_rounded, size: 18, color: p.accent),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: SizedBox(
          width: buttonWidth,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: controller.isOpen ? p.accent : p.border, width: controller.isOpen ? 1.3 : 1),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  items[value] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(turns: controller.isOpen ? .5 : 0, duration: const Duration(milliseconds: 180), child: Icon(Icons.expand_more_rounded, size: 18, color: p.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small "?" badge that hides a full description behind a tooltip so tiles
/// stay one clean line. Shared by [SettingsTile] and [SwitchTile].
class HintBadge extends StatelessWidget {
  const HintBadge({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 300),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: ShapeDecoration(
        color: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.border)),
      ),
      textStyle: AppTextStyles.bodySecondary.copyWith(color: p.text),
      child: Icon(Icons.help_outline_rounded, size: 15, color: p.textSecondary),
    );
  }
}

/// Mini caption that splits a long card into named groups, so a pile of
/// switches and sliders stops looking like an endless wall of toggles.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel({super.key, required this.label, this.first = false});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, first ? 4 : 14, 2, 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.section.copyWith(color: p.accent.withValues(alpha: .85), fontSize: 10.5, letterSpacing: .9),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: p.border)),
        ],
      ),
    );
  }
}

/// Uniform action button for card rows: one geometry, two weights, so the
/// right edge of every card reads as a single column of controls.
class NukefyActionButton extends StatelessWidget {
  const NukefyActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label, style: AppTextStyles.bodyRegular.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: filled ? Colors.transparent : p.border));
    final padding = const EdgeInsets.symmetric(horizontal: 14);
    return SizedBox(
      height: 36,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(padding: padding, shape: shape, visualDensity: VisualDensity.compact),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(padding: padding, shape: shape, visualDensity: VisualDensity.compact),
              child: child,
            ),
    );
  }
}
