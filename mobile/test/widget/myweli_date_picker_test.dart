import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';

/// What the picker DOES, as opposed to how wide it is (A14a).
///
/// **The adversarial review found this file missing, and the gap was
/// structural rather than an oversight.** Both a11y and golden subjects pump
/// `MyweliDatePickerScreen` directly, so `showMyweliDatePicker()` — the route,
/// the `fullscreenDialog`, the `Navigator.pop(d)`, and the whole tap-and-pop
/// contract the slice's UX argument turns on — had **zero coverage**. Nothing
/// asserted that tapping a day returns that day, that dismissing returns null,
/// or that a disabled day is inert. The geometry gate proved geometry and
/// nothing else.
///
/// That the screen is public is not the smell; it is public *because* the tests
/// avoided the route, and that was.
///
/// **`settleMocks`, never `pumpAndSettle`** — the house idiom, and it is not
/// stylistic: `settle.dart` records that the loading state is an infinitely
/// repeating Lottie, so `pumpAndSettle()` never returns. The first draft of
/// this file used it and hung for ten minutes per test.
void main() {
  // `weekdayInitials()` asks `intl` for French weekday names, and a bare unit
  // test has no locale data — the app loads it at startup and `wrapApp` loads
  // it for the widget tests. Without this the helper throws
  // `UninitializedLocaleData`, which is worth knowing about the helper as much
  // as about the test.
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  /// Opens the picker from a real route and records what it pops.
  ///
  /// **It records rather than returns a `Future` to await**, and that is not a
  /// style choice: `await`ing a route's pop future in a widget test blocks
  /// forever if the route never pops, so a broken assertion becomes a ten-minute
  /// hang instead of a failure. The first draft of this file did exactly that.
  /// A recorder turns the same bug into `popped == false`, which a test can say
  /// out loud.
  Future<_Result> open(
    WidgetTester tester, {
    required DateTime initial,
    required DateTime first,
    required DateTime last,
    DateTime? today,
  }) async {
    final result = _Result();
    await tester.pumpWidget(wrapApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMyweliDatePicker(
                context: context,
                initialDate: initial,
                firstDate: first,
                lastDate: last,
                today: today,
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
    ));
    await tester.tap(find.text('ouvrir'));
    await settleMocks(tester);
    return result;
  }

  testWidgets('tapping a day returns THAT day and pops', (tester) async {
    final r = await open(
      tester,
      initial: DateTime(2026, 3, 11),
      first: DateTime(2026, 3),
      last: DateTime(2026, 4, 30),
    );

    await tester.tap(find.text('19'));
    await settleMocks(tester);

    // `popped` is the contract; whether the widget has finished leaving the
    // tree is the pop ANIMATION, and `settleMocks` deliberately does not run
    // animations to completion.
    expect(r.popped, isTrue, reason: 'tapping a day must pop the route');
    expect(r.value, DateTime(2026, 3, 19));
  });

  testWidgets('dismissing returns null and changes nothing', (tester) async {
    final r = await open(
      tester,
      initial: DateTime(2026, 3, 11),
      first: DateTime(2026, 3),
      last: DateTime(2026, 4, 30),
    );

    await tester.tap(find.byTooltip('Fermer'));
    await settleMocks(tester);

    expect(r.popped, isTrue);
    expect(r.value, isNull);
  });

  testWidgets('a day outside the range is inert', (tester) async {
    // `firstDate` is the 10th, so the 5th renders and must not be selectable.
    final r = await open(
      tester,
      initial: DateTime(2026, 3, 11),
      first: DateTime(2026, 3, 10),
      last: DateTime(2026, 3, 31),
    );

    await tester.tap(find.text('5'));
    await settleMocks(tester);

    expect(r.popped, isFalse, reason: 'a disabled day must not pop the route');
    expect(find.text('mars 2026'), findsOneWidget);
  });

  testWidgets('an initialDate BEFORE the range opens on the first legal month',
      (tester) async {
    // The dead end the review found: rescheduling a PAST appointment passes its
    // own date while `firstDate` is today. Unclamped, the picker opened on a
    // month with every day disabled and the back chevron off.
    await open(
      tester,
      initial: DateTime(2025, 11, 4),
      first: DateTime(2026, 3, 10),
      last: DateTime(2026, 9, 30),
    );

    expect(find.text('mars 2026'), findsOneWidget);
    expect(find.text('novembre 2025'), findsNothing);
  });

  testWidgets('the year list jumps a year in two taps, not twelve',
      (tester) async {
    final r = await open(
      tester,
      initial: DateTime(2026, 3, 11),
      first: DateTime(2026, 3),
      last: DateTime(2027, 3, 31),
    );

    await tester.tap(find.text('mars 2026'));
    await settleMocks(tester);
    await tester.tap(find.text('2027'));
    await settleMocks(tester);

    expect(find.text('mars 2027'), findsOneWidget);

    await tester.tap(find.text('19'));
    await settleMocks(tester);
    expect(r.value, DateTime(2027, 3, 19));
  });

  testWidgets('today is announced, and only when it is passed in',
      (tester) async {
    await open(
      tester,
      initial: DateTime(2026, 3, 11),
      first: DateTime(2026, 3),
      last: DateTime(2026, 4, 30),
      today: DateTime(2026, 3, 17),
    );

    expect(
      // `\u2019`, not the character: the §20 pin forbids a curly quote inside a
      // `RegExp(`, because such a pattern can never match Dart source — four
      // pins were silently disabled that way in one commit.
      find.bySemanticsLabel(RegExp('^aujourd\u2019hui, ')),
      findsOneWidget,
      reason: 'the marker is a semantic label as well as a ring — §13 forbids '
          'meaning carried by colour alone',
    );
  });

  group('Formatters.weekdayInitials', () {
    test('is French, Monday first', () {
      // §17 and `french_test.dart`'s `firstDayOfWeekIndex == 1`: a French
      // calendar starts on Monday, and this is the list the header renders.
      expect(Formatters.weekdayInitials(),
          <String>['L', 'M', 'M', 'J', 'V', 'S', 'D']);
    });
  });
}

/// What the route popped, recorded rather than awaited — see [main]'s helper.
class _Result {
  bool popped = false;
  DateTime? value;
}
