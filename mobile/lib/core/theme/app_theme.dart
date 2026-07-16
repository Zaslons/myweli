import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';
import 'text_styles.dart';

class AppTheme {
  // Spacing System — an 8pt grid with one sanctioned half-step (SYSTEM.md §5).
  // Nothing else is legal: 10, 14, 18, 20 are not spacing values.
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;

  /// The half-step. 12px appeared 76× as a raw literal because 8 was too tight
  /// and 16 too loose for dense UI — naming it makes that a legal choice instead
  /// of a violation (SYSTEM.md §5). Chip padding, dense list gaps, title↔subtitle.
  static const double spacingSM = 12.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;
  static const double spacingXXXL = 64.0;

  // Border Radius (SYSTEM.md §6)
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXL = 16.0;
  static const double radiusXXL = 24.0;

  /// Fully-rounded. `999` is a *shape* (a pill), not a number — chips, avatars,
  /// badges, FABs, segmented controls (SYSTEM.md §6). It was hand-written 21×.
  static const double radiusPill = 999.0;

  // Icon size — five is enough (SYSTEM.md §7). An icon's *size* and its *tap
  // target* are different things: `iconM` is 24px of glyph inside a ≥48px touch
  // target (§13.2) — never grow the glyph to enlarge the target, grow the target.
  static const double iconXS = 16.0; // inline w/ bodySmall/labelMedium; chips
  static const double iconS = 20.0; // inline with text — the common case
  static const double iconM = 24.0; // default action icon (AppBar, IconButton)
  static const double iconL = 32.0; // feature / avatar-scale glyphs
  static const double iconXL = 64.0; // the empty-state illustration glyph

  /// The height bound a **scroller** must hand a box that mixes constant chrome
  /// with text, when the OS text scale moves (SYSTEM.md §13.3).
  ///
  /// A horizontal `ListView` demands a bounded cross-axis, so "let it be
  /// intrinsic" is not available — the bound has to be computed. Two ways to get
  /// that wrong, both found in review:
  ///
  /// * **Scaling the whole bound.** A 280px provider card is 180 image + 32
  ///   padding + 68 text; only the 68 tracks the font. `scale(280)` gives 560 at
  ///   200% for 332 of content — 41% dead space, and it drags the *image's* share
  ///   up with it. So scale [text] alone and add [constant] back untouched.
  /// * **Letting it shrink.** Rows are `max(icon, line)` and icons do *not*
  ///   scale, so a text block that measures 68 at 1× still needs 60.4 at 0.85 —
  ///   not `68 × 0.85 = 57.8`. A proportional bound under-provisions at *small*
  ///   scales, which is a real clip and can trip a downstream height threshold.
  ///   Hence the `max`: the 1× baseline is a **floor**, and this only ever grows.
  ///
  /// [constant] is the chrome that must not move (image/avatar height, padding);
  /// [text] is the text block's own height at 1×. Pin both with a test that
  /// asserts the bound still covers the real content — a measured constant
  /// silently rots the day someone adds a row (see `test/a11y/text_scale_test.dart`).
  static double textScaledBound(
    BuildContext context, {
    required double constant,
    required double text,
  }) =>
      constant + math.max(text, MediaQuery.textScalerOf(context).scale(text));

