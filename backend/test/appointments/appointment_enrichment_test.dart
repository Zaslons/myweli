import 'package:myweli_backend/src/appointments/appointment_enrichment.dart';
import 'package:myweli_backend/src/appointments/booking_window.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The relationship lives on the server, so the server hydrates it
/// (`salon-state-and-refusals.md` §5, Decision C).
///
/// **What this replaces.** A consumer appointment carried a `providerId` and
/// nothing else about the salon, so both clients made a SECOND call to the
/// public `GET /providers/{id}` to render a booking card — web fanned out one
/// request per distinct salon in `bff.ts`, mobile made six from a single
/// screen. That second call is the thing Decision C closes. Everything those
/// fetches were for now rides the appointment the client already owns.
///
/// **The assertion this file exists for is the draft one.** Every other test
/// here would pass on an implementation that filtered hidden salons out of the
/// enrichment — and that implementation would reintroduce, one layer down,
/// exactly the silent degradation the closure is supposed to end.
void main() {
  Map<String, dynamic> salon({String? status}) => {
    'id': 'p1',
    'slug': 'salon-test',
    'name': 'Salon Test',
    if (status != null) 'status': status,
    'address': 'Rue des Jardins, Cocody',
    'phoneNumber': '+2250711223344',
    'whatsapp': '+2250711223355',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
    'depositMobileMoneyOperator': 'wave',
    'depositMobileMoneyNumber': '+2250700000000',
    'services': [
      {'id': 's1', 'name': 'Tresses', 'durationMinutes': 180},
      {'id': 's2', 'name': 'Soin du visage', 'durationMinutes': 45},
    ],
    'artists': [
      {'id': 'a1', 'name': 'Awa'},
      {'id': 'a2', 'name': 'Fatou'},
    ],
    'availability': {'bookingHorizonDays': 30, 'minimumNoticeMinutes': 120},
  };

  Map<String, dynamic> appointment({List<String>? serviceIds}) => {
    'id': 'appt1',
    'providerId': 'p1',
    'artistId': 'a1',
    'serviceIds': serviceIds ?? ['s1', 's2'],
    'status': 'confirmed',
  };

  Future<Map<String, dynamic>> enrichOne(
    Map<String, dynamic> a,
    Map<String, dynamic> p,
  ) async {
    final out = await withProviderFacts(InMemoryProvidersRepository([p]), [a]);
    return out.single;
  }

  group('the salon facts a booking card needs', () {
    test(
      'identity, contact, address and the deposit coordinates land',
      () async {
        final e = await enrichOne(appointment(), salon(status: 'active'));

        expect(e['providerName'], 'Salon Test');
        expect(e['providerSlug'], 'salon-test');
        expect(e['providerAddress'], 'Rue des Jardins, Cocody');
        expect(e['providerPhone'], '+2250711223344');
        expect(e['providerWhatsapp'], '+2250711223355');
        expect(e['providerCountryCode'], 'CI');
        // The worst of the degradations this replaces: a pay-later client at a
        // salon the public read no longer serves could not see where to send the
        // deposit, on the one screen whose whole job is collecting it.
        expect(e['depositMobileMoneyOperator'], 'wave');
        expect(e['depositMobileMoneyNumber'], '+2250700000000');
      },
    );

    test('the market fields MP1 already stamped are still there', () async {
      // This function used to be `withProviderMarket` and did only these two.
      // Losing them while adding eleven others is the obvious way to break it.
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e['providerTimezone'], 'Africa/Abidjan');
      expect(e['providerCurrency'], 'XOF');
    });

    test('names are resolved from ids — the client has no catalogue', () async {
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e['artistName'], 'Awa');
      expect(e['serviceNames'], ['Tresses', 'Soin du visage']);
    });

    test('an unknown id resolves to nothing rather than a hole', () async {
      final e = await enrichOne({
        ...appointment(serviceIds: ['s1', 'gone']),
        'artistId': 'gone',
      }, salon(status: 'active'));
      expect(e['artistName'], isNull);
      // Not `[Tresses, null]` — a deleted service must not put a null into an
      // array both clients render with a join.
      expect(e['serviceNames'], ['Tresses']);
    });

    test('no artist chosen is null, not the first one on the roster', () async {
      final e = await enrichOne({
        ...appointment(),
        'artistId': null,
      }, salon(status: 'active'));
      expect(e['artistName'], isNull);
    });
  });

  group('the booking window rides the appointment', () {
    test("the salon's own numbers, not the defaults", () async {
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e['providerBookingHorizonDays'], 30);
      expect(e['providerMinimumNoticeMinutes'], 120);
    });

    test('a salon that set neither gets the documented defaults', () async {
      // The pair. Without it the two assertions above pass on an
      // implementation that always returns the salon's value AND on one that
      // always returns null — and the client would then quietly show a
      // year-wide date picker for a salon that books two weeks out.
      final p = salon(status: 'active')..remove('availability');
      final e = await enrichOne(appointment(), p);
      expect(e['providerBookingHorizonDays'], kDefaultBookingHorizonDays);
      expect(e['providerMinimumNoticeMinutes'], kDefaultMinimumNoticeMinutes);
    });
  });

  group('durationMinutes is backfilled from the catalogue', () {
    test('a consumer payload without one gets the real length', () async {
      // `reschedule_screen.dart` required the whole salon object for exactly
      // this: a 3-hour braid whose duration was null got offered 30-minute
      // slots. The catalogue that priced the booking is the only correct
      // source, and the server is holding it already.
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e['durationMinutes'], 225);
    });

    test('a stored duration is never overwritten', () async {
      // The pair, and the more important half: the booking was priced at a
      // length, and a service edited since must not retroactively move an
      // existing appointment.
      final e = await enrichOne({
        ...appointment(),
        'durationMinutes': 90,
      }, salon(status: 'active'));
      expect(e['durationMinutes'], 90);
    });
  });

  group('the status is the point', () {
    test('a DRAFT salon still enriches, in full', () async {
      // THE assertion. A consumer holding a booking at a salon that is not
      // published keeps the salon's identity, contact and deposit handle —
      // that is the whole product answer to « how does a consumer's own
      // appointment keep resolving a salon they have a relationship with ».
      final e = await enrichOne(appointment(), salon(status: 'draft'));
      expect(e['providerStatus'], 'draft');
      expect(e['providerName'], 'Salon Test');
      expect(e['providerPhone'], '+2250711223344');
      expect(e['depositMobileMoneyNumber'], '+2250700000000');
    });

    test('a SUSPENDED salon does too', () async {
      final e = await enrichOne(appointment(), salon(status: 'suspended'));
      expect(e['providerStatus'], 'suspended');
      expect(e['providerName'], 'Salon Test');
    });

    test('a salon with no status key reads as active, not as null', () async {
      // The NULL trap, resolved once on the server. If this crossed the wire
      // as null, every client would invent a default and one of them would
      // spell it `?? 'draft'` — hiding « Réserver à nouveau » on every seeded
      // salon in the country.
      final e = await enrichOne(appointment(), salon());
      expect(e['providerStatus'], 'active');
    });
  });

  group('what it must not do', () {
    test('the public document does not ride along wholesale', () async {
      // The allowlist rule (T51): this runs on every consumer appointment
      // read, so anything on it is disclosed to anyone holding a booking at
      // that salon. Resolve to the two arrays the surfaces render; never ship
      // the catalogue, the roster or the gallery.
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e.containsKey('services'), isFalse);
      expect(e.containsKey('artists'), isFalse);
      expect(e.containsKey('imageUrls'), isFalse);
      expect(e.containsKey('reviews'), isFalse);
      expect(e.containsKey('availability'), isFalse);
    });

    test('a salon that has vanished leaves nulls, never throws', () async {
      final out = await withProviderFacts(
        InMemoryProvidersRepository([salon(status: 'active')]),
        [
          {...appointment(), 'providerId': 'gone'},
        ],
      );
      expect(out.single['providerName'], isNull);
      expect(out.single['providerStatus'], isNull);
      // Even here the window must be usable — a null horizon would open the
      // picker to whatever the client defaults to.
      expect(
        out.single['providerBookingHorizonDays'],
        kDefaultBookingHorizonDays,
      );
    });

    test('the appointment’s own fields survive', () async {
      final e = await enrichOne(appointment(), salon(status: 'active'));
      expect(e['id'], 'appt1');
      expect(e['status'], 'confirmed');
      expect(e['serviceIds'], ['s1', 's2']);
    });
  });

  test('one repository read per distinct salon, not per appointment', () async {
    // `byIds` exists so the favourites hydration does not move an N+1 INTO the
    // backend; the enrichment gets the same benefit for free. A list of ten
    // bookings across two salons must cost two lookups.
    final repo = _CountingRepository([salon(status: 'active')]);
    await withProviderFacts(repo, [
      for (var i = 0; i < 10; i++) {...appointment(), 'id': 'appt$i'},
    ]);
    expect(repo.lookups, 1);
  });
}

class _CountingRepository extends InMemoryProvidersRepository {
  _CountingRepository(super.seed);

  int lookups = 0;

  @override
  Future<Map<String, dynamic>?> byId(String id) {
    lookups++;
    return super.byId(id);
  }

  @override
  Future<List<Map<String, dynamic>>> byIds(List<String> ids) {
    lookups++;
    return super.byIds(ids);
  }
}
