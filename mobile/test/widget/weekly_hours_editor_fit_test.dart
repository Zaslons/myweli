import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/widgets/provider/weekly_hours_editor.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';

/// docs/design/pro-app-batch7.md §2.2 (B7.2) — a day's row stacks (day above,
/// hours and switch under it) only when it must. At the default size the
/// look is the one it always was: one line. The first version stacked EVERY
/// row at 1×, which only the golden saw — this holds it.
void main() {
  setUpAll(loadRealFonts);

  Future<void> pump(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final slot = TimeSlot(
      startTime: DateTime(2026, 1, 1, 13),
      endTime: DateTime(2026, 1, 1, 14),
      isAvailable: true,
    );
    await pumpApp(
      tester,
      theme: AppTheme.themeData(fontFamily: kRealFont),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: WeeklyHoursEditor(
            hours: {
              for (final d in [1, 2, 3, 4, 5]) d: [slot],
            },
            onChanged: (_) {},
            offLabel: 'Aucune',
          ),
        ),
      ),
    );
  }

  /// Whether « Mardi » and its switch share a line.
  bool oneLine(WidgetTester tester) {
    final day = tester.getRect(find.text('Mardi'));
    final switches = tester
        .widgetList<Switch>(find.byType(Switch))
        .map((w) => find.byWidget(w))
        .toList();
    final mine = switches[1]; // Lundi, Mardi, …
    final sw = tester.getRect(mine);
    return (sw.center.dy - day.center.dy).abs() < day.height;
  }

  testWidgets('at the default size, one line — as it always was', (
    tester,
  ) async {
    await pump(tester, 1);
    expect(oneLine(tester), isTrue);
  });

  testWidgets('at 200 %, the day above, its controls under it', (tester) async {
    await pump(tester, 2);
    expect(oneLine(tester), isFalse);
  });
}
