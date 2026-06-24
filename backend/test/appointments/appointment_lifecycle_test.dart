import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/cancel.dart' as cancel_route;
import '../../routes/appointments/[id]/reschedule.dart' as reschedule_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// A future Mon–Sat at 09:00 UTC — an open slot in the seed schedule.
DateTime _slotAt(int hour) {
  final now = DateTime.now().toUtc();
  var d = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 7));
  while (d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return DateTime.utc(d.year, d.month, d.day, hour);
}

void main() {
  late InMemoryAppointmentRepository appts;
  late AppointmentLifecycleService lifecycle;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;

  setUp(() {
    final providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    lifecycle = AppointmentLifecycleService(
      appts,
      SlotService(providers, appts),
    );
  });

  Future<String> seedFor(String userId, {String status = 'pending'}) async {
    final created = await appts.create({
      'id': 'appt_${DateTime.now().microsecondsSinceEpoch}',
      'userId': userId,
      'providerId': 'provider1',
      'serviceIds': ['service1'],
      'appointmentDate': DateTime.now()
          .toUtc()
          .add(const Duration(days: 3))
          .toIso8601String(),
      'status': status,
      'depositAmount': 6000,
      'balanceDue': 9000,
    });
    return created!['id'] as String;
  }

  group('AppointmentLifecycleService', () {
    test(
      'cancel sets status; reschedule moves the date (deposit carries)',
      () async {
        final id = await seedFor('user_A');
        final newDate = _slotAt(9);

        final r = await lifecycle.reschedule(id, 'user_A', newDate);
        expect(r.ok, isTrue);
        expect(r.appointment!['appointmentDate'], newDate.toIso8601String());
        expect(r.appointment!['depositAmount'], 6000); // unchanged

        final c = await lifecycle.cancel(id, 'user_A');
        expect(c.ok, isTrue);
        expect(c.appointment!['status'], 'cancelled');
      },
    );

    test('ownership + state guards', () async {
      final id = await seedFor('user_A');
      expect((await lifecycle.cancel(id, 'user_B')).error, 'forbidden');
      expect((await lifecycle.cancel('nope', 'user_A')).error, 'not_found');

      await lifecycle.cancel(id, 'user_A');
      // Already cancelled → terminal.
      expect((await lifecycle.cancel(id, 'user_A')).error, 'invalid_state');
      expect(
        (await lifecycle.reschedule(id, 'user_A', DateTime.now())).error,
        'invalid_state',
      );
    });

    test(
      'reschedule rejects an unavailable new time → slot_unavailable',
      () async {
        final id = await seedFor('user_A');
        // 09:15 is not an aligned opening slot.
        final res = await lifecycle.reschedule(
          id,
          'user_A',
          _slotAt(9).add(const Duration(minutes: 15)),
        );
        expect(res.error, 'slot_unavailable');
      },
    );
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(
        () => context.read<AppointmentLifecycleService>(),
      ).thenReturn(lifecycle);
      return context;
    }

    Request post(String path, String token, [Object? body]) => Request.post(
      Uri.parse('http://localhost$path'),
      headers: {'Authorization': 'Bearer $token'},
      body: jsonEncode(body ?? const {}),
    );

    test(
      'cancel: 401 without token; 403 for another user; 200 for owner',
      () async {
        final id = await seedFor('user_A');

        final noAuth = await cancel_route.onRequest(
          ctx(
            Request.post(Uri.parse('http://localhost/appointments/$id/cancel')),
          ),
          id,
        );
        expect(noAuth.statusCode, HttpStatus.unauthorized);

        final other = await cancel_route.onRequest(
          ctx(post('/appointments/$id/cancel', accessB)),
          id,
        );
        expect(other.statusCode, HttpStatus.forbidden);

        final owner = await cancel_route.onRequest(
          ctx(post('/appointments/$id/cancel', accessA)),
          id,
        );
        expect(owner.statusCode, HttpStatus.ok);
        expect((await owner.json() as Map)['status'], 'cancelled');
      },
    );

    test('reschedule: 200 moves the date; bad body → 400', () async {
      final id = await seedFor('user_A');
      final newDate = _slotAt(9).toIso8601String();

      final ok = await reschedule_route.onRequest(
        ctx(
          post('/appointments/$id/reschedule', accessA, {
            'newDateTime': newDate,
          }),
        ),
        id,
      );
      expect(ok.statusCode, HttpStatus.ok);
      expect((await ok.json() as Map)['appointmentDate'], newDate);

      final bad = await reschedule_route.onRequest(
        ctx(post('/appointments/$id/reschedule', accessA, {'nope': 1})),
        id,
      );
      expect(bad.statusCode, HttpStatus.badRequest);
    });

    test('cancel on a missing appointment → 404', () async {
      final res = await cancel_route.onRequest(
        ctx(post('/appointments/nope/cancel', accessA)),
        'nope',
      );
      expect(res.statusCode, HttpStatus.notFound);
    });
  });
}
