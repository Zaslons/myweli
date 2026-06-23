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
}
