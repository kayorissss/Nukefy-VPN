import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class SidebarItem {
  const SidebarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Desktop navigation rail. No logo/header: the first item (Home) starts
/// at the very top and is taller than the rest. The rail can be collapsed
/// with the button or by dragging its right edge; both states share the
/// same visual language (icon tile + selection stripe).
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.width,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onResize,
    required this.onToggleCollapse,
    required this.autoSetupLabel,
    required this.addonsLabel,
    required this.onAutoSetup,
    required this.onAddons,
    required this.collapseLabel,
    required this.expandLabel,
  });

  final double width;
  final List<SidebarItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<double> onResize;
  final VoidCallback onToggleCollapse;
  final String autoSetupLabel;
  final String addonsLabel;
  final VoidCallback onAutoSetup;
  final VoidCallback onAddons;
  final String collapseLabel;
  final String expandLabel;

  bool get _collapsed => width < 110;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.55),
            border: Border(right: BorderSide(color: border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              for (var i = 0; i < items.length; i++)
                _SidebarTile(
                  icon: items[i].icon,
                  label: items[i].label,
                  selected: selected == i,
                  collapsed: _collapsed,
                  tall: i == 0,
                  onTap: () => onSelect(i),
                ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _collapsed ? 10 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionButton(
                      icon: Icons.auto_fix_high_rounded,
                      label: autoSetupLabel,
                      collapsed: _collapsed,
                      filled: true,
                      onTap: onAutoSetup,
                    ),
                    const SizedBox(height: 8),
                    _ActionButton(
                      icon: Icons.extension_rounded,
                      label: addonsLabel,
                      collapsed: _collapsed,
                      filled: false,
                      onTap: onAddons,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SidebarTile(
                icon: _collapsed
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded,
                label: _collapsed ? expandLabel : collapseLabel,
                selected: false,
                collapsed: _collapsed,
                tall: false,
                onTap: onToggleCollapse,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        // Drag handle: grab and move left/right to resize the menu.
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) =>
                onResize(width + details.delta.dx),
            onDoubleTap: onToggleCollapse,
            child: SizedBox(
              width: 8,
              child: Center(
                child: Container(
                  width: 2,
                  height: 44,
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.tall,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final bool tall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = selected ? onSurface : AppColors.textSecondary;
    final height = tall ? 58.0 : 48.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Material(
          color: selected
              ? onSurface.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  // Selection stripe, present in both rail states.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    height: selected ? height * 0.52 : 0,
                    decoration: BoxDecoration(
                      color: onSurface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(width: collapsed ? 0 : 8),
                  Expanded(
                    child: collapsed
                        ? Center(child: Icon(icon, size: 22, color: color))
                        : Row(
                            children: [
                              Icon(icon, size: 21, color: color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyRegular.copyWith(
                                    color: color,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: tall ? 15 : 14,
                                  ),
                                ),
                              ),
                            ],
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final background =
        filled ? onSurface : onSurface.withValues(alpha: 0.06);
    final foreground =
        filled ? Theme.of(context).colorScheme.surface : onSurface;
    return Tooltip(
      message: collapsed ? label : '',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: onSurface.withValues(alpha: 0.22),
                    ),
                  ),
            child: collapsed
                ? Center(child: Icon(icon, size: 20, color: foreground))
                : Row(
                    children: [
                      Icon(icon, size: 20, color: foreground),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyRegular.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
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
