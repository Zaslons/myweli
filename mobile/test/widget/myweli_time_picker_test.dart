import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/widgets/common/myweli_date_time_picker.dart';
import 'package:myweli/widgets/common/myweli_time_picker.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';

/// What the three time controls DO (A14b).
///
/// The a11y gate proves the digits fit. This proves the behaviour the slice's
/// whole argument rests on: that the end of a range **cannot** be before its
/// start, that a past time **cannot** be chosen for today, and that going back
/// from the time step does not destroy the date — the three things that used to
/// be error messages, or a bare `return`, or nothing at all.
///
/// **`settleMocks`, never `pumpAndSettle`** — `settle.dart` records that the
/// loading state is an infinitely repeating Lottie, so `pumpAndSettle()` never
/// returns. A14a's first draft used it and hung for ten minutes per test.
///
/// **The pop is recorded, not awaited.** Awaiting a route's pop future blocks
/// forever if the route never pops, turning a broken assertion into a hang
/// instead of a failure. A recorder turns the same bug into `popped == false`,
/// which a test can say out loud. Both lessons are A14a's, paid for once.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Future<_Result<T>> openFrom<T>(
    WidgetTester tester,
    Future<T?> Function(BuildContext) show,
  ) async {
    final result = _Result<T>();
    await tester.pumpWidget(wrapApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => show(context).then((v) {
                result
                  ..popped = true
                  ..value = v;
              }),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await settleMocks(tester);
    return result;
  }

  /// Taps a value in one of the wheels, scrolling it fully into view first.
  ///
  /// **`tester.tap` alone silently does nothing here, and the reason is worth
  /// recording.** The wheels are `ListView`s, so the last row on screen is
  /// *partially* rendered: measured on the default 800×600 test surface, « 30 »
  /// laid out at y 488–544 while the scroll viewport clips at **516**. `tap`
  /// aims at the widget's layout centre — y 516, exactly on the clip edge — so
  /// the hit test landed outside the viewport and no `onTap` fired. The
  /// assertion then failed on the *headline* rather than on the tap, which
  /// reads like a broken widget instead of a mis-aimed gesture.
  /// [column] is 0 for Heures and 1 for Minutes, and it is needed whenever the
  /// wanted row is not built yet. Each column opens **scrolled to its own
  /// selection**, so every value below it is outside the `ListView.builder`'s
  /// cache and `find.text` returns nothing at all — `ensureVisible` then throws
  /// « Bad state: No element » rather than scrolling, because there is no
  /// element to scroll to. Dragging is the only way down.
  Future<void> tapValue(WidgetTester tester, String value,
      {int column = 1}) async {
    // **Scoped to the column**, because « 10 » is an hour AND a minute: an
    // unscoped `find.text('10')` tapped whichever came first, and the B1 test
    // below quietly asserted about 12:10 instead of hour 10.
    final f = find.descendant(
      of: find.byType(Scrollable).at(column),
      matching: find.text(value),
    );
    if (f.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        f,
        find.byType(Scrollable).at(column),
        const Offset(0, 60),
      );
      await tester.pump();
    }
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settleMocks(tester);
  }

  group('MyweliTimePicker', () {
    testWidgets('confirming returns the chosen hour and minute',
        (tester) async {
      final r = await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );

      // 9:00 is the opening value, so the headline says so before any tap.
      expect(find.text('09:00'), findsOneWidget);

      await tapValue(tester, '30');
      expect(find.text('09:30'), findsOneWidget,
          reason: 'the headline is the only place the value is legible '
              'without decoding two highlighted columns');

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.popped, isTrue);
      expect(r.value, const TimeOfDay(hour: 9, minute: 30));
    });

    testWidgets('dismissing returns null and changes nothing', (tester) async {
      final r = await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      await tester.tap(find.byTooltip('Fermer'));
      await settleMocks(tester);

      expect(r.popped, isTrue);
      expect(r.value, isNull,
          reason: 'every call site treats null as "change nothing"');
    });

    testWidgets('an initialTime off the grid snaps onto it', (tester) async {
      // 09:07 with a 5-minute step highlights no row at all unless it snaps,
      // and « Confirmer » would then return a value the user never saw.
      await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 7),
        ),
      );
      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('minTime lifts the opening value out of the past',
        (tester) async {
      // The constraint Material could not express. Without it,
      // `pro_manual_booking`'s « Choisissez une date et une heure à venir. »
      // was the only thing standing between the user and an impossible time.
      await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 8, minute: 0),
          minTime: const TimeOfDay(hour: 14, minute: 10),
        ),
      );
      expect(find.text('14:10'), findsOneWidget,
          reason: 'an initialTime below the floor must be lifted TO the floor, '
              'not left selected-but-invalid');
    });

    testWidgets('a floor of 23:58 does not invent an hour 24', (tester) async {
      // **The crash this file was written too late to prevent, and the reason
      // the controls now do their arithmetic in total minutes.** The first
      // version lifted a below-floor selection by ceiling the MINUTE component
      // and carrying:
      //
      //   _minute = _ceilToStep(58);        // 60
      //   if (_minute >= 60) { _hour += 1; } // 24
      //
      // **`TimeOfDay` does NOT assert on hour 24** — `time.dart:55` has no range
      // check — so nothing threw, which is worse: « Confirmer » stayed enabled
      // (1440 is not < 1438), the headline read « 24:00 », and
      // `salonDateTime(hour: 24)` normalises to the NEXT DAY at 00:00. A
      // reschedule silently booked a different day than the one on screen. The
      // path is reachable: `pro_manual_booking` passes the salon's `now` as the
      // floor when the chosen day is today.
      //
      // The floor is now past the last time a 5-minute grid can represent, so
      // the correct behaviour is the documented EMPTY state: the columns render,
      // the selection sits at 23:55, and « Confirmer » is disabled because that
      // is still below the floor.
      final r = await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 8, minute: 0),
          minTime: const TimeOfDay(hour: 23, minute: 58),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'nothing throws either way — this is here so the test says '
              'out loud that the old failure was silent');
      expect(find.text('23:55'), findsOneWidget,
          reason: 'capped at the last time the grid can represent');

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.popped, isFalse,
          reason: 'no time on the grid satisfies the floor, so Confirmer is '
              'disabled — the empty state §11.4 specifies, not a value the '
              'caller would then have to re-validate');
    });

    testWidgets('a minuteStep that does not divide 60 still lands on the grid',
        (tester) async {
      // Not used by any call site today — the default is 5 and every caller
      // takes it — but the parameter is public, and 7 is the cheapest way to
      // show the arithmetic is not quietly assuming a divisor of 60.
      await openFrom<TimeOfDay>(
        tester,
        (context) => showMyweliTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 30),
          minuteStep: 7,
        ),
      );
      expect(tester.takeException(), isNull);
      // 30 snaps DOWN to 28 (4 × 7), which is a row the column actually offers.
      expect(find.text('09:28'), findsOneWidget);
    });
  });

  group('MyweliTimeRangePicker', () {
    testWidgets('confirming returns both halves', (tester) async {
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 9, minute: 0),
          initialEnd: const TimeOfDay(hour: 17, minute: 0),
        ),
      );

      // Both values are on screen at once — the reason this is one screen and
      // not the two indistinguishable modals it replaces.
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.popped, isTrue);
      expect(r.value?.start, const TimeOfDay(hour: 9, minute: 0));
      expect(r.value?.end, const TimeOfDay(hour: 17, minute: 0));
    });

    testWidgets('an initialEnd at or before the start is repaired on open',
        (tester) async {
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 17, minute: 0),
          initialEnd: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      // **Ordering alone is not enough, and the review proved it:** a widget
      // that silently SWAPPED the two — discarding the 17:00 start the caller
      // asked for — satisfies `end > start` and passed. So the start is pinned.
      expect(r.value!.start, const TimeOfDay(hour: 17, minute: 0),
          reason: 'the START the caller passed must survive; repairing the end '
              'is not licence to move the start');
      expect(r.value!.end.hour * 60 + r.value!.end.minute,
          greaterThan(r.value!.start.hour * 60 + r.value!.start.minute),
          reason: 'weekly_hours_editor.dart:75 answered this with a BARE '
              'SILENT RETURN — two modals, then the row simply did not '
              'change, indistinguishable from a cancel. The invalid state has '
              'to be unreachable, not caught.');
    });

    testWidgets('moving the start past the end drags the end with it',
        (tester) async {
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 9, minute: 0),
          initialEnd: const TimeOfDay(hour: 10, minute: 0),
        ),
      );

      // The « Début » chip is active on open, so the columns edit the start.
      await tapValue(tester, '14', column: 0);

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.value!.start, const TimeOfDay(hour: 14, minute: 0));
      expect(r.value!.end.hour * 60 + r.value!.end.minute, greaterThan(14 * 60),
          reason: 'availability_screen.dart:642 faked this with '
              '`pickedStart.hour + 1` because two dialogs could not see each '
              'other. On one screen it is just a default the user can change.');
    });

    testWidgets('an hour with no selectable minute in it is INERT',
        (tester) async {
      // **The review's B1.** The end column's hour predicate was
      // `(hour + 1) * 60 > start` — "does this hour end after the start" — but
      // the largest minute the column offers is `60 - step`. With a start of
      // 10:55 that marked hour 10 enabled while all of 10:00–10:55 was disabled,
      // so tapping 10 fell through to `_clampEnd` and the user landed on **11**.
      // Tapping a disabled row must do nothing at all.
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 10, minute: 55),
          initialEnd: const TimeOfDay(hour: 12, minute: 0),
        ),
      );

      await tester.tap(find.text('Fin'));
      await settleMocks(tester);
      await tapValue(tester, '10', column: 0);

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.end, const TimeOfDay(hour: 12, minute: 0),
          reason: 'hour 10 holds no minute after 10:55, so it is disabled and '
              'the tap changes nothing. It must not silently become 11:00.');
    });

    testWidgets('a start at the very end of the day stays ON the grid',
        (tester) async {
      // **The review's C2.** The start was clamped to `_lastGridMinute - 1` =
      // 1434 = **23:54**, which a 5-minute column never renders: nothing
      // highlighted and « Confirmer » returned a time the control never offered.
      // The cap is now one whole step below the last grid time, so there is
      // always a selectable end after it.
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 23, minute: 55),
          initialEnd: const TimeOfDay(hour: 23, minute: 59),
        ),
      );
      expect(find.text('23:50'), findsOneWidget,
          reason: 'clamped to the last START the grid allows, not to an '
              'off-grid 23:54');

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.start, const TimeOfDay(hour: 23, minute: 50));
      expect(r.value!.end, const TimeOfDay(hour: 23, minute: 55));
    });

    testWidgets('the repaired end is on the grid at a step that splits an hour',
        (tester) async {
      // **The review's B3.** `_clampEnd` did `start + step`, which crosses the
      // hour boundary without re-snapping: at a step of 7 a start of 10:56 gave
      // **11:03**, and 3 is not one of [0,7,14,…,56].
      final r = await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 10, minute: 56),
          initialEnd: const TimeOfDay(hour: 9, minute: 0),
          minuteStep: 7,
        ),
      );
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.value!.end.minute % 7, 0,
          reason: 'every returned minute must be a row the column renders — '
              '${r.value!.end.minute} is not on a 7-minute grid');
      expect(r.value!.end.hour * 60 + r.value!.end.minute,
          greaterThan(10 * 60 + 56));
    });

    testWidgets('the labels are the caller’s, not ours', (tester) async {
      // weekly_hours_editor is the only picker caller in the app that has ever
      // passed a localised string, and in chain B the two dialogs had NONE —
      // visually identical, with nothing saying which one you were in.
      await openFrom<({TimeOfDay start, TimeOfDay end})>(
        tester,
        (context) => showMyweliTimeRangePicker(
          context: context,
          initialStart: const TimeOfDay(hour: 9, minute: 0),
          initialEnd: const TimeOfDay(hour: 17, minute: 0),
          startLabel: 'Heure de début',
          endLabel: 'Heure de fin',
        ),
      );
      expect(find.text('Heure de début'), findsOneWidget);
      expect(find.text('Heure de fin'), findsOneWidget);
    });
  });

  group('MyweliDateTimePicker', () {
    Future<_Result<({DateTime date, TimeOfDay time})>> openCombined(
      WidgetTester tester, {
      DateTime? today,
      TimeOfDay? minTimeOnToday,
      DateTime? initialDate,
    }) =>
        openFrom<({DateTime date, TimeOfDay time})>(
          tester,
          (context) => showMyweliDateTimePicker(
            context: context,
            initialDate: initialDate ?? DateTime(2026, 3, 11),
            initialTime: const TimeOfDay(hour: 9, minute: 0),
            firstDate: DateTime(2026, 3),
            lastDate: DateTime(2027, 3, 11),
            today: today,
            minTimeOnToday: minTimeOnToday,
          ),
        );

    testWidgets(
        'a day tap advances to the time step, and Confirmer returns '
        'both', (tester) async {
      final r = await openCombined(tester);

      expect(find.text('Heures'), findsNothing,
          reason: 'it opens on the DATE step');
      await tester.tap(find.text('18'));
      await settleMocks(tester);
      expect(find.text('Heures'), findsOneWidget);

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.popped, isTrue);
      expect(r.value!.date, DateTime(2026, 3, 18));
      expect(r.value!.time, const TimeOfDay(hour: 9, minute: 0));
    });

    testWidgets('going back from the time step KEEPS the date', (tester) async {
      // The defect this control exists for. `pro_journal_screen.dart:433` hit
      // `if (time == null) return;` and silently threw away the date the user
      // had already chosen, with no message and no way back to it.
      final r = await openCombined(tester);

      await tester.tap(find.text('18'));
      await settleMocks(tester);
      await tester.tap(find.byTooltip('Retour à la date'));
      await settleMocks(tester);

      expect(r.popped, isFalse,
          reason: 'back is a step, not a dismissal — nothing has been decided');
      expect(find.text('18/03/2026'), findsOneWidget,
          reason: 'the date survives the trip back; that is the entire fix');

      await tester.tap(find.text('20'));
      await settleMocks(tester);
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.date, DateTime(2026, 3, 20));
    });

    testWidgets('closing from the date step returns null', (tester) async {
      final r = await openCombined(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settleMocks(tester);
      expect(r.popped, isTrue);
      expect(r.value, isNull);
    });

    testWidgets('the past-time floor applies to TODAY and not to other days',
        (tester) async {
      final r = await openCombined(
        tester,
        today: DateTime(2026, 3, 11),
        minTimeOnToday: const TimeOfDay(hour: 14, minute: 30),
        initialDate: DateTime(2026, 3, 11),
      );

      // Today: the 09:00 seed is in the past and must be lifted.
      expect(find.text('14:30'), findsOneWidget,
          reason: 'today + an earlier hour was submittable before A14b, and '
              '« Choisissez une date et une heure à venir. » was the only '
              'thing that noticed');

      // **The second clause, actually asserted.** The first version tapped a
      // later day and checked the time was still 14:00 — which holds whether or
      // not the floor applies to that day, because the init-time lift had
      // already moved it. Its own `reason` admitted as much. To distinguish the
      // two behaviours you have to pick a time BELOW the floor on the later day
      // and prove it sticks.
      // The minute column, not the hour column: an hour below the floor is
      // scrolled out of a `ListView.builder` and therefore not in the tree at
      // all, so `ensureVisible` throws « No element » rather than scrolling to
      // it. Minute 00 is on screen, and 14:00 is below the 14:30 floor, which is
      // all the assertion needs.
      await tester.tap(find.text('12'));
      await settleMocks(tester);
      await tapValue(tester, '00');
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.date, DateTime(2026, 3, 12));
      expect(r.value!.time, const TimeOfDay(hour: 14, minute: 0),
          reason: '14:00 is before the 14:30 floor but the day is NOT today, '
              'so the floor must not apply and the tap must stick. If the lift '
              'were unconditional, minute 00 would be disabled and this would '
              'come back 14:30.');
    });

    testWidgets('a floor late in an hour lifts to the next hour, not into it',
        (tester) async {
      // **The review's B2** — the combined picker had B1's over-permissive
      // predicate against the floor. With a floor of 10:56, hour 10 read as
      // enabled while no grid minute in it satisfied `>= 656`, so tapping 10
      // bounced straight to 11:00. Reachable ~7% of the time, because the floor
      // IS the salon's wall clock.
      final r = await openCombined(
        tester,
        today: DateTime(2026, 3, 11),
        minTimeOnToday: const TimeOfDay(hour: 10, minute: 56),
        initialDate: DateTime(2026, 3, 11),
      );
      expect(find.text('11:00'), findsOneWidget,
          reason: 'the first grid time at or after 10:56 is 11:00 — not 10:55, '
              'which is before it, and not 10:56, which is not a row');

      // It opens on the DATE step, so « Confirmer » does not exist yet.
      await tester.tap(find.text('11'));
      await settleMocks(tester);
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.time, const TimeOfDay(hour: 11, minute: 0));
    });

    testWidgets('it returns the PARTS, so the caller must recombine',
        (tester) async {
      // Not a style point. Composing `DateTime(y, m, d, h, min)` here would be
      // device-local — the shape §18 forbids, and the one
      // `availability_screen.dart:651-657` records having got wrong once, with
      // the note "The pin cannot see this: there is no clock token here".
      final r = await openCombined(tester);
      await tester.tap(find.text('18'));
      await settleMocks(tester);
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      // `isA<({DateTime date, TimeOfDay time})>()` was the first assertion here
      // and it is a TAUTOLOGY: `openFrom<T>` fixes T, so the matcher can only
      // fail on null — a check three tests above already make. What is worth
      // asserting is that the two parts come back UNCOMBINED and unconverted,
      // so the call site still has to run them through `salonDateTime`.
      expect(r.value!.date, DateTime(2026, 3, 18),
          reason: 'a bare calendar day, with no time folded into it');
      expect(r.value!.date.hour, 0);
      expect(r.value!.date.minute, 0);
      expect(r.value!.date.isUtc, isFalse,
          reason: 'not an instant — converting to one is the call site’s job, '
              'because only it knows the salon timezone (§18)');
      expect(r.value!.time, const TimeOfDay(hour: 9, minute: 0));
    });
  });
}

class _Result<T> {
  bool popped = false;
  T? value;
}
