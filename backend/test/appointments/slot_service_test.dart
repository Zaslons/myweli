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
}
