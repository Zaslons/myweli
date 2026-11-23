import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:provider/provider.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';

void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  Widget wrap(Widget child) => wrapApp(
    providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    home: Scaffold(body: child),
  );

  Appointment appt({String? clientName}) => Appointment(
    id: 'a1',
    userId: clientName == null ? 'u1' : 'manual',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2026, 6, 30, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 20000,
    createdAt: DateTime(2026),
    clientName: clientName,
  );

  testWidgets('shows the salon-entered badge when clientName is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt(clientName: 'Awa'),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Réservé par votre salon'), findsOneWidget);
  });

  testWidgets('hides the badge for a normal booking', (tester) async {
    await tester.pumpWidget(
      wrap(AppointmentCard(appointment: appt(), onTap: () {})),
    );
    await tester.pump();
    expect(find.text('Réservé par votre salon'), findsNothing);
  });

  // consumer-app-truth.md §2.6: the booking carries its salon's name and its
  // services' names. The discovery list here is EMPTY (nothing loaded), which
  // is the case of a salon in another commune, on page two, or gone from the
  // listing — it used to read « Salon » with no services.
  testWidgets('reads the salon and the services from the booking itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt().copyWith(
            providerName: 'Beauté Awa',
            serviceNames: const ['Tresses', 'Pose de vernis'],
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Beauté Awa'), findsOneWidget);
    expect(find.text('Salon'), findsNothing);
    expect(find.text('Tresses'), findsOneWidget);
    expect(find.text('Pose de vernis'), findsOneWidget);
  });

  testWidgets('with no name anywhere, says « Salon » (§17.2)', (tester) async {
    await tester.pumpWidget(
      wrap(AppointmentCard(appointment: appt(), onTap: () {})),
    );
    await tester.pump();
    expect(find.text('Salon'), findsOneWidget);
  });

  // §2.7: a past booking the salon never confirmed is not « Terminé ».
  testWidgets('a past pending booking reads « Non confirmé »', (tester) async {
    freezeClock(DateTime(2026, 7, 2, 12));
    await tester.pumpWidget(
      wrap(
        AppointmentCard(
          appointment: appt().copyWith(status: AppointmentStatus.pending),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Non confirmé'), findsOneWidget);
    expect(find.text('En attente'), findsNothing);
    expect(find.text('Terminé'), findsNothing);
  });

  // A2 (appointment-detail-complete.md §2.9, decision 199): the place and the
  // cover come off the booking first. The discovery list below holds OTHER
  // facts for the same salon, so a card that read the list first fails.
  group('A2 — the booking first', () {
    final listed = models.Provider.fromJson({
      'id': 'p1',
      'name': 'Salon de la liste',
      'description': 'd',
      'address': 'Adresse de la liste',
      'commune': 'Marcory',
      'city': 'Abidjan',
      'latitude': 1.0,
      'longitude': 1.0,
      'imageUrls': <String>['asset:assets/images/providers/beaute_divine.svg'],
      'rating': 0,
      'reviewCount': 0,
      'services': <Map<String, dynamic>>[],
      'artists': <Map<String, dynamic>>[],
      'availability': {
        'providerId': 'p1',
        'weeklySchedule': <String, dynamic>{},
        'blockedDates': <String>[],
        'bufferMinutes': 0,
      },
      'phoneNumber': '+2250700000001',
      'category': 'salon',
    });

    Widget seeded(Widget child) => wrapApp(
      providers: [
        ChangeNotifierProvider<ProviderProvider>(
          create: (_) => _Seeded([listed]),
        ),
      ],
      home: Scaffold(body: child),
    );

    Appointment booking({String? providerStatus, bool position = true}) =>
        appt().copyWith(
          providerName: 'Beauté Divine',
          providerStatus: providerStatus,
          providerCommune: 'Cocody',
          providerCity: 'Abidjan',
          providerLatitude: position ? 5.36 : null,
          providerLongitude: position ? -3.99 : null,
          providerPhotoUrl:
              'asset:assets/images/providers/barber_shop_pro_photo.png',
        );

    testWidgets('photo, place and « Itinéraire » from the booking', (
      tester,
    ) async {
      await tester.pumpWidget(
        seeded(AppointmentCard(appointment: booking(), onTap: () {})),
      );
      await tester.pump();
      final image = tester.widget<TimedCachedImage>(
        find.byType(TimedCachedImage),
      );
      expect(
        image.imageUrl,
        'asset:assets/images/providers/barber_shop_pro_photo.png',
      );
      expect(find.text('Cocody, Abidjan'), findsOneWidget);
      expect(find.text('Marcory, Abidjan'), findsNothing);
      expect(find.text('Itinéraire'), findsOneWidget);
      expect(_mapLink, findsOneWidget);
    });

    testWidgets('« Voir sur la carte » only for a live salon', (tester) async {
      await tester.pumpWidget(
        seeded(
          AppointmentCard(
            appointment: booking(providerStatus: 'suspended'),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      // The place stays, as text; the map, which 404s a stopped salon, goes.
      expect(find.text('Cocody, Abidjan'), findsOneWidget);
      expect(_mapLink, findsNothing);
      expect(find.text('Itinéraire'), findsOneWidget);
    });

    testWidgets('an older server: the discovery list is the fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        seeded(AppointmentCard(appointment: appt(), onTap: () {})),
      );
      await tester.pump();
      // The card's place before A2: the listed salon's city.
      expect(find.text('Abidjan'), findsOneWidget);
      expect(
        tester.widget<TimedCachedImage>(find.byType(TimedCachedImage)).imageUrl,
        'asset:assets/images/providers/beaute_divine.svg',
      );
    });

    testWidgets('« Réservé par votre salon » reads userId, not the name', (
      tester,
    ) async {
      final salonNoName = appt().copyWith(userId: 'manual');
      await tester.pumpWidget(
        wrap(AppointmentCard(appointment: salonNoName, onTap: () {})),
      );
      await tester.pump();
      expect(find.text('Réservé par votre salon'), findsOneWidget);
    });
  });
}

/// A discovery list already loaded with [_seed].
class _Seeded extends ProviderProvider {
  _Seeded(this._seed);
  final List<models.Provider> _seed;

  @override
  List<models.Provider> get providers => _seed;
}

/// The place line's map affordance, found by its own `Semantics` widget: the
/// card is one semantics container, so its inner labels merge into the card's.
final _mapLink = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Voir sur la carte',
);
