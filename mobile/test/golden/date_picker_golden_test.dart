import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';

import '../support/golden.dart';
import '../support/surface.dart';

/// The house date picker, photographed (A14, SYSTEM.md §21 row 73).
///
/// **The first picker golden in this repo.** Row 73 was found by looking at a
/// phone, and until now nothing had ever photographed a date picker — no
/// golden opened one, and no screen test pumped one. A defect that only shows
/// up as *a missing digit* is exactly the kind §20.1 exists for: the arithmetic
/// gate in `test/a11y/date_picker_test.dart` proves the box is wide enough, and
/// the picture proves the month someone actually sees.
///
/// Two sizes, because the whole slice is about the second one:
///
/// - **`w360`** is §10's floor and the phone row 73 was measured on.
/// - **`w360_x2`** is §13.3's contract point, and the one that would have
///   caught « 2 21 2 2 2 2 2 » on sight.
///
/// The month is deterministic because it is a **literal** — `DateTime(2026,3,11)`
/// — not because a clock is frozen. The picker reads no clock at all; its
/// « today » marker is passed in by the call site, which is the only place that
/// knows the salon's timezone. An earlier draft credited `goldenApp`'s frozen
/// clock, which this widget never consults.
void main() {
  group('goldens', () {
    setUpAll(loadRealFonts);

    Future<void> pumpPicker(WidgetTester tester, {double scale = 1}) async {
      goldenSurface(tester, size: Size(360, kFloorPhone.height));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        goldenApp(
          home: MyweliDatePickerScreen(
            initialDate: DateTime(2026, 3, 11),
            firstDate: DateTime(2026, 3),
            lastDate: DateTime(2027, 3, 11),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the date picker at the floor', (tester) async {
      await pumpPicker(tester);
      await expectGolden(tester, 'components_date_picker_w360');
    });

    testWidgets('the date picker at 200% — every day still whole', (
      tester,
    ) async {
      // The picture row 73 is about. At 1.95× Material rendered « 2 21 2 2 2 2
      // 2 »; the cell here is a rectangle rather than a circle, so it takes the
      // column's full width and grows downwards instead of clipping.
      await pumpPicker(tester, scale: 2);
      await expectGolden(tester, 'components_date_picker_w360_x2');
    });
  }, skip: kGoldensSkip);
}
