import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/appointments.dart' as manual;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late BookingService booking;
  late InMemoryProviderAuthRepository providerAuth;
  final tokens = TokenService(secret: 'test-secret');
  late String token; // provider linked to provider1
  final at = DateTime.utc(2030, 6, 25, 9);

  setUp(() async {
    providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    booking = BookingService(providers, appts, SlotService(providers, appts));
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    final reg = await providerAuth.register(
      email: 'reg6@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-6',
      phoneNumber: '+2250500000030',
      businessName: 'X',
      businessType: 'salon',
      providerId: 'provider1',
    );
    token = tokens
        .issueAccessToken(subject: reg.provider!.id, role: 'provider')
        .token;
  });

  group('BookingService.bookManual', () {
    test(
      'creates a confirmed, deposit-free walk-in with client details',
      () async {
        final r = await booking.bookManual(
          providerId: 'provider1',
          serviceIds: const ['service1'],
          appointmentDateTime: at,
          clientName: 'Awa',
          clientPhone: '+2250700000000',
        );
        expect(r.ok, isTrue);
        final a = r.appointment!;
        expect(a['status'], 'confirmed');
        expect(a['userId'], 'manual');
        expect(a['depositAmount'], 0);
        expect(a['balanceDue'], a['totalPrice']);
        expect((a['totalPrice'] as num) > 0, isTrue); // server-priced
        expect(a['clientName'], 'Awa');
        expect(a['clientPhone'], '+2250700000000');
      },
    );

    test(
      'a future date is allowed (phone booking) and lands in the list',
      () async {
        final future = DateTime.now().toUtc().add(const Duration(days: 7));
        final r = await booking.bookManual(
          providerId: 'provider1',
          serviceIds: const ['service1'],
          appointmentDateTime: future,
        );
        expect(r.ok, isTrue);
        expect(
          (await appts.listForProvider('provider1')).single['status'],
          'confirmed',
        );
      },
    );

    test('unknown / empty services are rejected', () async {
      expect(
        (await booking.bookManual(
          providerId: 'provider1',
          serviceIds: const ['nope'],
          appointmentDateTime: at,
        )).error,
        'invalid_service',
      );
      expect(
        (await booking.bookManual(
          providerId: 'provider1',
          serviceIds: const [],
          appointmentDateTime: at,
        )).error,
        'no_services',
      );
    });
  });

  group('route POST /providers/{id}/appointments', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<BookingService>()).thenReturn(booking);
      when(
        () => context.read<ProviderAuthRepository>(),
      ).thenReturn(providerAuth);
      when(() => context.read<MembershipService>()).thenReturn(
        MembershipService(InMemoryMembershipRepository(), providerAuth),
      );
      return context;
    }

    Request post(String path, {String? bearer, Object? body}) => Request.post(
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : jsonEncode(body),
    );

    Future<Map<String, dynamic>> jsonOf(Response r) async =>
        await r.json() as Map<String, dynamic>;

    Map<String, Object?> validBody() => {
      'serviceIds': ['service1'],
      'appointmentDateTime': at.toIso8601String(),
      'clientName': 'Awa',
      'clientPhone': '+2250700000000',
    };

    test('valid manual booking → 201 confirmed', () async {
      final res = await manual.onRequest(
        ctx(
          post(
            '/providers/provider1/appointments',
            bearer: token,
            body: validBody(),
          ),
        ),
        'provider1',
      );
      expect(res.statusCode, HttpStatus.created);
      expect((await jsonOf(res))['status'], 'confirmed');
    });

    test('no token → 401; cross-salon → 403; GET → 405', () async {
      expect(
        (await manual.onRequest(
          ctx(post('/providers/provider1/appointments', body: validBody())),
          'provider1',
        )).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await manual.onRequest(
          ctx(
            post(
              '/providers/provider2/appointments',
              bearer: token,
              body: validBody(),
            ),
          ),
          'provider2',
        )).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await manual.onRequest(
          ctx(
            Request.get(
              Uri.parse('http://localhost/providers/provider1/appointments'),
              headers: {'Authorization': 'Bearer $token'},
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });

    test('missing services → 400; bad phone → 400', () async {
      final noServices = await manual.onRequest(
        ctx(
          post(
            '/providers/provider1/appointments',
            bearer: token,
            body: {'appointmentDateTime': at.toIso8601String()},
          ),
        ),
        'provider1',
      );
      expect(noServices.statusCode, HttpStatus.badRequest);

      final badPhone = await manual.onRequest(
        ctx(
          post(
            '/providers/provider1/appointments',
            bearer: token,
            body: {...validBody(), 'clientPhone': 'not-a-phone'},
          ),
        ),
        'provider1',
      );
      expect(badPhone.statusCode, HttpStatus.badRequest);
    });
  });
}
