import 'package:flutter/material.dart';

/// Display face used for headings, numerals and wordmarks.
const kDisplay = 'Sora';

/// "Aurora" palette: a near-black void lit by cyan, violet and magenta.
class AppColors {
  static const bg = Color(0xFF04040A);
  static const surface = Color(0xFF0F0F1A);
  static const surface2 = Color(0xFF181829);
  static const outline = Color(0x1FFFFFFF);
  static const muted = Color(0xFF9EA1BE);

  // Ember: burgundy, crimson, burnt orange. The default look; Settings offers other dark styles.
  static const ember1 = Color(0xFF7A1232);
  static const ember2 = Color(0xFFA61F2E);
  static const ember3 = Color(0xFFB5531A);
  static const pink = Color(0xFFD0284F); // love / selection accent

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember1, ember2, ember3],
  );

  /// Kept as an alias so the whole app shares one gradient.
  static const dockGradient = gradient;

  /// Sweeps along a ring or progress arc.
  static const List<Color> ring = [ember1, ember2, ember3];

  static Color ringAt(double t) => along(ring, t);

  /// Colour at [t] (0..1) along a list of colours.
  static Color along(List<Color> colors, double t) {
    t = t.clamp(0.0, 1.0) * (colors.length - 1);
    final i = t.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], t - i)!;
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    // Transparent so the animated aurora behind the whole app shows through.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AppColors.surface,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.pink,
      secondary: AppColors.ember3,
      tertiary: AppColors.ember2,
      surface: AppColors.surface,
      onSurface: Colors.white,
    ),
  );
  final body = base.textTheme.apply(
    fontFamily: 'PlusJakartaSans',
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );
  TextStyle? d(TextStyle? s) => s?.copyWith(fontFamily: kDisplay);
  final text = body.copyWith(
    displayLarge: d(body.displayLarge),
    displayMedium: d(body.displayMedium),
    displaySmall: d(body.displaySmall),
    headlineLarge: d(body.headlineLarge),
    headlineMedium: d(body.headlineMedium),
    headlineSmall: d(body.headlineSmall),
    titleLarge: d(body.titleLarge),
  );
  return base.copyWith(
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: AppColors.outline,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: AppColors.ember2.withValues(alpha: 0.28),
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: const IconThemeData(color: AppColors.muted),
      selectedLabelTextStyle: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
      unselectedLabelTextStyle: text.labelSmall?.copyWith(color: AppColors.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      hintStyle: const TextStyle(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.ember2, width: 1.4)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      selectedColor: AppColors.ember2.withValues(alpha: 0.3),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: text.labelLarge,
    ),
  );
}
