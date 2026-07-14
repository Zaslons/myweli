import 'package:flutter/material.dart';

/// The Myweli colour tokens — docs/design/SYSTEM.md §3.
///
/// Every value here carries its measured contrast ratio against `background`
/// (#F6F7F9 — the worst of our three surfaces) and, critically, **what it is
/// allowed to be used for**. A token that is legal as an icon can be illegal as
/// a label: WCAG sets 4.5:1 for text, 3:1 for icons and control borders, and
/// nothing for decoration. `test/unit/design_contrast_test.dart` asserts all of
/// it — these comments cannot drift from the code without a failing test.
class AppColors {
  // ---- Brand -----------------------------------------------------------------
  // THE TWO BLACKS (SYSTEM.md §1). `primary` is the thing you look AT — button
  // fills, the logo, the focus ring; white on it is 21:1, and its absoluteness is
  // what makes the monochrome read as deliberate. `textPrimary` (below) is the
  // thing you read THROUGH. Text is never `primary`; a fill is never
  // `textPrimary`. Long runs of pure-black glyphs halate; a black fill does not.
  static const Color primary = Color(0xFF000000); // 19.59:1 — brand, never text

  /// The hover/pressed step off [primary] (white on it: 12.63:1).
  /// No mobile caller yet — the web consumes it, and A3's component themes will.
  static const Color primaryHover = Color(0xFF333333);

  static const Color secondary =
      Color(0xFFFFFFFF); // card surface; 21:1 on primary
  static const Color secondaryVariant =
      Color(0xFFF5F5F5); // pressed tint on white

  // ---- Surfaces --------------------------------------------------------------
  // Cards are `secondary` on `background` — a deliberate, low-contrast lift that
  // carries the layout without borders or shadows.
  static const Color background = Color(0xFFF6F7F9); // the scaffold
  static const Color surface = Color(0xFFFAFAFA);
  static const Color surfaceVariant =
      Color(0xFFF5F5F5); // input fills, skeletons

  // ---- Text (the ink) --------------------------------------------------------
  static const Color textPrimary = Color(0xFF1A1A1A); // 16.24:1 — AAA
  static const Color textSecondary = Color(0xFF4A4A4A); // 8.27:1
  /// The LIGHTEST text that is still text — 4.76:1, exactly the AA floor.
  /// There is nothing legal below it: if a string wants to be fainter, make it
  /// smaller or less prominent, not greyer.
  static const Color textTertiary = Color(0xFF6E6E6E);

  /// Disabled control labels ONLY. Exempt from the contrast rule (WCAG exempts
  /// inactive components) — but exempt is not the same as invisible, which is why
  /// it is not the old #C0C0C0 (1.70:1, effectively blank).
  ///
  /// Note the app's *disabled-looking* text mostly uses [textTertiary], which at
  /// 4.76:1 is MORE readable. We deliberately do not "tidy" those onto this token.
  static const Color textDisabled = Color(0xFF9E9E9E); // 2.50:1

  // ---- Borders — three roles, three weights (SYSTEM.md §3.3) -----------------
  // One token doing three jobs got tuned for the softest and failed the strictest.
  static const Color divider =
      Color(0xFFE0E0E0); // decorative rules between rows
  static const Color border = Color(0xFFD0D0D0); // passive container hairlines

  /// **The sole boundary of any INTERACTIVE control** — text inputs, unselected
  /// checkboxes/chips/pills, time slots, dropdowns, dropzones (WCAG 1.4.11, 3:1).
  ///
  /// The rule in one line: if the border is the only thing telling you a control
  /// is there, it must be this. A field outlined in [border] (1.44:1) is a control
  /// a low-vision user cannot see — which is what every input in the app used to be.
  static const Color borderStrong = Color(0xFF8A8A8A); // 3.22:1

  /// The focus ring — 2px, 2px offset, so it never merges with the control's edge.
  static const Color borderFocus = Color(0xFF000000);

  // ---- Semantic (status only — never `Colors.green`/`Colors.red`) ------------
  static const Color success =
      Color(0xFF2D5016); // 8.63:1 · white on it: 9.25:1
  static const Color successLight = Color(0xFF4A7C2A); // 4.66:1

  static const Color error = Color(0xFF8B0000); // 9.34:1 · white on it: 10.01:1
  static const Color errorLight = Color(0xFFDC143C); // 4.66:1

  static const Color warning = Color(0xFF6B5B00); // 6.28:1

  /// ⚠️ NOT a foreground — 1.62:1. It is the background TINT of a warning chip,
  /// with [textPrimary] on it (10.04:1). As a text or icon colour it fails.
  static const Color warningLight = Color(0xFFFFB800);

  static const Color info = Color(0xFF1A1A2E); // 15.91:1
  static const Color infoLight = Color(0xFF2D3561); // 10.92:1

  // ---- Accents (SYSTEM.md §3.5) ----------------------------------------------
  // MEANING NEVER RIDES ON HUE. A gold star at 1.62:1 is invisible to a
  // low-vision user and meaningless to a colour-blind one — so it is never *the*
  // signal.

  /// The fill of a RATING STAR GLYPH, and nothing else — 1.62:1, so it can only
  /// ever be decoration. The information is carried by the numeral beside it
  /// (`★ 4,8 (32 avis)`) and by the glyph itself (`star_border` → `star`), which
  /// is what lets a rating survive greyscale.
  ///
  /// Gold-as-STATE — the unseen-story ring, the featured flag, a rating bar —
  /// uses [gold], which actually clears the 3:1 non-text floor.
  static const Color starRating = Color(0xFFFFB800);

  static const Color favorite =
      Color(0xFFE53935); // 3.94:1 — heart GLYPH; not text
  static const Color gold =
      Color(0xFFB8860B); // 3.04:1 — gold-as-state; not text

  // Service-category accents (map markers + category chips). A deliberate,
  // bounded **exception** to the monochrome identity: muted/earthy hues that aid
  // wayfinding without shouting. Use via `categoryColor()` — never inline.
  // See docs/design/SYSTEM.md §19. Falls back to [primary] (default).
  static const Color categorySpa = Color(0xFF5B6B4F); // sage · 5.35:1
  static const Color categoryBarber = Color(0xFF6D5A4C); // taupe · 6.09:1
  static const Color categorySalon = Color(0xFF4F5B6B); // slate · 6.44:1

  // Dark mode is deferred (SYSTEM.md §22). The four orphan `*Dark` constants that
  // used to sit here had zero references and no scheme behind them — when dark
  // mode lands it will be a full `ColorScheme.dark`, not four guessed hexes.
  // Every token above is ROLE-named precisely so that day is a value swap.
}
