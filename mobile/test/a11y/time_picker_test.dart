import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myweli/widgets/common/myweli_date_time_picker.dart';
import 'package:myweli/widgets/common/myweli_time_picker.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';
import '_a11y.dart';

/// The time picker at §10's compact range and §13.3's floor (A14b).
///
/// **This gate could not be written the way A14a's was, and the reason is the
/// whole point of the slice.** A14a pointed its assertion at Material's own
/// `showDatePicker`, watched it go red, and only then built a replacement. Point
/// the same assertion at `showTimePicker` and it is **green unconditionally** —
/// not because the dialog is correct, but because there is nothing there to
/// measure:
///
/// - the dial is a `CustomPaint` driven by `_DialPainter`
///   (`time_picker.dart:1000`, `:1702`), inside
///   `GestureDetector(excludeFromSemantics: true)` (`:1697`) and
///   `ExcludeSemantics` (`:3041`);
/// - every helper in `_a11y.dart` walks
///   `tester.allRenderObjects.whereType<RenderParagraph>()`, and the dial
///   contains **zero**.
///
/// So Material's defect is unreachable by assertion, and the honest substitute
/// is two gates that *are* reachable: this one, on the house widget, and the
/// `TextScaler.noScaling` source pin in `design_system_pin_test.dart` — which
/// forbids the literal at `time_picker.dart:387` that makes the hour and minute
/// ignore the user's setting at every scale.
///
/// **Watched RED before the fix, so it is not a gate that has never failed.**
/// `_rowHeight` was replaced with the constant `24.0` — the titleMedium line
/// height *measured at 1×*, which is the mistake §13.3 describes in terms — and
/// `expectNoVerticalClip` reported, at every 2× width:
///
/// ```
/// Expected: empty
///   Actual: [
///             '    « 00 » needs 48.0dp in a 24.0dp box',
///             '    « 00 » needs 48.0dp in a 24.0dp box',
///             '    « 01 » needs 48.0dp in a 24.0dp box',
///             …
/// ```
///
/// **3 passed, 3 failed** — exactly the three 2× cells, with 1× clean at all
/// three widths, which also says the defect is a scale defect and not a width
/// one. « 00 » appears twice per report because it is the top of the hours
/// column *and* the top of the minutes column. Restoring the formula greens it.
///
/// The transcript lives here rather than in git history because committing a
/// knowingly-broken widget to prove a point is worse than recording what the
/// broken version printed — but it is the **real** output, pasted, not a
/// paraphrase. The first draft of this comment invented a plausible-looking
/// message that the helper does not emit.
///
/// The mechanical hazards A14a recorded still apply, and still produce a green
/// gate that measures nothing if ignored:
///
/// 1. `pumpAtWidth` defaults to a **1600dp-tall** surface, in which nothing can
///    clip vertically. The height is pinned to `kFloorPhone`'s 780.
/// 2. The loops stay **outside** `testWidgets` — `_overflowReportNeeded` latches
///    (`layout_test.dart:74-93`), so a width loop inside one test measures the
///    first width and silently skips the rest.
void main() {
  setUpAll(loadRealFonts);

  /// §10's compact range, and §13.3's two scales.
  const widths = <double>[360, 375, 390];
  const scales = <double>[1, 2];

  /// Two-digit tokens from the top of each column, which is what the columns
  /// scroll to when the picker opens at 00:00. Both are zero-padded, so « 00 »
  /// is present in the hours **and** the minutes and the assertion covers both.
  ///
  /// `expectTokensWhole` is A14a's `expectDayNumbersWhole`, renamed in this
  /// slice because the mechanism was never about days: an hour is the same
  /// thing — a single unbreakable token with no second line for a digit to move
  /// to.
  const namedTokens = <String>['00', '01', '02'];

  /// **All three controls, not just the leaf.** The first version of this file
  /// pumped `MyweliTimePickerScreen` alone, and the two it skipped were the two
  /// with a defect: at 360 × 2× the combined picker's date chip rendered
  /// « 11/03/2 » on one line and « 026 » on the next — a **mid-token break**,
  /// which is the thing `expectNoMidWordBreak` exists for. The goldens caught
  /// it; the gate could not, because the gate was not looking at that screen.
  ///
  /// A family of three controls needs three subjects. That is the whole lesson,
  /// and it is A8's restated: gating one representative and calling the family
  /// covered is how three defects shipped in five untouched call sites.
  final subjects = <String, Widget>{
    'the time picker': const MyweliTimePickerScreen(
      initialTime: TimeOfDay(hour: 0, minute: 0),
    ),
    'the range picker': const MyweliTimeRangePickerScreen(
      initialStart: TimeOfDay(hour: 9, minute: 0),
      initialEnd: TimeOfDay(hour: 17, minute: 0),
      startLabel: 'Heure de début',
      endLabel: 'Heure de fin',
    ),
    'the combined picker': MyweliDateTimePickerScreen(
      initialDate: DateTime(2026, 3, 11),
      initialTime: const TimeOfDay(hour: 14, minute: 30),
      firstDate: DateTime(2026, 3),
      lastDate: DateTime(2027, 3, 11),
      today: DateTime(2026, 3, 11),
    ),
  };

  for (final entry in subjects.entries) {
    for (final width in widths) {
      for (final scale in scales) {
        final at = '${width.toInt()}dp × ${scale.toInt()}× text';
        final name = entry.key;

        testWidgets('$name holds its digits at $at', (tester) async {
          pinSurface(tester, size: Size(width, kFloorPhone.height));
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(wrapApp(home: entry.value));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          if (name == 'the combined picker') {
            // C: it opens on the DATE step, so the month is the anchor.
            expect(find.text('mars 2026'), findsOneWidget,
                reason: 'C: the combined picker is not showing its date step '
                    'at $at, so every assertion below is about nothing');
            // **The defect the goldens found and this file used to miss.**
            // « 11/03/2026 » has no space to break at, so a chip too narrow
            // for it splits the number itself.
            expectNoMidWordBreak(tester, '11/03/2026', at);
          } else {
            expect(find.text('Heures'), findsOneWidget,
                reason: 'C: $name is not on screen at $at, so every assertion '
                    'below would be about nothing');
            expectTokensWhole(tester, namedTokens, at);
          }

          if (name == 'the range picker') {
            // Both halves visible at once is the reason this control exists.
            expectNoMidWordBreak(tester, 'Heure de début', at);
            expectNoMidWordBreak(tester, 'Heure de fin', at);
          }

          expectNoUndeclaredTruncation(tester, context: '$name at $at');
          expectNoLegibilityCrush(tester, context: '$name at $at');
          expectNoVerticalClip(tester, context: '$name at $at');
          expect(tester.takeException(), isNull, reason: 'A: $at');
        });
      }
    }
  }
}
