import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';
import 'package:myweli/widgets/common/myweli_month_grid.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';

class _Result {
  bool popped = false;
  DaySelectionDelta? value;
}

/// What the multi-picker guarantees, as opposed to the single picker it
/// mirrors (A14e).
///
/// The two differ in exactly one way that matters, and everything here follows
/// from it: **this one cannot pop on tap.** A tap toggles, the commit is a
/// button, and the thing it hands back is a DELTA — because the picker's own
/// range hides every past day, so a full set would silently delete them.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  // A fixed month, never a clock: the picker reads none.
  final first = DateTime(2026, 3, 1);
  final last = DateTime(2026, 4, 30);

  /// Opens it from a real route and RECORDS what it pops.
  ///
  /// Records rather than awaits, for the reason `myweli_date_picker_test.dart`
  /// documents: awaiting a route's pop future hangs forever when the route
  /// never pops, so a broken assertion becomes a ten-minute stall instead of a
  /// failure.
  Future<_Result> open(
    WidgetTester tester, {
    Set<CalendarDay> initial = const {},
  }) async {
    final result = _Result();
    await tester.pumpWidget(
      wrapApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showMyweliMultiDatePicker(
                      context: context,
                      initialSelection: initial,
                      firstDate: first,
                      lastDate: last,
                      today: first,
                    ).then((v) {
                      result
                        ..popped = true
                        ..value = v;
                    }),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await settleMocks(tester);
    return result;
  }

  group('a tap toggles — it does not pop', () {
    testWidgets('the route survives the first tap', (tester) async {
      final r = await open(tester);

      await tester.tap(find.text('12'));
      await tester.pump();

      expect(
        r.popped,
        isFalse,
        reason:
            'the single picker pops on tap because its callers want one date; '
            'this one is a selection, and selecting is not submitting',
      );
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('tapping a chosen day removes it again', (tester) async {
      await open(tester, initial: {const CalendarDay(2026, 3, 12)});

      // 1 chosen → tap it → 0 chosen. The summary is the observable.
      expect(find.text('1 date bloquée'), findsOneWidget);
      await tester.tap(find.text('12'));
      await tester.pump();
      expect(find.text('1 date bloquée'), findsNothing);
    });
  });

  group('the delta is what comes back', () {
    testWidgets('added and removed are reported separately', (tester) async {
      final r = await open(tester, initial: {const CalendarDay(2026, 3, 12)});

      await tester.tap(find.text('12')); // remove the seeded one
      await tester.pump();
      await tester.tap(find.text('18')); // add one
      await tester.pump();
      await tester.tap(find.text('19')); // and another
      await tester.pump();

      await tester.tap(find.text('Enregistrer'));
      await settleMocks(tester);

      expect(r.popped, isTrue);
      expect(r.value!.added, {
        const CalendarDay(2026, 3, 18),
        const CalendarDay(2026, 3, 19),
      });
      expect(
        r.value!.removed,
        {const CalendarDay(2026, 3, 12)},
        reason:
            'the page needs the removals to filter its stored list — a set of '
            'survivors would make it guess which of its days the picker '
            'never showed',
      );
    });
  });

  group('the enablement rule — gated on the DELTA, never on the selection', () {
    testWidgets('deselecting the LAST chosen day leaves the button live', (
      tester,
    ) async {
      // The trap. `onPressed: _selected.isEmpty ? null : …` reads sensibly
      // and makes « tout débloquer » unreachable: the pro deselects their
      // last blocked day and the control dies with the change unsaved.
      final r = await open(tester, initial: {const CalendarDay(2026, 3, 12)});

      await tester.tap(find.text('12'));
      await tester.pump();

      expect(
        find.text('Toutes vos dates bloquées seront retirées.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Enregistrer'));
      await settleMocks(tester);

      expect(r.popped, isTrue, reason: 'unblocking everything must be savable');
      expect(r.value!.removed, {const CalendarDay(2026, 3, 12)});
      expect(r.value!.added, isEmpty);
    });

    testWidgets('nothing chosen and nothing changed → nothing to save', (
      tester,
    ) async {
      // The other half of the pair. Without it the rule above could be « always
      // enabled », which is a different bug wearing the same green.
      final r = await open(tester);

      expect(find.text('Touchez les jours à bloquer.'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await settleMocks(tester);

      expect(r.popped, isFalse, reason: 'an empty delta is not a save');
    });
  });

  group('an already-chosen day is PAINTED chosen', () {
    testWidgets('the seeded day reports isSelected to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, initial: {const CalendarDay(2026, 3, 12)});

      // Seeding through `Set<DateTime>` instead of `CalendarDay` renders
      // NOTHING selected — silently, because `DateTime.==` compares `isUtc`
      // and the grid builds local days. This is the assertion that catches it.
      expect(
        tester.getSemantics(
          find
              .ancestor(of: find.text('12'), matching: find.byType(Semantics))
              .first,
        ),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          // `isEnabled: true` is load-bearing, not decoration: a seed outside
          // [firstDate, lastDate] paints selected AND disabled — a `primary`
          // fill under `textTertiary` ink with a dead tap. The screen asserts
          // the invariant in debug; this is its observable consequence.
          label: 'jeudi 12 mars 2026',
        ),
      );
      handle.dispose();
    });
  });
}
