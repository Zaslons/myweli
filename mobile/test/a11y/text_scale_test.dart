import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/compact_appointment_tile.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/common/otp_code_row.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:myweli/widgets/home/category_chips.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '_a11y.dart';
import '_fixtures.dart';

/// A5 — the app survives the OS font-size setting at **200%** (SYSTEM.md §13.3,
/// register rows 15 + 16). A user who sets 200% has told the system they cannot
/// read the default; a layout that clips or overflows there is unusable for them.
///
/// A layout that can't grow throws a `RenderFlex` overflow during layout, so the
/// assertion is just "no exception". Before A5 this went red on `CategoryChips`
/// (a `SizedBox(height: 50)` around chips whose text doubled).
void main() {
  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  testWidgets('CategoryChips — the home category strip', (tester) async {
    await pumpAtTextScale(tester, const CategoryChips(selectedCategory: 'all'));
    expect(tester.takeException(), isNull);
  });

  // The strip is a horizontal scroller, so it NEEDS a bounded height — which is
  // exactly how it clipped: the bound was a constant. It must track the scale.
  testWidgets('CategoryChips — the strip grows with the text scale', (
    tester,
  ) async {
    await expectGrowsWithTextScale(
      tester,
      const CategoryChips(selectedCategory: 'all'),
      find.byType(CategoryChips),
    );
  });

  // A11 C3. The box was `Container(width: 50, height: 64)` around a
  // `headlineMedium` field — a fixed height around text, which §13.3 forbids in
  // writing. It was not a hypothetical clip: measured at the moment the height
  // came off, the field wanted **66.0dp at 1×** and had 64, so the row shipped
  // 2dp of clipping on every device, and wanted **99.0dp at 2×**.
  testWidgets('OtpCodeRow — the code boxes', (tester) async {
    await pumpAtTextScale(tester, otpRow());
    expect(tester.takeException(), isNull);
  });

  testWidgets('OtpCodeRow — the boxes grow with the text scale', (
    tester,
  ) async {
    await expectGrowsWithTextScale(tester, otpRow(), find.byType(OtpCodeRow));
  });

  testWidgets('CommunePill', (tester) async {
    await pumpAtTextScale(tester, CommunePill(commune: 'Cocody', onTap: () {}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdminSegmentedControl', (tester) async {
    await pumpAtTextScale(
      tester,
      AdminSegmentedControl(
        labels: const ['En attente', 'Vérifiés'],
        selected: 0,
        onSelect: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ReviewTile', (tester) async {
    await pumpAtTextScale(
      tester,
      ReviewTile(review: review(), onReport: () {}),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('NotificationTile', (tester) async {
    await pumpAtTextScale(
      tester,
      NotificationTile(notification: note(), onTap: () {}),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppointmentCard', (tester) async {
    await pumpAtTextScale(
      tester,
      AppointmentCard(appointment: appt(), onTap: () {}),
      providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    );
    expect(tester.takeException(), isNull);
  });

  // The `hint` variant is the one that breaks — an unflexed Text in a Row — so
  // pumping only the default variant is a gate that passes against the bug.
  for (final hint in [null, 'Réserver à nouveau']) {
    testWidgets('CompactAppointmentTile (hint: $hint) — bounded, as it ships', (
      tester,
    ) async {
      await pumpAtTextScale(
        tester,
        // Unbounded, a tile can never overflow and the gate is vacuous. Both
        // call sites hand it a fixed WIDTH inside a horizontal strip — so the
        // test has to hand it one too.
        //
        // **270, not 340** (A11 C5). 340 was wider than every width the tile is
        // ever given: home computes `(w × 0.86).clamp(280, 360)` → 309.6 at the
        // 360dp floor, and the salon page `(w × 0.75).clamp(260, 340)` → 270.
        // So this gate was green about a configuration that does not ship —
        // the same vacuity class §20 names, one level subtler than "unbounded".
        // 270 is the narrowest width either call site can produce.
        SizedBox(
          width: 270,
          child: CompactAppointmentTile(
            appointment: appt(),
            providerName: 'Salon Excellence',
            hint: hint,
            onTap: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Both tile strips are intrinsic (≤5 tiles): no computed bound, so the only
  // thing to prove is that the strip tracks the text.
  testWidgets('CompactAppointmentTile — grows with the text scale', (
    tester,
  ) async {
    await expectGrowsWithTextScale(
      tester,
      // The scroll view is load-bearing: it gives an UNBOUNDED vertical axis so
      // the tile takes its intrinsic height. Without it the tile's Column just
      // fills the 600px viewport and measures 600 at BOTH scales — the helper
      // would report "it did not grow" about the screen, not the tile.
      SingleChildScrollView(
        child: SizedBox(
          width: 270,
          child: CompactAppointmentTile(
            appointment: appt(),
            providerName: 'Salon Excellence',
            hint: 'Réserver à nouveau',
            onTap: () {},
          ),
        ),
      ),
      find.byType(CompactAppointmentTile),
    );
  });

  // ProviderCard's carousel is long, so it stays lazy and NEEDS a computed
  // bound — which means a measured constant (`_textBlockHeight`) that will rot
  // the day a row is added to the card. This is what stops that being silent:
  // the bound must still cover the card's real content at every scale a user
  // can pick — including the SMALL ones, where a proportional bound
  // under-provisions (rows are max(icon, line) and icons do not scale).
  for (final scale in [0.82, 0.85, 1.0, 1.3, 1.5, 2.0]) {
    testWidgets('ProviderCard.carouselHeight covers the card at $scale×', (
      tester,
    ) async {
      late double bound;
      double? intrinsic;
      await pumpApp(
        tester,
        providers: favProviders(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  bound = ProviderCard.carouselHeight(context);
                  // An unbounded vertical axis → the card takes its INTRINSIC
                  // height, i.e. what it actually needs at this scale.
                  return SingleChildScrollView(
                    child: SizedBox(
                      width: 280,
                      child: ProviderCard(
                        provider: MockData.providers.first,
                        isGrid: true,
                        onTap: () {},
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      intrinsic = tester.getSize(find.byType(ProviderCard)).height;
      expect(
        bound,
        greaterThanOrEqualTo(intrinsic),
        reason:
            'the carousel gives the card $bound at $scale× but it needs '
            '$intrinsic — the text is clipped (§13.3). If a row was added to '
            'the card, raise ProviderCard._textBlockHeight.',
      );
      // ...and it must not be wildly generous either: scaling the WHOLE bound
      // (image + padding included) is what produced 41% dead space at 200%.
      expect(
        bound - intrinsic,
        lessThan(40),
        reason:
            'the carousel over-provisions by ${bound - intrinsic}px at '
            '$scale× — dead space below every card.',
      );
    });
  }

  // A carousel card must be the ROOMY design at every scale — otherwise
  // reducing the OS font size silently hands some users a different card.
  //
  // This used to assert `carouselHeight >= 260`, a proxy for the card's old
  // `maxH < 260` threshold, and **the proxy is what let A12's grid bug
  // through**: it guarded the bound dipping BELOW 260 at 0.85× and said
  // nothing about A12's smaller `gridHeight` crossing it going UP at ≈1.74×.
  // The threshold is now `carouselHeight` itself, so the assertion can be the
  // real thing — the image the card actually drew.
  for (final scale in [0.5, 0.8, 0.82, 0.85, 1.0, 1.5, 2.0]) {
    testWidgets('a carousel card is the roomy design at $scale×', (
      tester,
    ) async {
      await pumpApp(
        tester,
        providers: favProviders(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  height: ProviderCard.carouselHeight(context),
                  width: 280,
                  child: ProviderCard(
                    provider: MockData.providers.first,
                    isGrid: true,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TimedCachedImage>(find.byType(TimedCachedImage)).height,
        180.0,
        reason:
            'at $scale× the carousel card fell into the COMPACT branch — '
            'a different card design for the same surface.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  // The grid's twin of `carouselHeight covers the card`, and the sweep that did
  // not exist when `gridHeight` shipped. `layout_test.dart` drives the real
  // screen but only at 1× and 2×; the defect it found lived at the crossing
  // (≈1.74×), so the scales BETWEEN the two contract points are the point.
  for (final scale in [0.82, 0.85, 1.0, 1.3, 1.5, 1.7, 1.8, 2.0]) {
    testWidgets('ProviderCard.gridHeight covers the card at $scale×', (
      tester,
    ) async {
      await pumpApp(
        tester,
        providers: favProviders(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  height: ProviderCard.gridHeight(context),
                  // A 360dp screen's two-column cell: 16 padding each side and
                  // a 16 gutter.
                  width: (360 - 16 * 2 - 16) / 2,
                  child: ProviderCard(
                    provider: MockData.providers.first,
                    isGrid: true,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the card does not fit the height `gridHeight` promises it at '
            '$scale× — the two formulas in provider_card.dart disagree again.',
      );
      expectNoVerticalClip(tester, context: 'grid card at $scale×');
    });
  }

  testWidgets('ProviderCard (list)', (tester) async {
    await pumpAtTextScale(
      tester,
      ProviderCard(provider: MockData.providers.first, onTap: () {}),
      providers: favProviders(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard (grid)', (tester) async {
    await pumpAtTextScale(
      tester,
      ProviderCard(
        provider: MockData.providers.first,
        isGrid: true,
        onTap: () {},
      ),
      providers: favProviders(),
    );
    expect(tester.takeException(), isNull);
  });
}
