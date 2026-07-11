import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/me/provider/index.dart' as me_provider;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

class _MockAppointments extends Mock implements AppointmentRepository {}

ProviderAccount _account({String? providerId}) => ProviderAccount(
  id: 'acc1',
  phoneNumber: '+2250700000009',
  businessName: 'Salon Awa',
  businessType: 'salon',
  createdAt: DateTime.utc(2026),
)..providerId = providerId;

void main() {
  group('GET /me/provider', () {
    final tokens = TokenService(secret: 'test-secret');
    late _MockProviderAuth auth;
    late _MockProviders providers;
    late _MockAppointments appointments;

    setUp(() {
      auth = _MockProviderAuth();
      providers = _MockProviders();
      appointments = _MockAppointments();
    });

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
      when(() => c.read<ProvidersRepository>()).thenReturn(providers);
      when(() => c.read<AppointmentRepository>()).thenReturn(appointments);
      when(() => c.read<ProviderAccountService>()).thenReturn(
        ProviderAccountService(
          auth,
          providers,
          appointments,
          const FakeStorageService(),
          client: MockClient((req) async => http.Response('', 204)),
        ),
      );
      when(
        () => c.read<SalonProvisioningService>(),
      ).thenReturn(SalonProvisioningService(providers, auth));
      return c;
    }

    Request req(String method, {String? token}) => Request(
      method,
      Uri.parse('http://localhost/me/provider'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, String role) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    test('linked provider → 200 {account, provider}', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'p1'));
      when(
        () => providers.byId('p1'),
      ).thenAnswer((_) async => {'id': 'p1', 'name': 'Salon Awa'});

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect((m['account'] as Map)['businessName'], 'Salon Awa');
      expect((m['provider'] as Map)['id'], 'p1');
    });

    test('anonymous → 401', () async {
      final res = await me_provider.onRequest(ctx(req('GET')));
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('non-provider role → 403', () async {
      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('u1', 'user'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('no linked salon → SELF-HEALS: a draft salon is created + linked '
        '(pro-salon-lifecycle.md §2)', () async {
      final account = _account(providerId: null);
      when(() => auth.accountById('acc1')).thenAnswer((_) async => account);
      final draft = {'id': 'p_new', 'name': 'Salon Awa', 'status': 'draft'};
      when(
        () => providers.createSalon(
          name: 'Salon Awa',
          category: 'salon',
          phoneNumber: '+2250700000009',
          address: null,
        ),
      ).thenAnswer((_) async => draft);
      when(() => auth.linkProvider('acc1', 'p_new')).thenAnswer((_) async {});
      when(() => providers.byId('p_new')).thenAnswer((_) async => draft);

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect((m['account'] as Map)['providerId'], 'p_new');
      expect((m['provider'] as Map)['status'], 'draft');
      verify(() => auth.linkProvider('acc1', 'p_new')).called(1);
    });

    test('DELETE erases the identity + unpublishes the salon (T53)', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'p1'));
      // Only past/settled bookings → the gate passes.
      when(() => appointments.listForProvider('p1')).thenAnswer(
        (_) async => [
          {
            'status': 'completed',
            'appointmentDate': '2026-01-01T09:00:00.000Z',
          },
          {'status': 'pending', 'appointmentDate': '2020-01-01T09:00:00.000Z'},
        ],
      );
      when(
        () => providers.setStatus('p1', 'draft'),
      ).thenAnswer((_) async => {'id': 'p1', 'status': 'draft'});
      when(() => auth.deleteAccount('acc1')).thenAnswer((_) async => true);

      final res = await me_provider.onRequest(
        ctx(req('DELETE', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.noContent);
      verify(() => providers.setStatus('p1', 'draft')).called(1);
      verify(() => auth.deleteAccount('acc1')).called(1);
    });

    test(
      'DELETE with FUTURE pending/confirmed bookings → 409 (settle first)',
      () async {
        when(
          () => auth.accountById('acc1'),
        ).thenAnswer((_) async => _account(providerId: 'p1'));
        final future = DateTime.now()
            .toUtc()
            .add(const Duration(days: 3))
            .toIso8601String();
        when(() => appointments.listForProvider('p1')).thenAnswer(
          (_) async => [
            {'status': 'confirmed', 'appointmentDate': future},
          ],
        );

        final res = await me_provider.onRequest(
          ctx(req('DELETE', token: tok('acc1', 'provider'))),
        );
        expect(res.statusCode, HttpStatus.conflict);
        verifyNever(() => providers.setStatus(any(), any()));
        verifyNever(() => auth.deleteAccount(any()));
      },
    );

    test('DELETE: consumer token → 403; anonymous → 401', () async {
      final asUser = await me_provider.onRequest(
        ctx(req('DELETE', token: tok('u1', 'user'))),
      );
      expect(asUser.statusCode, HttpStatus.forbidden);
      final anon = await me_provider.onRequest(ctx(req('DELETE')));
      expect(anon.statusCode, HttpStatus.unauthorized);
    });

    test('linked salon missing → 404', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'gone'));
      when(() => providers.byId('gone')).thenAnswer((_) async => null);
      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('unsupported verb → 405', () async {
      final res = await me_provider.onRequest(
        ctx(req('POST', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
