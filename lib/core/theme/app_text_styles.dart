import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTextStyles {
  static const String display = 'SpaceGrotesk';
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono';

  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.15,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: AppColors.textPrimary,
  );

  static const TextStyle section = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    letterSpacing: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodyRegular = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w400,
    fontSize: 14.5,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  static const TextStyle monoValue = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: AppColors.textPrimary,
  );

  static const TextStyle status = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    letterSpacing: 2.2,
    color: AppColors.textSecondary,
  );
}
