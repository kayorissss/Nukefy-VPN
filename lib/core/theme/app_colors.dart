import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0B0E13);
  static const Color backgroundSecondary = Color(0xFF12161D);
  static const Color surface = Color(0xFF1A1F28);
  static const Color border = Color(0xFF242B36);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color violet = Color(0xFF7B61FF);
  static const Color success = Color(0xFF2EE59D);
  static const Color error = Color(0xFFFF4D6D);
  static const Color warning = Color(0xFFFFB547);
  static const Color textPrimary = Color(0xFFF3F6FA);
  static const Color textSecondary = Color(0xFF8B95A5);
  static const Color textDisabled = Color(0xFF4F5866);
  static const Color iconTop = Color(0xFF0B0E13);
  static const Color iconBottom = Color(0xFF161B24);

  static const Color lightBackground = Color(0xFFF2F4F8);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFE9EDF3);
  static const Color lightBorder = Color(0xFFD9DFE8);
  static const Color lightText = Color(0xFF0F141B);
  static const Color lightTextSecondary = Color(0xFF5B6675);
  static const Color lightCyan = Color(0xFF0097A7);
  static const Color lightViolet = Color(0xFF5B45D6);
  static const Color lightSuccess = Color(0xFF0E9F6E);

  static Color pingColor(int? ms) {
    if (ms == null) return textSecondary;
    if (ms < 0) return textDisabled;
    if (ms < 80) return success;
    if (ms <= 150) return warning;
    return error;
  }
}

/// Theme-aware palette. Use `context.palette` instead of raw [AppColors]
/// inside widgets so the light theme gets proper contrast.
class NukefyPalette extends ThemeExtension<NukefyPalette> {
  const NukefyPalette({
    required this.background,
    required this.card,
    required this.surface,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textDisabled,
    required this.accent,
    required this.accent2,
    required this.success,
    required this.isDark,
  });

  final Color background;
  final Color card;
  final Color surface;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textDisabled;
  final Color accent;
  final Color accent2;
  final Color success;
  final bool isDark;

  static const dark = NukefyPalette(
    background: AppColors.background,
    card: AppColors.backgroundSecondary,
    surface: AppColors.surface,
    border: AppColors.border,
    text: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textDisabled: AppColors.textDisabled,
    accent: AppColors.cyan,
    accent2: AppColors.violet,
    success: AppColors.success,
    isDark: true,
  );

  static const light = NukefyPalette(
    background: AppColors.lightBackground,
    card: AppColors.lightCard,
    surface: AppColors.lightSurface,
    border: AppColors.lightBorder,
    text: AppColors.lightText,
    textSecondary: AppColors.lightTextSecondary,
    textDisabled: Color(0xFFA3ACB9),
    accent: AppColors.lightCyan,
    accent2: AppColors.lightViolet,
    success: AppColors.lightSuccess,
    isDark: false,
  );

  Color pingColor(int? ms) {
    if (ms == null) return textSecondary;
    if (ms < 0) return textDisabled;
    if (ms < 80) return success;
    if (ms <= 150) return AppColors.warning;
    return AppColors.error;
  }

  @override
  NukefyPalette copyWith() => this;

  @override
  NukefyPalette lerp(ThemeExtension<NukefyPalette>? other, double t) =>
      t < 0.5 ? this : (other as NukefyPalette? ?? this);
}

extension NukefyPaletteContext on BuildContext {
  NukefyPalette get palette =>
      Theme.of(this).extension<NukefyPalette>() ?? NukefyPalette.dark;
}
