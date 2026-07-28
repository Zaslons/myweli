import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';

import '_a11y.dart';
import '_fixtures.dart';

/// A4a — every interactive element has a ≥48×48 touch target (SYSTEM.md §13.2,
/// register row 12). `androidTapTargetGuideline` is Flutter's own check; before
/// A4a it went red on these components (hand-rolled gestures + a `shrinkWrap`
/// button), which is the whole reason the row existed. Component-level (cheap,
/// precise) — the screen-embedded fixes (contact rows, journal, photo controls)
/// are covered by the goldens + the same pattern.
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
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

  testWidgets('AppointmentCard — the location + itinéraire rows',
      (tester) async {
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
}
