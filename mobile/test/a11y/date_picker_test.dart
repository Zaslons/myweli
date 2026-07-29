import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myweli/widgets/common/myweli_date_picker.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';
import '_a11y.dart';

/// The date picker at §10's compact range and §13.3's floor (A14, §21 row 73).
///
/// **This gate was written against Material's own picker and watched go RED
/// before anything was built** — « the day 20 has 35.4dp and needs 36.9 at
/// 360dp × 2× text », 5 passed / 1 failed, the defect exactly 1.5dp wide and
/// present at 360 only. It now stands on `MyweliDatePickerScreen`, which is why
/// it is green; the measurement is recorded in
/// `docs/design/mobile-a14-pickers.md` §2.3 so a future reader can see what it
/// looked like when it could fail.
///
/// Row 73 was found on hardware during A12's device run and nothing in this
/// repo could see it:
/// `expectNoUndeclaredTruncation` is guarded against firing on wrapped prose,
/// `expectNoLegibilityCrush` has an 8-character floor a two-digit day is under,
/// and `expectNoMidWordBreak` skips the `maxLines: 1` paragraphs that a day
/// number is. `expectDayNumbersWhole` exists for this and is proven falsifiable
/// in `primitives_test.dart`.
///
/// **Two mechanical hazards, both of which would produce a green gate that
/// measures nothing:**
///
/// 1. `pumpAtWidth` defaults to a **1600dp-tall** surface, and a dialog in a
///    1600dp viewport can never clip. The height is pinned to `kFloorPhone`'s
///    780 — the phone row 73 was measured on.
/// 2. `pumpAtWidth` ends in `settleMocks`, not `pumpAndSettle`. The route needs
///    its own pumps **after** the frame that opens it, so the dialog is opened
///    from a post-frame callback (the `components_feedback_a6_golden_test.dart`
///    idiom) and then pumped past the fade explicitly.
///
/// The loops are outside `testWidgets`, as `layout_test.dart:74-93` requires:
/// `_overflowReportNeeded` latches on the first `RenderFlex` report, so a width
/// loop *inside* one test measures the first width and silently skips the rest.
void main() {
  setUpAll(loadRealFonts);

  /// §10's compact range, and §13.3's two scales. Same arrays as the matrix.
  const widths = <double>[360, 375, 390];
  const scales = <double>[1, 2];

  /// The days row 73 named. March 2026 contains all of them, and the frozen
  /// clock (`kFixedNow`, a Wednesday mid-month) puts the picker there.
  ///
  /// 21 is deliberately included even though row 73 records it as the one that
  /// survived: if a fix ever narrows the cell to exactly one narrow glyph, 21
  /// is the day that would still pass while every other two-digit day failed.
  const namedDays = <String>['20', '21', '22', '23', '24', '25', '26'];

  /// The picker's screen, pumped directly. It is public for this reason: a
  /// route adds a `Navigator` and a transition to a subject that is a layout.
  Widget host(DateTime initial) => MyweliDatePickerScreen(
        initialDate: initial,
        firstDate: DateTime(initial.year, initial.month),
        lastDate: initial.add(const Duration(days: 365)),
      );

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';

      testWidgets('every day number in the picker renders whole at $at',
          (tester) async {
        // 780, not `pumpAtWidth`'s 1600 — see the header. This is the phone
        // row 73 was measured on.
        pinSurface(tester, size: Size(width, kFloorPhone.height));
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(wrapApp(home: host(DateTime(2026, 3, 11))));
        await tester.pump(); // push the route
        await tester.pump(const Duration(milliseconds: 400)); // past the fade

        expect(
          find.text('mars 2026'),
          findsOneWidget,
          reason: 'C: the picker is not showing March 2026 at $at, so every '
              'assertion below is about the wrong month or no month',
        );

        expectDayNumbersWhole(tester, namedDays, at);
        expectNoUndeclaredTruncation(tester, context: 'date picker at $at');
        expectNoLegibilityCrush(tester, context: 'date picker at $at');
        expectNoVerticalClip(tester, context: 'date picker at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });
    }
  }
}
