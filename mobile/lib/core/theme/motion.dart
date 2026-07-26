import 'package:flutter/animation.dart';

/// §9's five motion tokens — the Dart side, ported from the doc table that
/// `web/styles/tokens.ts` has mirrored since B2a.
///
/// **Values live in exactly one place**, and it is not this file: the
/// authority is SYSTEM.md §9's table. `web/tests/tokens.mirror.test.ts` reads
/// the table, this file and `tokens.ts`, and fails on any disagreement between
/// the three — so editing a number here without editing §9 is a red CI job, not
/// a silent divergence.
///
/// **Curves are mobile-only.** `tokens.ts:214` says so explicitly: Tailwind has
/// no equivalent for `easeOutCubic`, so the web mirrors durations and stops.
/// That is a declared divergence, not drift.
///
/// **The pairing is the rule, not a suggestion.** §9: entering decelerates
/// (`easeOut*`), exiting accelerates (`easeIn*`), and things that move *and*
/// stay use `easeInOut`. Every duration below therefore ships with its curve —
/// pick the token, take both. A8 found one site already inverted: the pro
/// splash faded a logo IN on `Curves.easeIn`.
class AppMotion {
  AppMotion._();

  /// The per-item delay in a staggered list reveal. No curve — it is an offset,
  /// not a movement.
  static const Duration stagger = Duration(milliseconds: 50);

  /// Immediate state feedback — ripple, checkbox, toggle.
  static const Duration fast = Duration(milliseconds: 100);
  static const Curve fastCurve = Curves.easeOut;

  /// **The default.** Most transitions, cross-fades, expand/collapse.
  static const Duration base = Duration(milliseconds: 200);
  static const Curve baseCurve = Curves.easeInOut;

  /// Entering surfaces — sheets, dialogs, snackbars.
  static const Duration emphasis = Duration(milliseconds: 300);
  static const Curve emphasisCurve = Curves.easeOutCubic;

  /// Full-screen / large-surface transitions. Also the **ceiling**: nothing
  /// user-initiated may take longer, because past ~400 ms an animation stops
  /// reading as *response* and starts reading as lag — especially on the
  /// reference low-end Android.
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve slowCurve = Curves.easeInOutCubic;
}
