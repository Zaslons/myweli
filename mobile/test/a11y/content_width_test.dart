import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/widgets/common/content_width_cap.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';

/// §10's `contentMaxWidth`, measured (A11 C6).
///
/// ## Why this file pumps the widget instead of a screen
///
/// **No test in this repo renders an app root.** `grep MyweliApp mobile/test/`
/// returns nothing: every golden builds its own `MaterialApp` (`golden.dart`),
/// every widget test goes through `wrapApp`, and neither has a `builder:`. So a
/// cap wired into `main.dart` and `main_pro.dart` is invisible to every test in this suite,
/// and the spec's *"the unchanged golden suite is the no-regression proof"* is
/// true and **vacuous** — it proves nothing about the cap, because the cap is
/// not in any tree it photographs.
///
/// Two halves close that. This file measures the widget itself; a source pin in
/// `design_system_pin_test.dart` asserts the two roots install it and that the
/// admin root does not. It is the shape §20 already uses for
/// `ReduceMotionObserver` — *"every app root is source-pinned … globbed, not
/// listed"* — because a widget that is correct and uninstalled is still a bug.
///
/// The honest fix for the underlying gap is to make the test shell render at a
/// real device width instead of `flutter_test`'s 800×600, which the spec's §8
/// already files as its own slice. Capping `wrapApp` would move ~46 files from
/// 800 to 720 — neither of which is a phone.
void main() {
  setUpAll(loadRealFonts);

  /// The child, tagged so its box can be measured without depending on what is
  /// inside it.
  const key = ValueKey('capped');

  Future<Size> pumpCapAt(WidgetTester tester, double width) async {
    pinSurface(tester, size: Size(width, 800));
    await pumpApp(
      tester,
      home: const ContentWidthCap(
        child: ColoredBox(
            color: Color(0xFF000000), child: SizedBox.expand(key: key)),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byKey(key));
  }

  testWidgets('caps the column at 720 on a wide window', (tester) async {
    expect(
      (await pumpCapAt(tester, 1024)).width,
      AppTheme.contentMaxWidth,
      reason: '§10: text and forms never stretch past 720. A 1024dp window '
          'must render a 720dp column, not a 1024dp one.',
    );
  });

  testWidgets('centres it — the gutters are equal', (tester) async {
    await pumpCapAt(tester, 1024);
    final r = tester.getRect(find.byKey(key));
    expect(
      r.left,
      closeTo(1024 - r.right, 0.01),
      reason: 'the column is ${r.left}dp from the left and ${1024 - r.right}dp '
          'from the right — a capped column that is not centred is a column '
          'shoved against one edge',
    );
  });

  testWidgets('is the identity below 720 — every phone this ships to',
      (tester) async {
    expect(
      (await pumpCapAt(tester, 390)).width,
      390,
      reason: 'a ConstrainedBox(maxWidth: 720) under a tight 390 constraint '
          'passes it through, and Center on a child that already fills the '
          'width is a no-op. If this is not 390 the cap is doing something on '
          'a phone, which it must never do.',
    );
  });

  testWidgets('the boundary is inclusive, not off by one', (tester) async {
    expect(
      (await pumpCapAt(tester, AppTheme.contentMaxWidth)).width,
      AppTheme.contentMaxWidth,
      reason: 'at exactly 720 the cap must still be the identity',
    );
  });

  testWidgets('the gutters are painted, not left to the window',
      (tester) async {
    await pumpCapAt(tester, 1024);
    // Above the Navigator nothing paints the area outside the column, so the
    // ColoredBox is load-bearing rather than decoration: without it the gutters
    // are whatever the window happened to be cleared to.
    final box = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(ContentWidthCap),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(box.color, isNot(const Color(0x00000000)));
  });

  // ---- the SnackBar, measured rather than asserted -----------------------
  //
  // The spec promised « SnackBars are unaffected — ScaffoldMessenger wraps above
  // builder, so §15's bars stay full-bleed ». The premise is right and the
  // conclusion does not follow: ScaffoldMessenger is only the controller, and
  // the bar is rendered by ScaffoldState into its own layout slot, sized against
  // the SCAFFOLD's width. The Scaffold is under the builder.
  //
  // So the bar tracks the column. That was reviewed and kept — a floating bar
  // aligned with the content reads as belonging to it, and a 1400dp bar on a
  // stretched window is the same defect §10 names for body copy. This test
  // exists so the next person reads a measurement instead of either account.
  testWidgets('a SnackBar tracks the capped column, and that is deliberate',
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    pinSurface(tester, size: const Size(1024, 800));
    await tester.pumpWidget(
      wrapApp(
        scaffoldMessengerKey: messengerKey,
        home: const ContentWidthCap(child: Scaffold(body: SizedBox.expand())),
      ),
    );
    messengerKey.currentState!
        .showSnackBar(const SnackBar(content: Text('mesure')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bar = tester.getSize(find.byType(SnackBar));
    expect(
      bar.width,
      lessThanOrEqualTo(AppTheme.contentMaxWidth),
      reason: 'the bar is ${bar.width}dp in a 1024dp window. If this ever '
          'exceeds 720 the SDK has moved the SnackBar out of the Scaffold\'s '
          'layout, and the docstring on ContentWidthCap needs rewriting.',
    );
  });

  // ---- the two source pins ------------------------------------------------
  //
  // Discovered, not listed — the shape `motion_test.dart` uses for
  // `ReduceMotionObserver`: a fourth `main_*.dart` is covered the day it lands
  // rather than the day someone remembers this file.
  group(
      'every app root that should cap, does — and the one that must not,'
      " doesn't", () {
    List<File> roots() => Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'main(_\w+)?\.dart$').hasMatch(f.path))
        .toList();

    test('the phone apps install the cap', () {
      final found = roots();
      expect(found, isNotEmpty,
          reason: 'no app root found — this test is resolving paths from the '
              'wrong directory and would pass on an empty set');

      final missing = found
          .where((f) => !f.path.endsWith('main_admin.dart'))
          .where((f) => !f.readAsStringSync().contains('ContentWidthCap'))
          .map((f) => f.path)
          .toList();

      expect(missing, isEmpty,
          reason: '§10 caps text and forms at 720 on every phone surface. A '
              'root without the cap stretches a French paragraph across a '
              'tablet, and no other test can see it: nothing in this suite '
              'renders an app root.');
    });

    test('the admin console does NOT', () {
      // §4.5 asked for the exclusion to be held by "a **negative assertion**,
      // not a paragraph that can drift". This is it.
      //
      // Scoped to the ROOT file on purpose. A blanket "no width cap in the
      // admin tree" would fire on `admin_login_screen.dart`'s existing
      // `BoxConstraints(maxWidth: 380)` — a login card that is correctly
      // capped, in the app whose *console* must not be.
      final admin = File('lib/main_admin.dart');
      expect(admin.existsSync(), isTrue,
          reason: 'main_admin.dart moved — this pin is asserting about a file '
              'that is not there, which is a pass for the wrong reason');

      expect(
        admin.readAsStringSync().contains('ContentWidthCap'),
        isFalse,
        reason: 'admin is a desktop console, and §10 says so itself: "fine for '
            'the consumer app (its users hold phones) and wrong for admin". '
            'AdminScaffold is a top-level Row with a 240dp sidebar, and seven '
            'AdminDataTable call sites divide their width with Expanded '
            'columns and NO horizontal scroll — at 720 that leaves ~431dp for '
            'a five-column table, which truncates rather than scrolls.',
      );
    });
  });
}
