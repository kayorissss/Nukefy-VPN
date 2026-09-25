import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.iconTop, AppColors.iconBottom],
        ),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45)),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.28),
                  blurRadius: size * 0.45,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/icons/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: AppColors.cyan,
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
