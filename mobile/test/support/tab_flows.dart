import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settle.dart';

/// Reaching the data behind a tab, once (A11 C7).
///
/// Both sequences below were already written twice — `_openProList` and
/// `_openEarningsAll` are `_`-private in `test/a11y/layout_test.dart`, and the
/// earnings one is inline a second time in `pro_screens_golden_test.dart`. A
/// golden file cannot import a private helper, so C7's third subject would have
/// made a third copy, which §11 calls a review failure.
///
/// **They are shared for the C1/C3 reason, not the count.** Every line here is
/// fiddly and every line is load-bearing: a tap that does not land, or a settle
/// one round short, produces an *empty state* — and an empty state is a test
/// that passes about nothing. That failure looks identical to success in a
/// finder-based assertion and identical to a screen in a picture.

/// Taps « Tout » on the pro earnings screen and proves rows arrived.
///
/// Until C4 the screen's first load passed no date bounds while every tab tap
/// passed them, so it opened showing every transaction the salon had ever taken.
/// C4 made the first load the selected tab's load, so « Aujourd'hui » is now
/// correctly empty — `MockData` seeds `provider1` at `now + 2d`, `now - 10d` and
/// `now - 7d`, never today — and anything that wants to see takings has to go
/// where they are.
///
/// `ensureVisible` first: the bar is scrollable since C4 and « Tout » is the
/// last of four, which at 200% text sits well outside a 360dp viewport.
Future<void> openEarningsAll(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Tout'));
  await tester.tap(find.text('Tout'));
  await settleMocks(tester, rounds: 3);
  expect(
    find.text('Aucune transaction'),
    findsNothing,
    reason: 'the « Tout » tap did not land, or the salon has no takings at all '
        '— either way the tab bar would be the only thing this measured',
  );
}

/// Reaches the four-tab bar on `AppointmentListScreen`, and proves it arrived.
///
/// **Two taps, and neither is optional.**
///
/// 1. `TabBarView` builds only the visible page, so the whole « Liste » column —
///    including the TabBar this exists to reach — does not exist while
///    « Calendrier » is showing. An unbuilt widget cannot overflow and cannot be
///    photographed, so a one-tap version is green (and blank) at every width.
/// 2. Landing on « Liste » runs `_loadAppointmentsForListTab(0)` = « Aujourd'hui »,
///    whose salon-day bounds `MockData` never seeds. So the first thing the tab
///    shows is « Aucun rendez-vous ». « Tous » is the tab with data in it.
///
/// The `ensureVisible` before « Tous » is not defensive padding. C4 made this bar
/// scrollable, so at 200% text its strip is 553dp inside a 360dp viewport and
/// « Tous » — the last tab — sits at [458.6, 553.0], entirely off-screen at all
/// three widths. Without it the failure is silent and misleading:
/// `hitTestWarningShouldBeFatal` is false by default and nothing here sets it, so
/// `tester.tap` prints a warning, dispatches into nothing, the controller never
/// moves, and the test dies on the `findsWidgets` below — an empty-state failure
/// whose real cause is a console line forty rows up.
Future<void> openProList(WidgetTester tester) async {
  await tester.tap(find.text('Liste'));
  // kTabScrollDuration is 300ms and the tab's own reload is another 300; three
  // 400ms rounds clear both with room to spare.
  await settleMocks(tester, rounds: 3);
  expect(
    find.byType(TabBar),
    findsNWidgets(2),
    reason: 'the « Liste » page never built — its TabBar is the subject, and '
        'a TabBarView does not build a page it is not showing',
  );

  await tester.ensureVisible(find.text('Tous'));
  await tester.tap(find.text('Tous'));
  await settleMocks(tester, rounds: 3);
  expect(
    find.byType(Card),
    findsWidgets,
    reason: '« Tous » is the tab that has rows; if this is empty the caller is '
        'measuring or photographing an empty state',
  );
}
