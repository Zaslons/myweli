import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/cancel.dart' as cancel_route;
import '../../routes/appointments/[id]/reschedule.dart' as reschedule_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockNotifier extends Mock implements BookingNotifier {}

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
  setUpAll(() => registerFallbackValue(MessageTemplate.bookingConfirmed));
  late InMemoryAppointmentRepository appts;
  late AppointmentLifecycleService lifecycle;
  late InMemoryProviderAuthRepository providerAuth;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;
  // Provider tokens: pro1 manages provider1 (owns the seeded bookings); pro2
  // manages provider2 (cross-salon).
  late String proAccess1;
  late String proAccess2;

  setUp(() async {
    final providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    lifecycle = AppointmentLifecycleService(
      appts,
      SlotService(providers, appts),
    );
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    final pro1 = await providerAuth.register(
      email: 'reg16@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-16',
      phoneNumber: '+2250500000050',
      businessName: 'Salon 1',
      businessType: 'salon',
      providerId: 'provider1',
    );
    final pro2 = await providerAuth.register(
      email: 'reg17@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-17',
      phoneNumber: '+2250500000051',
      businessName: 'Salon 2',
      businessType: 'salon',
      providerId: 'provider2',
    );
    proAccess1 = tokens
        .issueAccessToken(subject: pro1.provider!.id, role: 'provider')
        .token;
    proAccess2 = tokens
        .issueAccessToken(subject: pro2.provider!.id, role: 'provider')
        .token;
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

    test(
      'rescheduleByProvider: salon ownership + state + slot guards',
      () async {
        final id = await seedFor('user_A'); // provider1's booking
        final newDate = _slotAt(10);

        // Owning salon moves it; deposit carries over.
        final r = await lifecycle.rescheduleByProvider(
          id,
          'provider1',
          newDate,
        );
        expect(r.ok, isTrue);
        expect(r.appointment!['appointmentDate'], newDate.toIso8601String());
        expect(r.appointment!['depositAmount'], 6000);

        // Another salon cannot move it.
        expect(
          (await lifecycle.rescheduleByProvider(
            id,
            'provider2',
            _slotAt(11),
          )).error,
          'forbidden',
        );
        // Off-grid time → slot_unavailable.
        expect(
          (await lifecycle.rescheduleByProvider(
            id,
            'provider1',
            _slotAt(10).add(const Duration(minutes: 15)),
          )).error,
          'slot_unavailable',
        );
        // Terminal → invalid_state.
        await lifecycle.cancel(id, 'user_A');
        expect(
          (await lifecycle.rescheduleByProvider(
            id,
            'provider1',
            _slotAt(12),
          )).error,
          'invalid_state',
        );
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
      when(
        () => context.read<ProviderAuthRepository>(),
      ).thenReturn(providerAuth);
      final notifier = _MockNotifier();
      when(() => notifier.notify(any(), any())).thenAnswer((_) async {});
      when(() => context.read<BookingNotifier>()).thenReturn(notifier);
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

    test(
      'reschedule (provider): owning salon → 200; cross-salon → 403',
      () async {
        final id = await seedFor('user_A'); // provider1's booking
        final newDate = _slotAt(10).toIso8601String();

        final owner = await reschedule_route.onRequest(
          ctx(
            post('/appointments/$id/reschedule', proAccess1, {
              'newDateTime': newDate,
            }),
          ),
          id,
        );
        expect(owner.statusCode, HttpStatus.ok);
        expect((await owner.json() as Map)['appointmentDate'], newDate);

        final cross = await reschedule_route.onRequest(
          ctx(
            post('/appointments/$id/reschedule', proAccess2, {
              'newDateTime': _slotAt(11).toIso8601String(),
            }),
          ),
          id,
        );
        expect(cross.statusCode, HttpStatus.forbidden);
      },
    );

    test('cancel on a missing appointment → 404', () async {
      final res = await cancel_route.onRequest(
        ctx(post('/appointments/nope/cancel', accessA)),
        'nope',
      );
      expect(res.statusCode, HttpStatus.notFound);
    });
  });
}