  // Elevation/Shadows
  static List<BoxShadow> get elevation1 => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get elevation2 => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get elevation3 => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get elevation4 => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 15,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
      ];

  /// The app's theme. Production passes no [fontFamily], so text renders in the
  /// platform's system font (SF Pro on iOS, Roboto on Android) — unchanged.
  static ThemeData get lightTheme => themeData();

  /// [fontFamily] pins the typeface for every text style the theme sets.
  ///
  /// `ThemeData(fontFamily:)` alone would NOT be enough: the styles below are
  /// passed explicitly (the AppBar title, the three button labels, the input
  /// label/hint, the nav labels), and an explicit style's null family wins over
  /// the theme's. So the family is applied to each of them here, in one place.
  ///
  /// Only the golden tests pass it today (they pin Roboto so the rendered bytes
  /// are reproducible — see test/support/golden.dart). It is also the seam the
  /// brand font will use when it lands (docs/design/SYSTEM.md §22).
  static ThemeData themeData({String? fontFamily}) {
    TextStyle f(TextStyle style) =>
        fontFamily == null ? style : style.copyWith(fontFamily: fontFamily);

    return ThemeData(
      useMaterial3: true,
      // The FULL scheme (SYSTEM.md §21 row 9). We used to set 8 slots; the other
      // ~22 fell back to Material 3's PURPLE baseline, and since nothing reads a
      // slot by name, that purple leaked implicitly through every unthemed
      // component (pickers, snackbars, chips, tab labels, icons, sheets…).
      // Filling them all — monochrome, token-derived — de-purples the whole app
      // at once, present components and future ones alike.
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.secondary,
        primaryContainer: AppColors.surfaceVariant,
        onPrimaryContainer: AppColors.textPrimary,
        secondary: AppColors.primary,
        onSecondary: AppColors.secondary,
        secondaryContainer: AppColors.surfaceVariant, // was #E8DEF8 purple
        onSecondaryContainer: AppColors.textPrimary,
        tertiary: AppColors.primary,
        onTertiary: AppColors.secondary,
        tertiaryContainer: AppColors.surfaceVariant,
        onTertiaryContainer: AppColors.textPrimary,
        error: AppColors.error,
        onError: AppColors.secondary,
        errorContainer: AppColors.secondaryVariant,
        onErrorContainer: AppColors.error,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        // The single worst leak: icon/label defaults resolve to onSurfaceVariant.
        onSurfaceVariant: AppColors.textSecondary,
        // The neutral surface ramp (M3 draws menus/sheets/switch tracks from it).
        surfaceDim: AppColors.secondaryVariant,
        surfaceBright: AppColors.secondary,
        surfaceContainerLowest: AppColors.secondary,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.secondaryVariant,
        surfaceContainerHigh: AppColors.secondaryVariant,
        surfaceContainerHighest: AppColors.divider,
        outline: AppColors.borderStrong, // 3.22:1
        outlineVariant: AppColors.border,
        inverseSurface: AppColors.textPrimary, // snackbar bg
        onInverseSurface: AppColors.secondary,
        inversePrimary: AppColors.secondary,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint:
            Colors.transparent, // flat monochrome — no M3 elevation tint
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: const TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        displayMedium: AppTextStyles.displayMedium,
        displaySmall: AppTextStyles.displaySmall,
        headlineLarge: AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        headlineSmall: AppTextStyles.headlineSmall,
        titleLarge: AppTextStyles.titleLarge,
        titleMedium: AppTextStyles.titleMedium,
        titleSmall: AppTextStyles.titleSmall,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelLarge: AppTextStyles.labelLarge,
        labelMedium: AppTextStyles.labelMedium,
        labelSmall: AppTextStyles.labelSmall,
      ).apply(fontFamily: fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: f(
          AppTextStyles.headlineSmall.copyWith(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
          size: 24,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingM,
          vertical: spacingM,
        ),
        // WCAG 1.4.11 (SYSTEM.md §3.3): a field's outline is the ONLY thing that
        // says a field is there, so it is `borderStrong` (3.22:1) — not `border`
        // (1.44:1), which is what every input in the product used to be outlined
        // in, i.e. invisible to a low-vision user. These two lines fix every
        // AppTextField in all three apps, plus the DropdownButtonFormFields that
        // don't override the theme.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        // Disabled controls are exempt from the contrast rule — and SHOULD recede
        // below the enabled state. Without this the disabled field fell through to
        // an untokened Material default; now it is deliberately the soft `border`.
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.borderFocus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: f(
          AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
        ),
        hintStyle: f(
          AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.secondary,
          // Disabled reads as disabled, and legibly (SYSTEM.md §21 row 24): the
          // old #5C5C5C-on-#949495 was 2.21:1. Exempt from WCAG, but this pair
          // is a clearly-inert light grey.
          disabledBackgroundColor: AppColors.surfaceVariant,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 1,
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingM,
          ),
          // Height floor only — a button takes its WIDTH from its container, not
          // a forced `double.infinity` (which became a ~1000px bar on a tablet).
          // AppButton overrides this for its own full-width sizing.
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          textStyle: f(AppTextStyles.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textDisabled,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingM,
          ),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          textStyle: f(AppTextStyles.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textDisabled,
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingS,
          ),
          // 48, not 40 — the WCAG tap-target floor (§13.2). Raises raw
          // TextButtons and AppButton.text alike.
          minimumSize: const Size(0, 48),
          textStyle: f(AppTextStyles.labelLarge),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.secondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.05),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.secondary,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 3,
        selectedLabelStyle: f(AppTextStyles.labelSmall),
        unselectedLabelStyle: f(AppTextStyles.labelSmall),
      ),
      // ---- The component themes (SYSTEM.md §21 row 9) -----------------------
      // Everything below used to render off Material's purple defaults. Only the
      // components the app ACTUALLY renders are themed here; the completed
      // ColorScheme above already keeps the unused ones (radio, segmented,
      // badge, drawer) on-token, so we don't add dead config.

      // Fixes the ~65 bare SnackBars (were dark purple-grey `inverseSurface`),
      // and lets Helpers.showSnackBar drop its hardcoded Colors.black87.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: f(
          AppTextStyles.bodyMedium.copyWith(color: AppColors.secondary),
        ),
        actionTextColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      // Bare chips were filled with #E8DEF8 purple (`secondaryContainer`).
      // The label INVERTS to white on the black selected fill — via a
      // `WidgetStateColor`, not `secondaryLabelStyle` (which M3's RawChip
      // ignores; it resolves `labelStyle.color` per-state instead). This works
      // uniformly for Chip / ChoiceChip / FilterChip — the golden proved that
      // secondaryLabelStyle left FilterChip's selected label dark-on-black.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.surfaceVariant,
        checkmarkColor: AppColors.secondary,
        side: const BorderSide(color: AppColors.borderStrong),
        shape: const StadiumBorder(),
        labelStyle: f(AppTextStyles.labelMedium).copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? AppColors.secondary
                : AppColors.textPrimary,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.secondary
              : AppColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceVariant,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.secondary,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.secondary),
        side: const BorderSide(color: AppColors.borderStrong, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant, // was purple-tinted
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.12),
        valueIndicatorColor: AppColors.textPrimary,
        valueIndicatorTextStyle: f(
          AppTextStyles.labelMedium.copyWith(color: AppColors.secondary),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textTertiary, // was onSurfaceVariant
        labelStyle: f(AppTextStyles.titleSmall),
        unselectedLabelStyle: f(AppTextStyles.titleSmall),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.divider,
      ),
      // The ~30 uncolored IconButtons defaulted to `onSurfaceVariant`.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.secondary,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: f(
          AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
        ),
        contentTextStyle: f(
          AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.secondary,
        modalBackgroundColor: AppColors.secondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXXL)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.secondary,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: f(
          AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.secondary,
        indicatorColor: AppColors.surfaceVariant,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          f(AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary)),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textTertiary,
          ),
        ),
      ),
      // ListTile leading/trailing icons defaulted to `onSurfaceVariant`.
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),
      // No explicit tooltips today, but A4 adds ~26 — themed now so they land
      // on-brand (dark, rounded, white text).
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: f(
          AppTextStyles.bodySmall.copyWith(color: AppColors.secondary),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
      ),
      // The 11 date/time pickers were the worst purple offenders. Most of it
      // now derives from the completed ColorScheme; these pin the header/surface
      // to the flat monochrome brand.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.secondary,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: AppColors.secondary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.secondary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
    );
  }
}
