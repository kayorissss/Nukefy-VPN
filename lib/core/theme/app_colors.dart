import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0D0D0D);
  static const Color backgroundSecondary = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFF242424);
  static const Color border = Color(0xFF2E2E2E);
  static const Color cyan = Color(0xFF00F0FF);
  static const Color violet = Color(0xFF7B61FF);
  static const Color success = Color(0xFF00FF88);
  static const Color error = Color(0xFFFF3B5C);
  static const Color warning = Color(0xFFFFB800);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textDisabled = Color(0xFF4A4A4A);
  static const Color iconTop = Color(0xFF0A0A0A);
  static const Color iconBottom = Color(0xFF1A1A1A);

  static const Color lightBackground = Color(0xFFF4F6F8);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFEEF1F4);
  static const Color lightBorder = Color(0xFFD8DEE6);
  static const Color lightText = Color(0xFF121417);
  static const Color lightTextSecondary = Color(0xFF5C6570);

  static Color pingColor(int? ms) {
    if (ms == null) return textSecondary;
    if (ms < 0) return textDisabled;
    if (ms < 80) return success;
    if (ms <= 150) return warning;
    return error;
  }
}
