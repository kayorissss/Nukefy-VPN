import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography.
///
/// Display styles (Unbounded) are used for headings, tabs, buttons and
/// numbers; body styles (Montserrat) for regular text. Primary styles carry
/// no colour so they inherit the theme's text colour and stay readable in
/// both the dark and the light theme.
class AppTextStyles {
  static const String display = 'Unbounded';
  static const String body = 'Montserrat';
  static const String mono = 'JetBrainsMono';

  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.2,
    letterSpacing: -0.2,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    height: 1.25,
  );

  static const TextStyle section = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.6,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    letterSpacing: 0.2,
  );

  static const TextStyle tab = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 9.5,
    letterSpacing: 1.1,
  );

  static const TextStyle bodyRegular = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w500,
    fontSize: 14.5,
    height: 1.35,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  static const TextStyle monoValue = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 13,
  );

  static const TextStyle number = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle metric = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 28,
    height: 1.1,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle metricCaption = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w600,
    fontSize: 10.5,
    letterSpacing: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle status = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    letterSpacing: 2.4,
    color: AppColors.textSecondary,
  );
}
