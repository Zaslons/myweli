import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/accept.dart' as accept_route;
import '../../routes/appointments/[id]/no-show.dart' as no_show_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockNotifier extends Mock implements BookingNotifier {}

void main() {
  setUpAll(() => registerFallbackValue(MessageTemplate.bookingConfirmed));
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late ProAppointmentService pro;

  late String accountForP1; // provider account linked to provider1
  late String accountForP2; // linked to provider2
  late String accountUnlinked; // no providerId

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    pro = ProAppointmentService(providerAuth, appts);

    accountForP1 = (await providerAuth.register(
      phoneNumber: '+2250500000001',
      businessName: 'Salon One',
      businessType: 'salon',
      providerId: 'provider1',
    )).provider!.id;
    accountForP2 = (await providerAuth.register(
      phoneNumber: '+2250500000002',
      businessName: 'Salon Two',
      businessType: 'salon',
      providerId: 'provider2',
    )).provider!.id;
    accountUnlinked = (await providerAuth.register(
      phoneNumber: '+2250500000003',
      businessName: 'Unlinked',
      businessType: 'salon',
    )).provider!.id;
  });

  Future<String> seedAppt({String status = 'pending'}) async {
    final created = await appts.create({
      'id': 'appt_${DateTime.now().microsecondsSinceEpoch}',
      'userId': 'user_X',
      'providerId': 'provider1',
      'serviceIds': ['service1'],
      'appointmentDate': DateTime.now()
          .toUtc()
          .add(const Duration(days: 2))
          .toIso8601String(),
      'status': status,
    });
    return created!['id'] as String;
  }

  group('ProAppointmentService', () {
    test('accept pending → confirmed → complete; no-show path', () async {
      final id = await seedAppt();
      expect(
        (await pro.accept(id, accountForP1)).appointment!['status'],
        'confirmed',
      );
      expect(
        (await pro.complete(id, accountForP1)).appointment!['status'],
        'completed',
      );

      final id2 = await seedAppt();
      expect(
        (await pro.noShow(id2, accountForP1)).appointment!['status'],
        'noShow',
      );
    });

    test('state machine guards', () async {
      // accept only from pending
      final confirmed = await seedAppt(status: 'confirmed');
      expect(
        (await pro.accept(confirmed, accountForP1)).error,
        'invalid_state',
      );
      // complete only from confirmed (a pending booking can't be completed)
      final pending = await seedAppt();
      expect(
        (await pro.complete(pending, accountForP1)).error,
        'invalid_state',
      );
    });

    test(
      'ownership: another salon / an unlinked account → forbidden',
      () async {
        final id = await seedAppt();
        expect((await pro.accept(id, accountForP2)).error, 'forbidden');
        expect((await pro.accept(id, accountUnlinked)).error, 'forbidden');
        expect((await pro.accept('nope', accountForP1)).error, 'not_found');
      },
    );
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ProAppointmentService>()).thenReturn(pro);
      final notifier = _MockNotifier();
      when(() => notifier.notify(any(), any())).thenAnswer((_) async {});
      when(() => context.read<BookingNotifier>()).thenReturn(notifier);
      return context;
    }

    Request post(String path, {String? token}) => Request.post(
      Uri.parse('http://localhost$path'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String providerToken(String accountId) =>
        tokens.issueAccessToken(subject: accountId, role: 'provider').token;

    test(
      'accept: 401 anon; 403 consumer; 403 other salon; 200 owner',
      () async {
        final id = await seedAppt();

        expect(
          (await accept_route.onRequest(ctx(post('/x')), id)).statusCode,
          HttpStatus.unauthorized,
        );

        final consumer = tokens
            .issueAccessToken(subject: 'user_X', role: 'user')
            .token;
        expect(
          (await accept_route.onRequest(
            ctx(post('/x', token: consumer)),
            id,
          )).statusCode,
          HttpStatus.forbidden,
        );

        expect(
          (await accept_route.onRequest(
            ctx(post('/x', token: providerToken(accountForP2))),
            id,
          )).statusCode,
          HttpStatus.forbidden,
        );

        final ok = await accept_route.onRequest(
          ctx(post('/x', token: providerToken(accountForP1))),
          id,
        );
        expect(ok.statusCode, HttpStatus.ok);
        expect((await ok.json() as Map)['status'], 'confirmed');
      },
    );

    test('no-show route is provider-gated + works for the owner', () async {
      final id = await seedAppt();
      final res = await no_show_route.onRequest(
        ctx(post('/x', token: providerToken(accountForP1))),
        id,
      );
      expect(res.statusCode, HttpStatus.ok);
      expect((await res.json() as Map)['status'], 'noShow');
    });
  });
}
