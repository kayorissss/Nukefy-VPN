import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Country marker that renders identically on every platform (emoji flags
/// fall back to plain letters on Windows). A rounded tile with the ISO code
/// tinted by a stable per-country hue.
class CountryBadge extends StatelessWidget {
  const CountryBadge({super.key, required this.code, this.size = 40});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = (code ?? '').toUpperCase();
    final valid = text.length == 2;
    final hue = valid ? ((text.codeUnitAt(0) * 31 + text.codeUnitAt(1) * 17) % 360).toDouble() : 190.0;
    final c1 = HSLColor.fromAHSL(1, hue, 0.75, p.isDark ? 0.62 : 0.42).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.75, p.isDark ? 0.5 : 0.34).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1.withValues(alpha: 0.22), c2.withValues(alpha: 0.12)],
        ),
        border: Border.all(color: c1.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: valid
          ? Text(
              text,
              style: AppTextStyles.number.copyWith(
                fontSize: size * 0.3,
                color: c1,
                letterSpacing: 0.5,
              ),
            )
          : Icon(Icons.public_rounded, size: size * 0.5, color: c1),
    );
  }
}
