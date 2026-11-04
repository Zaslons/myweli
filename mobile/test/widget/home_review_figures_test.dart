import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/app_rating.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// The home, when a review is published — what the client SEES
/// (docs/design/amounts-that-fit.md §1.4, §8.4; consumer-reviews.md §2).
///
/// `review_figures_test.dart` asserts the figures each notifier holds and
/// that it notifies. This asserts the cards: the home keeps three copies of a
/// salon on one screen — the carousel's, « Mes favoris »' and the list's —
/// and only the open salon page used to move, so all three kept « Nouveau ».
void main() {
  setUpAll(() {
    // Before the services are built: several mocks seed clock-relative data
    // at construction.
    AppClock.freeze(kFixedNow);
    // `favorites_user1` is `MockFavoritesService`'s store; `user1` is who
    // [signInConsumer] signs in.
    SharedPreferences.setMockInitialValues({
      'favorites_user1': '["provider1"]',
    });
    stubSecureStorage(); // else the session read throws, on screen
    setupDependencyInjection(); // every service, all mocks
  });

  tearDownAll(AppClock.restore);

  setUp(() => freezeClock(kFixedNow));

  testWidgets('a first review takes « Nouveau » off the home at once — the '
      'carousel card, the favourite and the list row — and the re-read does '
      'not bring it back', (tester) async {
    // TWO unrated salons: the mock's carousel is the three best rated of
    // four, so a single unrated salon would not be in it.
    final seeded = List.of(MockData.providers);
    addTearDown(() {
      MockData.providers
        ..clear()
        ..addAll(seeded);
      MockData.reviews.removeWhere((r) => r.appointmentId == 'home-first');
    });
    for (var i = 0; i < seeded.length; i++) {
      if (seeded[i].id == 'provider1' || seeded[i].id == 'provider2') {
        MockData.providers[i] = seeded[i].copyWith(rating: 0, reviewCount: 0);
      }
    }

    final auth = await signInConsumer(tester);
    final salons = ProviderProvider();
    final favorites = FavoritesProvider();
    // Wide and tall: the carousels and the list are lazy, and a card that is
    // not built is a card this cannot look at.
    pinSurface(tester, size: const Size(1400, 2400));
    await tester.pumpWidget(
      wrapApp(
        home: const HomeScreen(),
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: salons),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider.value(value: favorites),
        ],
      ),
    );
    await settleMocks(tester, rounds: 5);

    // What each card of a salon was BUILT with, in screen order.
    List<(double, int)> cardsOf(String id) => [
      for (final rating in tester.widgetList<AppRating>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ProviderCard && w.provider.id == id,
          ),
          matching: find.byType(AppRating),
        ),
      ))
        (rating.rating, rating.reviewCount),
    ];

    expect(
      cardsOf('provider1'),
      [(0.0, 0), (0.0, 0), (0.0, 0)],
      reason: 'the carousel, « Mes favoris » and the list — all three built',
    );
    expect(cardsOf('provider2'), [(0.0, 0)], reason: 'the list alone');
    expect(find.text('Nouveau'), findsNWidgets(4));

    // « Publier », as the sheet sends it: the favourites' patch handed over.
    final published = salons.submitReview(
      Review(
        id: 'draft',
        appointmentId: 'home-first',
        providerId: SalonId('provider1'),
        userId: 'user1',
        userName: 'Awa K.',
        rating: 5,
        text: 'Très bien',
        createdAt: AppClock.now(),
      ),
      alsoPatch: favorites.patchSalonFigures,
    );
    // One mock round trip: the 201. The re-read is out, not answered.
    await tester.pump(const Duration(milliseconds: 350));
    expect(await published, isTrue);
    await tester.pump();

    expect(cardsOf('provider1'), [(5.0, 1), (5.0, 1), (5.0, 1)]);
    expect(find.text('Nouveau'), findsOneWidget, reason: 'the other salon');
    expect(cardsOf('provider2'), [(0.0, 0)]);

    // The re-read answers — from the mock's store, which counted the review.
    await settleMocks(tester, rounds: 2);

    expect(cardsOf('provider1'), [(5.0, 1), (5.0, 1), (5.0, 1)]);
    expect(find.text('Nouveau'), findsOneWidget);
  });
}
