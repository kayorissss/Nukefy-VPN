import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The app mark. Plain image with a soft glow — no frames.
class NukefyLogo extends StatelessWidget {
  const NukefyLogo({super.key, this.size = 36, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.18),
                  blurRadius: size * 0.6,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/icons/app_icon.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppColors.background,
          child: Center(
            child: Text(
              'N',
              style: TextStyle(
                color: AppColors.cyan,
                fontFamily: 'Unbounded',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
