import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';
import 'package:myweli/widgets/common/myweli_date_time_picker.dart';
import 'package:myweli/widgets/common/myweli_time_picker.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '_a11y.dart';
import '_fixtures.dart';

/// A4a — every interactive element has a ≥48×48 touch target (SYSTEM.md §13.2,
/// register row 12). `androidTapTargetGuideline` is Flutter's own check; before
/// A4a it went red on these components (hand-rolled gestures + a `shrinkWrap`
/// button), which is the whole reason the row existed. Component-level (cheap,
/// precise) — the screen-embedded fixes (contact rows, journal, photo controls)
/// are covered by the goldens + the same pattern.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
    // The picker subjects below use `pumpAtWidth`, which refuses to run without
    // a real font — it measures text, and the placeholder glyph is up to 79%
    // wider than Roboto.
    await loadRealFonts();
  });

  testWidgets('CommunePill — the location pill', (tester) async {
    final handle = await pumpForA11y(
      tester,
      CommunePill(commune: 'Cocody', onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('AdminSegmentedControl — the segments', (tester) async {
    final handle = await pumpForA11y(
      tester,
      AdminSegmentedControl(
        labels: const ['En attente', 'Vérifiés'],
        selected: 0,
        onSelect: (_) {},
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('ReviewTile — the « Signaler » action', (tester) async {
    final handle = await pumpForA11y(
      tester,
      ReviewTile(review: review(), onReport: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('AppointmentCard — the location + itinéraire rows', (
    tester,
  ) async {
    final handle = await pumpForA11y(
      tester,
      AppointmentCard(appointment: appt(), onTap: () {}),
      providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  // A11 C3. The row this measures used to be inline inside two `build` methods,
  // where this guideline could not reach it — and it was 50dp wide inside a
  // padding that made the row overflow a 360dp phone by 28px. After C3 the boxes
  // are `(W − 2×spacingM − 5×spacingS)/6`, which at 360 is **exactly 48.0**: the
  // §13.2 floor met with zero slack, by six targets a user types into one after
  // another. That is precisely the shape that needs a gate rather than a comment.
  testWidgets('OtpCodeRow — the six code boxes', (tester) async {
    final handle = await pumpForA11y(tester, otpRow());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  // A11 C4. **The first TabBar in any a11y inventory** — four shipped in `lib/`
  // and none had ever been measured against §13.2.
  //
  // Measured here rather than assumed, because the arithmetic says it should
  // fail: `_kTabHeight` is **46.0** (tabs.dart:30), 2dp under the 48×48 floor,
  // and it is a framework constant with no override short of `Tab(height:)` at
  // every call site. The `Tab`'s own box does measure 46.0 — and the guideline
  // **passes anyway**, in both bars below, because `androidTapTargetGuideline`
  // evaluates semantics nodes rather than that box.
  //
  // Recorded as a measured green rather than acted on: the fix for a number
  // that is already correct is nothing.
  //
  // **The two subjects are the two SHIPPING bars, not one bar pumped twice
  // (A12).** This was `for (final scrollable in [true, false])` over the same
  // four-label strip, and the `false` arm **overflowed** the moment
  // `pumpForA11y` began pinning 360dp: four French labels do not fit a bar that
  // divides a phone's width, which is the whole of C4's finding. It had been
  // green only against `flutter_test`'s 800dp default — and `lib/` has had no
  // such bar since C4 anyway.
  //
  // A guideline asserted against a layout that cannot render is not a
  // measurement. So each mode is now the bar that actually ships in it:
  // `tabStrip` is the scrollable four, `tabStripFill` the two short labels
  // `appointment_list_screen.dart` keeps on `fill`.
  for (final bar in <String, Widget Function()>{
    'the four pro tabs (scrollable)': tabStrip,
    'the two-tab bar that keeps fill': tabStripFill,
  }.entries) {
    testWidgets('TabBar — ${bar.key}', (tester) async {
      final handle = await pumpForA11y(tester, bar.value());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // **The guideline above cannot see the thing this subject is about**, and
      // the comment says so four paragraphs up: it evaluates semantics nodes,
      // not the `Tab`'s box. So until A12's review, both subjects asserted a
      // property their own documentation records as blind — a measured 46.0
      // written in prose beside an assertion that would pass at any height.
      //
      // Pinned here instead. 46.0 is `_kTabHeight` (tabs.dart:30), 2dp under
      // §13.2's floor, and it is the framework's with no override short of
      // `Tab(height:)` at every call site. Asserting it is not blessing it —
      // it makes the shortfall a number the suite holds, so a framework change
      // or a stray `height:` is visible rather than silent.
      for (final tab in find.byType(Tab).evaluate()) {
        expect(
          tester.getSize(find.byWidget(tab.widget)).height,
          46.0,
          reason:
              '§13.2 wants 48; a Tab measures `_kTabHeight`. If this moved, '
              'the register and the comment above both need re-deriving.',
        );
      }
      handle.dispose();
    });
  }

  testWidgets('NotificationTile — the tile tap', (tester) async {
    final handle = await pumpForA11y(
      tester,
      NotificationTile(notification: note(), onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  // ── A14b: the picker family, which had NO subject in any `meetsGuideline`
  // gate — not here, not in `label_test`, not in `contrast_test`.
  //
  // `time_picker_test.dart` asserts that text FITS; it says nothing about
  // targets. That gap is how A14a's month bar shipped a **40dp** year toggle
  // (`spacingS` twice around a 24dp line) and nobody noticed for a slice and a
  // half: the `Row` around it is 48 because of the chevrons, so it looks right
  // and measures short.
  //
  // The two TIME controls take Flutter's guideline whole. The two DATE-bearing
  // ones cannot, and that is recorded rather than skipped — see below.

  testWidgets('MyweliTimePickerScreen — every control meets the floor', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 1,
      home: const MyweliTimePickerScreen(
        initialTime: TimeOfDay(hour: 14, minute: 30),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('MyweliTimeRangePickerScreen — every control meets the floor', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 1,
      home: const MyweliTimeRangePickerScreen(
        initialStart: TimeOfDay(hour: 9, minute: 0),
        initialEnd: TimeOfDay(hour: 17, minute: 0),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  // **A month grid cannot pass `androidTapTargetGuideline`, on any phone.**
  // Measured here: the day cell is **Size(46.9, 56.0)** at 360dp. Seven 48dp
  // targets need 336dp plus padding, which no 360dp screen has — so §13.2's
  // floor is unreachable on the horizontal axis for *any* 7-column calendar.
  // A14a's §2.4 recorded that trade, `_WeekStrip` took it first, and
  // WEB-SYSTEM row 7h states it for the web twin.
  //
  // Asserting the guideline here and skipping the test would hide the one thing
  // that CAN regress: the height, and everything that is not a day cell. So the
  // exception is narrowed to exactly the day cells and the rest is measured.
  for (final subject in <String, Widget>{
    'MyweliDatePickerScreen': MyweliDatePickerScreen(
      initialDate: DateTime(2026, 3, 11),
      firstDate: DateTime(2026, 3),
      lastDate: DateTime(2027, 3, 11),
      today: DateTime(2026, 3, 11),
    ),
    'MyweliDateTimePickerScreen': MyweliDateTimePickerScreen(
      initialDate: DateTime(2026, 3, 11),
      initialTime: const TimeOfDay(hour: 14, minute: 30),
      firstDate: DateTime(2026, 3),
      lastDate: DateTime(2027, 3, 11),
      today: DateTime(2026, 3, 11),
    ),
  }.entries) {
    testWidgets('${subject.key} — 48 tall everywhere, width grid-bound only '
        'in the day cells', (tester) async {
      await pumpAtWidth(tester, width: 360, scale: 1, home: subject.value);

      // Every day cell: at least 48 TALL, and narrower only by the grid.
      //
      // Found through the day NUMBER, not by `w is GestureDetector` — the
      // broad predicate matched a 40×40 framework internal and reported it as a
      // failing day cell, which is a gate lying about which widget is wrong.
      for (final day in const ['1', '11', '28']) {
        final cell = find
            .ancestor(
              of: find.text(day),
              matching: find.byType(GestureDetector),
            )
            .first;
        final size = tester.getSize(cell);
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason:
              '§13.2 on the axis a month grid CAN satisfy — day « $day » '
              'measured ${size.width} × ${size.height}',
        );
        expect(
          size.width,
          greaterThan(40.0),
          reason:
              'grid-bound, but the column is (360 − 2×16)/7 ≈ 46.9 and a '
              'much smaller number would mean the grid, not the floor, broke',
        );
      }

      // The month bar's year toggle — the 40dp target this gate exists for.
      final toggle = find.ancestor(
        of: find.text('mars 2026'),
        matching: find.byType(InkWell),
      );
      expect(
        tester.getSize(toggle.first).height,
        greaterThanOrEqualTo(48.0),
        reason:
            'A14a shipped this at 40 — `spacingS` twice around a 24dp '
            'line — and the Row around it is 48 because of the chevrons, so '
            'it looked right and measured short',
      );
    });
  }
}
