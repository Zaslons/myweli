import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/myweli_date_time_picker.dart';
import 'package:myweli/widgets/common/myweli_time_picker.dart';

import '../support/golden.dart';
import '../support/surface.dart';

/// The house time controls, photographed (A14b).
///
/// **Nothing in this repo has ever photographed a time picker**, in the same way
/// nothing had photographed a date picker before A14a. That matters more here
/// than it did there, because A14b's defect class is *invisible to arithmetic*:
/// Material's dialog does not clip, it **declines to grow**, and a control that
/// silently ignores the accessibility setting looks correct in every gate.
///
/// The gates prove the digits fit. These prove what someone actually sees.
///
/// Two sizes for each control, and the second is the point:
///
/// - **`w360`** is §10's floor.
/// - **`w360_x2`** is §13.3's contract point — the scale at which Material's
///   hour field is byte-for-byte the size it is at 100%.
///
/// No clock is involved: every seed is a literal, and none of these widgets
/// reads a clock (the salon's « now » is a parameter, for the reason recorded at
/// `MyweliMonthGrid.today`).
void main() {
  group('goldens', () {
    setUpAll(loadRealFonts);

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      double scale = 1,
    }) async {
      goldenSurface(tester, size: Size(360, kFloorPhone.height));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(goldenApp(home: home));
      await tester.pump();
    }

    const time = MyweliTimePickerScreen(
      initialTime: TimeOfDay(hour: 14, minute: 30),
    );

    const range = MyweliTimeRangePickerScreen(
      initialStart: TimeOfDay(hour: 9, minute: 0),
      initialEnd: TimeOfDay(hour: 17, minute: 0),
      startLabel: 'Heure de début',
      endLabel: 'Heure de fin',
    );

    final combined = MyweliDateTimePickerScreen(
      initialDate: DateTime(2026, 3, 11),
      initialTime: const TimeOfDay(hour: 14, minute: 30),
      firstDate: DateTime(2026, 3),
      lastDate: DateTime(2027, 3, 11),
      today: DateTime(2026, 3, 11),
    );

    testWidgets('the time picker at the floor', (tester) async {
      await pump(tester, time);
      await expectGolden(tester, 'components_time_picker_w360');
    });

    testWidgets('the time picker at 200% — the rows grew', (tester) async {
      // Against Material, where `TextScaler.noScaling` at `time_picker.dart:387`
      // means the hour field is the same size in both pictures.
      await pump(tester, time, scale: 2);
      await expectGolden(tester, 'components_time_picker_w360_x2');
    });

    testWidgets('the range picker at the floor', (tester) async {
      await pump(tester, range);
      await expectGolden(tester, 'components_time_range_picker_w360');
    });

    testWidgets('the range picker at 200% — both chips still readable', (
      tester,
    ) async {
      // The two chips are the whole reason this is one screen: at 2× they must
      // still both fit the row, or the control is back to hiding half its state.
      await pump(tester, range, scale: 2);
      await expectGolden(tester, 'components_time_range_picker_w360_x2');
    });

    testWidgets('the combined picker opens on the date step', (tester) async {
      await pump(tester, combined);
      await expectGolden(tester, 'components_date_time_picker_w360');
    });

    testWidgets('the combined picker at 200%', (tester) async {
      await pump(tester, combined, scale: 2);
      await expectGolden(tester, 'components_date_time_picker_w360_x2');
    });
  }, skip: kGoldensSkip);
}
