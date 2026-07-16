import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/compact_appointment_tile.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/home/category_chips.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/pump_app.dart';
import '_a11y.dart';

/// A5 — the app survives the OS font-size setting at **200%** (SYSTEM.md §13.3,
/// register rows 15 + 16). A user who sets 200% has told the system they cannot
/// read the default; a layout that clips or overflows there is unusable for them.
///
/// A layout that can't grow throws a `RenderFlex` overflow during layout, so the
/// assertion is just "no exception". Before A5 this went red on `CategoryChips`
/// (a `SizedBox(height: 50)` around chips whose text doubled).
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  List<SingleChildWidget> favProviders() => [
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ];

  Review review() => Review(
        id: 'r1',
        providerId: 'p1',
        userId: 'u1',
        userName: 'Marie Diallo',
        rating: 5,
        text: 'Super service, je recommande vivement ce salon.',
        createdAt: DateTime(2025, 2, 4),
      );

  Appointment appt() => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime(2026, 6, 30, 10),
        status: AppointmentStatus.confirmed,
        totalPrice: 20000,
        createdAt: DateTime(2026),
      );

  AppNotification note() => AppNotification(
        id: '1',
        type: AppNotificationType.bookingConfirmed,
        title: 'Rendez-vous confirmé',
        body: 'Salon Excellence, Cocody — jeudi 30 juin à 10h00',
        createdAt: DateTime(2026, 6, 29, 10),
        read: false,
      );

  testWidgets('CategoryChips — the home category strip', (tester) async {
    await pumpAtTextScale(tester, const CategoryChips(selectedCategory: 'all'));
    expect(tester.takeException(), isNull);
  });

  // The strip is a horizontal scroller, so it NEEDS a bounded height — which is
  // exactly how it clipped: the bound was a constant. It must track the scale.
  testWidgets('CategoryChips — the strip grows with the text scale',
      (tester) async {
    await expectGrowsWithTextScale(
      tester,
      const CategoryChips(selectedCategory: 'all'),
      find.byType(CategoryChips),
    );
  });

  testWidgets('CommunePill', (tester) async {
    await pumpAtTextScale(
      tester,
      CommunePill(commune: 'Cocody', onTap: () {}),
    );
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
        tester, ReviewTile(review: review(), onReport: () {}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('NotificationTile', (tester) async {
    await pumpAtTextScale(
        tester, NotificationTile(notification: note(), onTap: () {}));
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
    testWidgets('CompactAppointmentTile (hint: $hint) — bounded, as it ships',
        (tester) async {
      await pumpAtTextScale(
        tester,
        // Unbounded, a tile can never overflow and the gate is vacuous. Both
        // call sites hand it a fixed WIDTH inside a horizontal strip — so the
        // test has to hand it one too.
        SizedBox(
          width: 340,
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
  testWidgets('CompactAppointmentTile — grows with the text scale',
      (tester) async {
    await expectGrowsWithTextScale(
      tester,
      // The scroll view is load-bearing: it gives an UNBOUNDED vertical axis so
      // the tile takes its intrinsic height. Without it the tile's Column just
      // fills the 600px viewport and measures 600 at BOTH scales — the helper
      // would report "it did not grow" about the screen, not the tile.
      SingleChildScrollView(
        child: SizedBox(
          width: 340,
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
    testWidgets('ProviderCard.carouselHeight covers the card at $scale×',
        (tester) async {
      late double bound;
      double? intrinsic;
      await pumpApp(
        tester,
        providers: favProviders(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(builder: (context) {
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
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      intrinsic = tester.getSize(find.byType(ProviderCard)).height;
      expect(
        bound,
        greaterThanOrEqualTo(intrinsic),
        reason: 'the carousel gives the card $bound at $scale× but it needs '
            '$intrinsic — the text is clipped (§13.3). If a row was added to '
            'the card, raise ProviderCard._textBlockHeight.',
      );
      // ...and it must not be wildly generous either: scaling the WHOLE bound
      // (image + padding included) is what produced 41% dead space at 200%.
      expect(
        bound - intrinsic,
        lessThan(40),
        reason: 'the carousel over-provisions by ${bound - intrinsic}px at '
            '$scale× — dead space below every card.',
      );
    });
  }

  // The bound must never dip under the card's own compact threshold
  // (provider_card.dart: maxH < 260 swaps the image size and padding). A bound
  // that shrank with the text scale would trip it at Android "Small" (0.85) and
  // silently hand a DIFFERENT card design to users who reduce their font size.
  testWidgets('ProviderCard.carouselHeight never trips the compact branch',
      (tester) async {
    for (final scale in [0.5, 0.8, 0.82, 0.85, 1.0]) {
      late double bound;
      await pumpApp(
        tester,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Builder(builder: (context) {
              bound = ProviderCard.carouselHeight(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(bound, greaterThanOrEqualTo(260),
          reason: 'at $scale× the carousel bound is $bound, under the card\'s '
              'own compact threshold (260) — reducing the OS font size would '
              'silently change the card design.');
    }
  });

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
