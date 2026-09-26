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
  NukefyPalette copyWith({Color? accent, Color? accent2}) => NukefyPalette(
        background: background,
        card: card,
        surface: surface,
        border: border,
        text: text,
        textSecondary: textSecondary,
        textDisabled: textDisabled,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        success: success,
        isDark: isDark,
      );

  /// Palette with one of the user-selectable accent pairs applied.
  NukefyPalette withAccent(String key) {
    final pair = AccentThemes.of(key);
    if (pair == null) return this;
    return copyWith(accent: isDark ? pair.dark : pair.light, accent2: pair.secondary);
  }

  @override
  NukefyPalette lerp(ThemeExtension<NukefyPalette>? other, double t) =>
      t < 0.5 ? this : (other as NukefyPalette? ?? this);
}

extension NukefyPaletteContext on BuildContext {
  NukefyPalette get palette =>
      Theme.of(this).extension<NukefyPalette>() ?? NukefyPalette.dark;
}

class AccentPair {
  const AccentPair(this.dark, this.light, this.secondary);
  final Color dark;
  final Color light;
  final Color secondary;
}

/// User-selectable accent colours (Settings → Accent colour).
class AccentThemes {
  static const Map<String, AccentPair> all = {
    'cyan': AccentPair(AppColors.cyan, AppColors.lightCyan, AppColors.violet),
    'violet': AccentPair(Color(0xFFA78BFA), Color(0xFF6D4AFF), Color(0xFF22D3EE)),
    'crimson': AccentPair(Color(0xFFFF5C7A), Color(0xFFD9224A), Color(0xFFFF9F43)),
    'pink': AccentPair(Color(0xFFFF7AC6), Color(0xFFDB2777), Color(0xFF8B5CF6)),
    'blue': AccentPair(Color(0xFF60A5FA), Color(0xFF2563EB), Color(0xFF22D3EE)),
    'emerald': AccentPair(Color(0xFF34D399), Color(0xFF059669), Color(0xFF38BDF8)),
    'amber': AccentPair(Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFFF97316)),
  };

  static AccentPair? of(String key) => all[key];
}
