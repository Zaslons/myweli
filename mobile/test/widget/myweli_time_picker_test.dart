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
  Future<void> tapValue(WidgetTester tester, String value) async {
    final f = find.text(value);
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
      await tapValue(tester, '14');

      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);

      expect(r.value!.start, const TimeOfDay(hour: 14, minute: 0));
      expect(r.value!.end.hour * 60 + r.value!.end.minute, greaterThan(14 * 60),
          reason: 'availability_screen.dart:642 faked this with '
              '`pickedStart.hour + 1` because two dialogs could not see each '
              'other. On one screen it is just a default the user can change.');
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
        minTimeOnToday: const TimeOfDay(hour: 14, minute: 0),
        initialDate: DateTime(2026, 3, 11),
      );

      // Today: the 09:00 seed is in the past and must be lifted.
      expect(find.text('14:00'), findsOneWidget,
          reason: 'today + an earlier hour was submittable before A14b, and '
              '« Choisissez une date et une heure à venir. » was the only '
              'thing that noticed');

      // A later day: the floor is a property of the DAY, so it lifts.
      await tester.tap(find.text('12'));
      await settleMocks(tester);
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester);
      expect(r.value!.date, DateTime(2026, 3, 12));
      expect(r.value!.time, const TimeOfDay(hour: 14, minute: 0),
          reason: 'the lift already happened on the today step and is not '
              'undone — but 09:00 would also be legal here, which is why the '
              'floor is re-evaluated on every day change rather than once');
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

      expect(r.value, isA<({DateTime date, TimeOfDay time})>(),
          reason: 'returning a DateTime would make the unsafe call the '
              'convenient one');
    });
  });
}

class _Result<T> {
  bool popped = false;
  T? value;
}
