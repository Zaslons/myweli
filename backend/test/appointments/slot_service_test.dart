import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/availability/index.dart' as availability;

class _MockRequestContext extends Mock implements RequestContext {}

/// Mon–Sun 09:00–18:00 in 30-minute openings — the seed shape, inline so these
/// fixtures never borrow the shared mutable `seedProviders`.
Map<String, dynamic> _openAvailability() {
  final slots = <Map<String, dynamic>>[];
  for (var m = 9 * 60; m < 18 * 60; m += 30) {
    final start = DateTime.utc(2024, 1, 1, m ~/ 60, m % 60);
    slots.add({
      'startTime': start.toIso8601String(),
      'endTime': start.add(const Duration(minutes: 30)).toIso8601String(),
      'isAvailable': true,
    });
  }
  return {
    'weeklySchedule': {for (var d = 0; d <= 6; d++) '$d': slots},
    'blockedDates': <String>[],
    'bufferMinutes': 0,
  };
}

/// A future weekday (Mon–Sat) in UTC, so the default seed schedule is open.
DateTime _openDate() {
  var d = DateTime.utc(
    DateTime.now().toUtc().year,
    DateTime.now().toUtc().month,
    DateTime.now().toUtc().day,
  ).add(const Duration(days: 7));
  while (d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

int _minuteOf(DateTime d) => d.hour * 60 + d.minute;

void main() {
  late InMemoryAppointmentRepository appts;
  late SlotService slots;
  final date = _openDate();
  final dateStr =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  setUp(() {
    appts = InMemoryAppointmentRepository();
    slots = SlotService(InMemoryProvidersRepository(), appts);
  });

  group('SlotService', () {
    test('open weekday yields 30-min slots within 09:00–18:00', () async {
      final res = await slots.availableSlots(
        providerId: 'provider1',
        date: date,
        durationMinutes: 30,
      );
      expect(res.ok, isTrue);
      expect(res.slots, isNotEmpty);
      expect(res.slots!.any((s) => _minuteOf(s) == 9 * 60), isTrue);
      for (final s in res.slots!) {
        expect(s.minute % 30, 0);
        expect(_minuteOf(s) >= 9 * 60 && _minuteOf(s) < 18 * 60, isTrue);
      }
    });

    test('a closed day (Sunday) has no slots', () async {
      var sunday = date;
      while (sunday.weekday != DateTime.sunday) {
        sunday = sunday.add(const Duration(days: 1));
      }
      final res = await slots.availableSlots(
        providerId: 'provider1',
        date: sunday,
        durationMinutes: 30,
      );
      expect(res.slots, isEmpty);
    });

    test(
      'duration must fit before close (120 min → last start 16:00)',
      () async {
        final res = await slots.availableSlots(
          providerId: 'provider1',
          date: date,
          durationMinutes: 120,
        );
        expect(res.slots, isNotEmpty);
        expect(
          res.slots!.map(_minuteOf).reduce((a, b) => a > b ? a : b),
          16 * 60,
        );
      },
    );

    test(
      'an existing booking (buffer-padded) removes overlapping starts',
      () async {
        await appts.create({
          'id': 'a1',
          'userId': 'u1',
          'providerId': 'provider1',
          'serviceIds': ['service2'], // 60 min
          'appointmentDate': date
              .add(const Duration(hours: 10))
              .toIso8601String(),
          'status': 'pending',
        });
        final res = await slots.availableSlots(
          providerId: 'provider1',
          date: date,
          durationMinutes: 30,
        );
        final minutes = res.slots!.map(_minuteOf).toSet();
        expect(minutes.contains(10 * 60), isFalse); // booked
        expect(minutes.contains(9 * 60), isTrue); // before the padded window
      },
    );

    test('blocked date → no slots', () async {
      final repo = InMemoryProvidersRepository([
        {
          'id': 'p',
          'name': 'X',
          'rating': 4.0,
          'category': 'salon',
          'services': const <Map<String, dynamic>>[],
          'availability': {
            'providerId': 'p',
            'weeklySchedule': {
              '${date.weekday - 1}': [
                {
                  'startTime': DateTime.utc(2024, 1, 1, 9).toIso8601String(),
                  'endTime': DateTime.utc(2024, 1, 1, 9, 30).toIso8601String(),
                  'isAvailable': true,
                },
              ],
            },
            'blockedDates': [date.toIso8601String()],
            'bufferMinutes': 0,
          },
        },
      ]);
      final res = await SlotService(
        repo,
        appts,
      ).availableSlots(providerId: 'p', date: date, durationMinutes: 30);
      expect(res.slots, isEmpty);
    });

    test('a break removes overlapping starts', () async {
      final repo = InMemoryProvidersRepository([
        {
          'id': 'p',
          'name': 'X',
          'rating': 4.0,
          'category': 'salon',
          'services': const <Map<String, dynamic>>[],
          'availability': {
            'providerId': 'p',
            'weeklySchedule': {
              '${date.weekday - 1}': [
                for (final h in [11, 12, 13])
                  for (final m in [0, 30])
                    {
                      'startTime': DateTime.utc(
                        2024,
                        1,
                        1,
                        h,
                        m,
                      ).toIso8601String(),
                      'endTime': DateTime.utc(
                        2024,
                        1,
                        1,
                        h,
                        m + 30,
                      ).toIso8601String(),
                      'isAvailable': true,
                    },
              ],
            },
            'blockedDates': const <String>[],
            'bufferMinutes': 0,
            'breaks': {
              '${date.weekday - 1}': [
                {
                  'startTime': DateTime.utc(2024, 1, 1, 12).toIso8601String(),
                  'endTime': DateTime.utc(2024, 1, 1, 13).toIso8601String(),
                  'isAvailable': false,
                },
              ],
            },
          },
        },
      ]);
      final res = await SlotService(
        repo,
        appts,
      ).availableSlots(providerId: 'p', date: date, durationMinutes: 30);
      final minutes = res.slots!.map(_minuteOf).toSet();
      expect(minutes.contains(12 * 60), isFalse); // in the break
      expect(minutes.contains(11 * 60), isTrue);
    });

    test('unknown provider → error', () async {
      expect(
        (await slots.availableSlots(providerId: 'nope', date: date)).error,
        'provider_not_found',
      );
    });
  });

  group('the closed browse (Decision C)', () {
    // Isolated fixtures, never the shared mutable `seedProviders`.
    InMemoryProvidersRepository salons() => InMemoryProvidersRepository([
      {
        'id': 'live',
        'name': 'Live',
        'services': <Map<String, dynamic>>[
          {'id': 's1', 'name': 'Coupe', 'durationMinutes': 30, 'price': 5000},
        ],
        'availability': _openAvailability(),
      },
      {
        'id': 'stopped',
        'name': 'Stopped',
        'status': 'suspended',
        'services': <Map<String, dynamic>>[
          {'id': 's1', 'name': 'Coupe', 'durationMinutes': 30, 'price': 5000},
        ],
        'availability': _openAvailability(),
      },
      {
        'id': 'unpublished',
        'name': 'Draft',
        'status': 'draft',
        'services': <Map<String, dynamic>>[
          {'id': 's1', 'name': 'Coupe', 'durationMinutes': 30, 'price': 5000},
        ],
        'availability': _openAvailability(),
      },
    ]);

    test('a hidden salon has no public slots, and says so as UNKNOWN', () async {
      // `provider_not_found` on purpose, NOT the precise state. This is the
      // only public door that takes an arbitrary providerId in a query string,
      // and its body already carries the failure code — so naming the state
      // would turn a one-valued channel into a three-valued one, which is the
      // enumeration oracle T51 exists to prevent. A caller who OWNS a booking
      // gets the precise code instead; they have a relationship, so there is
      // nothing to protect.
      final repo = salons();
      final svc = SlotService(repo, InMemoryAppointmentRepository());
      for (final id in ['stopped', 'unpublished']) {
        final r = await svc.availableSlots(providerId: id, date: _openDate());
        expect(r.ok, isFalse);
        expect(r.error, 'provider_not_found');
      }
      // The pair.
      final live = await svc.availableSlots(
        providerId: 'live',
        date: _openDate(),
      );
      expect(live.ok, isTrue);
      expect(live.slots, isNotEmpty);
    });

    test('the SALON still sees its own — Decision A', () async {
      // `rescheduleByProvider` reaches this engine through `_moveTo` and opts
      // out, because a draft salon owns its calendar. Same principle that
      // exempts `bookManual` from the engine entirely.
      final svc = SlotService(salons(), InMemoryAppointmentRepository());
      final r = await svc.availableSlots(
        providerId: 'unpublished',
        date: _openDate(),
        requireVisibleSalon: false,
      );
      expect(r.ok, isTrue);
      expect(r.slots, isNotEmpty);
    });
  });

  group('route', () {
    RequestContext ctx(Uri uri) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(Request.get(uri));
      when(() => context.read<SlotService>()).thenReturn(slots);
      return context;
    }

    test('GET returns slots', () async {
      final res = await availability.onRequest(
        ctx(
          Uri.parse(
            'http://localhost/availability?providerId=provider1&date=$dateStr',
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.ok);
      final body = await res.json() as Map<String, dynamic>;
      expect(body['slots'], isNotEmpty);
    });

    test('missing params → 400', () async {
      final res = await availability.onRequest(
        ctx(Uri.parse('http://localhost/availability?providerId=provider1')),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('unknown provider → 404', () async {
      final res = await availability.onRequest(
        ctx(
          Uri.parse(
            'http://localhost/availability?providerId=nope&date=$dateStr',
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('non-GET → 405', () async {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/availability'),
          body: jsonEncode(const {}),
        ),
      );
      when(() => context.read<SlotService>()).thenReturn(slots);
      expect(
        (await availability.onRequest(context)).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });
  });

  group('SlotService — per-artist capacity (booking-capacity-web-hub.md)', () {
    Map<String, dynamic> salonWithArtists({
      Map<String, dynamic>? awaHours,
      List<String> tressesArtists = const ['awa', 'binta'],
    }) => {
      'id': 'cap1',
      'name': 'Salon Capacité',
      'status': 'active',
      'services': [
        {
          'id': 's-tresses',
          'name': 'Tresses',
          'price': 10000,
          'durationMinutes': 60,
          'artistIds': tressesArtists,
          'active': true,
        },
        {
          'id': 's-soin',
          'name': 'Soin',
          'price': 5000,
          'durationMinutes': 30,
          'artistIds': <String>[], // unrestricted
          'active': true,
        },
      ],
      'artists': [
        {'id': 'awa', 'name': 'Awa', 'workingHours': awaHours ?? {}},
        {'id': 'binta', 'name': 'Binta', 'workingHours': <String, dynamic>{}},
      ],
      'availability': {
        'weeklySchedule': {
          for (var day = 0; day <= 5; day++)
            '$day': [
              for (var m = 9 * 60; m < 18 * 60; m += 30)
                {
                  'startTime': DateTime.utc(
                    2024,
                    1,
                    1,
                    m ~/ 60,
                    m % 60,
                  ).toIso8601String(),
                  'endTime': DateTime.utc(
                    2024,
                    1,
                    1,
                    m ~/ 60,
                    m % 60,
                  ).add(const Duration(minutes: 30)).toIso8601String(),
                  'isAvailable': true,
                },
            ],
        },
        'blockedDates': <String>[],
        'bufferMinutes': 0,
      },
      'cancellationWindowHours': 24,
    };

    late SlotService capSlots;

    Future<void> seedBooking({
      required String id,
      String? artistId,
      required int hour,
      int minutes = 60,
      String status = 'confirmed',
    }) => appts.create({
      'id': id,
      'userId': 'u1',
      'providerId': 'cap1',
      'serviceIds': ['s-tresses'],
      'artistId': artistId,
      'appointmentDate': DateTime.utc(
        date.year,
        date.month,
        date.day,
        hour,
      ).toIso8601String(),
      'durationMinutes': minutes,
      'status': status,
      'totalPrice': 10000,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    });

    SlotService build([Map<String, dynamic>? salon]) => SlotService(
      InMemoryProvidersRepository([salon ?? salonWithArtists()]),
      appts,
    );

    bool has(SlotResult r, int hour) =>
        (r.slots ?? const []).any((s) => _minuteOf(s) == hour * 60);

    test('one artist busy → their slot is gone, the other + « Sans '
        'préférence » stay', () async {
      capSlots = build();
      await seedBooking(id: 'b1', artistId: 'awa', hour: 10);

      final awa = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'awa',
      );
      expect(has(awa, 10), isFalse);

      final binta = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'binta',
      );
      expect(has(binta, 10), isTrue);

      final anyone = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
      );
      expect(has(anyone, 10), isTrue); // one chair left
    });

    test(
      'ALL chairs busy → « Sans préférence » is NOT bookable either',
      () async {
        capSlots = build();
        await seedBooking(id: 'b1', artistId: 'awa', hour: 10);
        await seedBooking(id: 'b2', artistId: 'binta', hour: 10);

        final anyone = await capSlots.availableSlots(
          providerId: 'cap1',
          date: date,
          serviceIds: ['s-tresses'],
        );
        expect(has(anyone, 10), isFalse);
        expect(has(anyone, 14), isTrue); // the rest of the day stays open
      },
    );

    test('an UNASSIGNED booking consumes one chair from the pool', () async {
      capSlots = build();
      await seedBooking(id: 'b1', artistId: null, hour: 10);

      // One chair left → still bookable for anyone…
      final anyone = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
      );
      expect(has(anyone, 10), isTrue);

      // …but a second unassigned exhausts the pool.
      await seedBooking(id: 'b2', artistId: null, hour: 10);
      final full = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
      );
      expect(has(full, 10), isFalse);

      // And a specific artist is blocked too — the unassigned bookings need
      // both chairs.
      final awa = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'awa',
      );
      expect(has(awa, 10), isFalse);
    });

    test('capability: a service restricted to Awa never books Binta', () async {
      capSlots = build(salonWithArtists(tressesArtists: ['awa']));
      final binta = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'binta',
      );
      expect(binta.slots, isEmpty);

      // Pool for « Sans préférence » = only Awa → one assigned booking on
      // Awa kills the slot.
      await seedBooking(id: 'b1', artistId: 'awa', hour: 10);
      final anyone = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
      );
      expect(has(anyone, 10), isFalse);
    });

    test('artist working hours constrain THEIR slots (others inherit salon '
        'hours)', () async {
      // Awa works only 14:00–18:00 on every day the salon opens.
      final afternoon = {
        for (var day = 0; day <= 5; day++)
          '$day': [
            {
              'startTime': DateTime.utc(2024, 1, 1, 14).toIso8601String(),
              'endTime': DateTime.utc(2024, 1, 1, 18).toIso8601String(),
              'isAvailable': true,
            },
          ],
      };
      capSlots = build(salonWithArtists(awaHours: afternoon));

      final awa = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'awa',
      );
      expect(has(awa, 10), isFalse); // outside her hours
      expect(has(awa, 14), isTrue);

      final binta = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        serviceIds: ['s-tresses'],
        artistId: 'binta',
      );
      expect(has(binta, 10), isTrue); // inherits salon hours
    });

    test('unknown artist → invalid_artist', () async {
      capSlots = build();
      final r = await capSlots.availableSlots(
        providerId: 'cap1',
        date: date,
        artistId: 'ghost',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_artist');
    });
  });

  // ---- A14d — the bookable window (§21 row 76) ---------------------------
  //
  // Two ends, one setting. Before A14d neither was a rule: the far end existed
  // only as a client-side literal, and the near end as a bare `60` inside the
  // slot loop with no constant, no setting and no test. These are the first
  // assertions either end has ever had — including the pre-existing 1h notice,
  // which shipped untested and is pinned here beside its replacement.
  group('A14d — the bookable window', () {
    /// A salon open 09:00–18:00 every weekday, with the given window.
    InMemoryProvidersRepository repoWith({
      int? horizonDays,
      int? noticeMinutes,
    }) => InMemoryProvidersRepository([
      {
        'id': 'p',
        'name': 'X',
        'rating': 4.0,
        'category': 'salon',
        'services': const <Map<String, dynamic>>[],
        'availability': {
          'providerId': 'p',
          'weeklySchedule': {
            for (var wd = 0; wd < 7; wd++)
              '$wd': [
                for (var h = 9; h < 18; h++) ...[
                  {
                    'startTime': DateTime.utc(2024, 1, 1, h).toIso8601String(),
                    'endTime': DateTime.utc(
                      2024,
                      1,
                      1,
                      h,
                      30,
                    ).toIso8601String(),
                    'isAvailable': true,
                  },
                ],
              ],
          },
          'blockedDates': const <String>[],
          'bufferMinutes': 0,
          if (horizonDays != null) 'bookingHorizonDays': horizonDays,
          if (noticeMinutes != null) 'minimumNoticeMinutes': noticeMinutes,
        },
      },
    ]);

    DateTime dayAhead(int days) {
      final now = DateTime.now().toUtc();
      return DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: days));
    }

    test('beyond the horizon → no slots, and it is NOT an error', () async {
      final svc = SlotService(repoWith(horizonDays: 30), appts);

      final inside = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(20),
        durationMinutes: 30,
      );
      expect(
        inside.slots,
        isNotEmpty,
        reason:
            'the control — without this the assertion below passes for a '
            'salon that is simply never open',
      );

      final outside = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(40),
        durationMinutes: 30,
      );
      expect(outside.slots, isEmpty);
      // The shape matters as much as the emptiness. Its three siblings — past
      // day, blocked date, closed weekday — all return (ok: true, error: null),
      // and the PUBLIC browse route maps ANY error to 404
      // (`routes/availability/index.dart`: anything but invalid_artist becomes
      // notFound). A new error code here would answer 404 « beyond_horizon » on
      // browse, something else on book and something else again on reschedule
      // — one condition, three statuses.
      expect(outside.ok, isTrue);
      expect(outside.error, isNull);
    });

    test('the horizon is per-salon, and defaults to 365 when unset', () async {
      final svc = SlotService(repoWith(), appts);
      final far = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(300),
        durationMinutes: 30,
      );
      expect(far.slots, isNotEmpty, reason: 'inside the 365-day default');

      final tooFar = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(400),
        durationMinutes: 30,
      );
      expect(tooFar.slots, isEmpty, reason: 'past it');
    });

    test('a notice longer than a day reaches into FUTURE days', () async {
      // This is the assertion the old structure could not express. The rule
      // was « for today, only offer starts ≥ 1h from now », computed as
      // minutes past salon midnight and set to -1 on every other day — so a
      // salon requiring 48h could not exclude tomorrow, because the branch
      // that would do it did not exist. A14d replaces it with one absolute
      // instant (now + notice) compared against each slot's absolute start.
      final svc = SlotService(repoWith(noticeMinutes: 48 * 60), appts);

      final tomorrow = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(1),
        durationMinutes: 30,
      );
      expect(tomorrow.slots, isEmpty, reason: 'inside a 48-hour notice');

      final later = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(4),
        durationMinutes: 30,
      );
      expect(later.slots, isNotEmpty, reason: 'past it');
    });

    test('the default 1h notice still behaves exactly as it did', () async {
      // The literal this replaces had no test in its entire life. Pinning it
      // is how we know the restructure preserved it rather than merely
      // compiled.
      final svc = SlotService(repoWith(), appts);
      final today = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(0),
        durationMinutes: 30,
      );
      final now = DateTime.now().toUtc();
      for (final s in today.slots!) {
        expect(
          s.isAfter(now.add(const Duration(minutes: 59))),
          isTrue,
          reason: 'every offered start is at least an hour out: $s',
        );
      }
    });

    test('the salon is exempt — enforceBookingWindow: false', () async {
      // The window is a CLIENT-facing rule. `bookManual` was already exempt by
      // never reaching the slot engine; the salon's own reschedule reaches it
      // through the shared `_moveTo`, so without this flag a salon could not
      // move a booking past its own horizon — which contradicts the principle
      // that exempts manual booking in the first place.
      final svc = SlotService(
        repoWith(horizonDays: 30, noticeMinutes: 48 * 60),
        appts,
      );

      final asClient = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(40),
        durationMinutes: 30,
      );
      expect(asClient.slots, isEmpty);

      final asSalon = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(40),
        durationMinutes: 30,
        enforceBookingWindow: false,
      );
      expect(asSalon.slots, isNotEmpty, reason: 'the salon owns its calendar');

      // The near end is exempt too, or a salon could not squeeze in a client
      // who walked through the door.
      final soon = await svc.availableSlots(
        providerId: 'p',
        date: dayAhead(1),
        durationMinutes: 30,
        enforceBookingWindow: false,
      );
      expect(soon.slots, isNotEmpty);
    });
  });

  group('the weekly template is a set of RANGES', () {
    test('ONE open window is a range, not a single bookable minute', () async {
      // Found on a device, pro → server → consumer, and it is the defect the
      // A14 device run existed to catch: `_openMinutes` read each template
      // entry's `startTime` and threw its `endTime` away. That convention only
      // works if `weeklySchedule` holds one entry per 30-minute step — which is
      // what `seedProviders` holds and what **no real salon can have**.
      // `draftSalonDocument` gives a fresh registration an EMPTY
      // `weeklySchedule`, so every real salon authors its hours in the pro
      // app's day editor, and « 09:00 – 18:00 » is ONE entry there. Nine open
      // hours therefore offered one bookable start, and anything longer than
      // the step had nowhere to go at all: the client saw « Aucun créneau ce
      // jour-là » on every open day with no error on either side.
      //
      // Measured before the fix, same salon / same service / same day: ONE
      // 09:00–18:00 entry → **0** slots for a 60-minute service and exactly
      // **1** (09:00) for a 30-minute one; a split day (09:00–12:00 +
      // 14:00–18:00), the most ordinary schedule there is, → **2** and **0**;
      // eighteen half-hour entries → **18** and **17**, which the fix leaves
      // untouched. The 30-minute column is the tell — the end was not read at
      // all. The same file already read the same shape correctly twice, for
      // breaks and for an artist's own hours; only the salon's opening hours
      // did not.
      final repo = InMemoryProvidersRepository([
        {
          'id': 'p',
          'name': 'X',
          'rating': 4.0,
          'category': 'salon',
          'services': const <Map<String, dynamic>>[],
          'availability': {
            'providerId': 'p',
            'weeklySchedule': {
              '${date.weekday - 1}': [
                {
                  'startTime': DateTime.utc(2024, 1, 1, 9).toIso8601String(),
                  'endTime': DateTime.utc(2024, 1, 1, 18).toIso8601String(),
                  'isAvailable': true,
                },
              ],
            },
            'blockedDates': const <String>[],
            'bufferMinutes': 0,
          },
        },
      ]);
      final svc = SlotService(repo, appts);

      final short = await svc.availableSlots(
        providerId: 'p',
        date: date,
        durationMinutes: 30,
      );
      expect(
        short.slots!.map(_minuteOf),
        [for (var m = 9 * 60; m < 18 * 60; m += 30) m],
        reason: 'nine open hours are eighteen half-hour starts, not one',
      );

      final long = await svc.availableSlots(
        providerId: 'p',
        date: date,
        durationMinutes: 60,
      );
      expect(
        long.slots!.map(_minuteOf),
        [for (var m = 9 * 60; m <= 17 * 60; m += 30) m],
        reason:
            'a 60-minute service needs two consecutive open steps, and the '
            'last one it can start on is 17:00 — not zero of them',
      );
    });

    test(
      'an entry shorter than the step still yields exactly its start',
      () async {
        // The other half of the pair, and it is what stops the fix from becoming
        // « every day is open all day ». The demo seed's eighteen half-hour
        // entries must keep meaning eighteen starts, and a salon that expresses
        // « 09:00 and 14:00 only » as two 30-minute entries must still get two.
        final repo = InMemoryProvidersRepository([
          {
            'id': 'p',
            'name': 'X',
            'rating': 4.0,
            'category': 'salon',
            'services': const <Map<String, dynamic>>[],
            'availability': {
              'providerId': 'p',
              'weeklySchedule': {
                '${date.weekday - 1}': [
                  for (final h in [9, 14])
                    {
                      'startTime': DateTime.utc(
                        2024,
                        1,
                        1,
                        h,
                      ).toIso8601String(),
                      'endTime': DateTime.utc(
                        2024,
                        1,
                        1,
                        h,
                        30,
                      ).toIso8601String(),
                      'isAvailable': true,
                    },
                ],
              },
              'blockedDates': const <String>[],
              'bufferMinutes': 0,
            },
          },
        ]);
        final res = await SlotService(
          repo,
          appts,
        ).availableSlots(providerId: 'p', date: date, durationMinutes: 30);
        expect(res.slots!.map(_minuteOf), [9 * 60, 14 * 60]);
      },
    );
  });
}
