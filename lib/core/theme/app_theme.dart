import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  static ThemeData dark() => _build(NukefyPalette.dark);
  static ThemeData light() => _build(NukefyPalette.light);

  /// Transparent system bars so the app background continues under the
  /// status bar and the gesture bar.
  static SystemUiOverlayStyle overlay(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  static ThemeData _build(NukefyPalette p) {
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: const Color(0xFF041316),
      secondary: p.accent2,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: p.card,
      onSurface: p.text,
      surfaceContainerHighest: p.surface,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.border,
    );

    TextStyle body(double size, FontWeight w, {Color? color, double? height}) =>
        TextStyle(
          fontFamily: AppTextStyles.body,
          fontSize: size,
          fontWeight: w,
          color: color ?? p.text,
          height: height ?? 1.35,
        );
    TextStyle display(double size, FontWeight w, {double? spacing}) => TextStyle(
          fontFamily: AppTextStyles.display,
          fontSize: size,
          fontWeight: w,
          color: p.text,
          height: 1.2,
          letterSpacing: spacing,
        );

    final textTheme = TextTheme(
      displayLarge: display(40, FontWeight.w700, spacing: -0.6),
      displayMedium: display(32, FontWeight.w700, spacing: -0.4),
      displaySmall: display(26, FontWeight.w700, spacing: -0.2),
      headlineLarge: display(22, FontWeight.w700),
      headlineMedium: display(19, FontWeight.w600),
      headlineSmall: display(17, FontWeight.w600),
      titleLarge: display(16, FontWeight.w600),
      titleMedium: body(15, FontWeight.w600),
      titleSmall: body(13.5, FontWeight.w600),
      bodyLarge: body(15, FontWeight.w500),
      bodyMedium: body(14.5, FontWeight.w500),
      bodySmall: body(12.5, FontWeight.w500, color: p.textSecondary),
      labelLarge: display(13, FontWeight.w600, spacing: 0.2),
      labelMedium: display(11.5, FontWeight.w600, spacing: 0.4),
      labelSmall: display(10, FontWeight.w600, spacing: 1.2),
    );

    final rounded16 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      cardColor: p.card,
      fontFamily: AppTextStyles.body,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // No material ink: rectangles were flashing behind rounded controls.
      // Feedback comes from Pressable's scale animation instead.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: p.accent.withValues(alpha: 0.05),
      focusColor: p.accent.withValues(alpha: 0.10),
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textSecondary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: p.text,
        iconTheme: IconThemeData(color: p.text),
        titleTextStyle: display(17, FontWeight.w600),
        systemOverlayStyle: overlay(brightness),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: display(17, FontWeight.w600),
        contentTextStyle: body(14, FontWeight.w500, color: p.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.card,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface,
        contentTextStyle: body(14, FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        textStyle: body(14, FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: body(14, FontWeight.w500),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: p.border),
            ),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: p.border),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: body(14, FontWeight.w500, color: p.textSecondary),
        labelStyle: body(13.5, FontWeight.w500, color: p.textSecondary),
        floatingLabelStyle: body(13, FontWeight.w600, color: p.accent),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: const Color(0xFF041316),
          textStyle: AppTextStyles.button,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: rounded16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: p.surface,
          foregroundColor: p.text,
          textStyle: AppTextStyles.button,
          minimumSize: const Size(0, 48),
          shape: rounded16,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          textStyle: AppTextStyles.button,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: p.border),
          shape: rounded16,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: AppTextStyles.button,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.accent,
        textColor: p.text,
        titleTextStyle: body(14.5, FontWeight.w600),
        subtitleTextStyle: body(12.5, FontWeight.w500, color: p.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFF041316);
          return p.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return p.border;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.surface,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Color(0xFF041316)),
        side: BorderSide(color: p.textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.textSecondary,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accent.withValues(alpha: 0.16),
        labelStyle: body(13, FontWeight.w600),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        textStyle: body(12.5, FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surface,
        circularTrackColor: p.surface,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
