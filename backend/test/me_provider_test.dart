import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
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
    late InMemoryMembershipRepository memberships;

    setUp(() {
      auth = _MockProviderAuth();
      providers = _MockProviders();
      appointments = _MockAppointments();
      memberships = InMemoryMembershipRepository();
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
          memberships,
          client: MockClient((req) async => http.Response('', 204)),
        ),
      );
      when(
        () => c.read<SalonProvisioningService>(),
      ).thenReturn(SalonProvisioningService(providers, auth, memberships));
      when(
        () => c.read<MembershipService>(),
      ).thenReturn(MembershipService(memberships, auth));
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

    test('GUARD (access §2.3-1): an account with a MEMBERSHIP never gets a '
        'salon provisioned — its salon resolves via the membership', () async {
      final account = _account(providerId: null);
      when(() => auth.accountById('acc1')).thenAnswer((_) async => account);
      // The account is someone's team member (R2 shape: unlinked + a row).
      await memberships.ensureOwner(
        providerId: 'p_theirs',
        accountId: 'acc1',
        email: 'staff@test.pro',
      );
      when(
        () => providers.byId('p_theirs'),
      ).thenAnswer((_) async => {'id': 'p_theirs', 'name': 'Chez Awa'});

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      // No provisioning happened.
      verifyNever(
        () => providers.createSalon(
          name: any(named: 'name'),
          category: any(named: 'category'),
          phoneNumber: any(named: 'phoneNumber'),
          address: any(named: 'address'),
        ),
      );
      verifyNever(() => auth.linkProvider(any(), any()));
    });

    // ---- Membership block (module access R4a) -----------------------------

    test(
      'owner → membership {role: owner, full sorted capabilities}',
      () async {
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
        final m = (await res.json() as Map)['membership'] as Map;
        expect(m['role'], 'owner');
        final caps = (m['capabilities'] as List).cast<String>();
        expect(caps, contains('finances.view'));
        expect(caps, contains('members.manage'));
        expect(caps, contains('salon.publish'));
        expect(caps, List.of(caps)..sort()); // deterministic order
        expect(m.containsKey('artistId'), isFalse);
      },
    );

    test(
      'active MANAGER member → manager capabilities, no money caps',
      () async {
        when(
          () => auth.accountById('acc1'),
        ).thenAnswer((_) async => _account(providerId: null));
        final invited = await memberships.invite(
          providerId: 'p1',
          email: 'mgr@test.pro',
          role: 'manager',
          expiresAt: DateTime.now().add(const Duration(days: 7)),
        );
        await memberships.activate(invited.id, 'acc1');
        when(
          () => providers.byId('p1'),
        ).thenAnswer((_) async => {'id': 'p1', 'name': 'Salon Awa'});

        final res = await me_provider.onRequest(
          ctx(req('GET', token: tok('acc1', 'provider'))),
        );
        expect(res.statusCode, HttpStatus.ok);
        final m = (await res.json() as Map)['membership'] as Map;
        expect(m['role'], 'manager');
        final caps = (m['capabilities'] as List).cast<String>();
        expect(caps, contains('catalogue.manage'));
        expect(caps, isNot(contains('finances.view')));
        expect(caps, isNot(contains('members.manage')));
      },
    );

    test('active STAFF member → own caps only + artistId + artistName '
        'joined from the salon', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: null));
      final invited = await memberships.invite(
        providerId: 'p1',
        email: 'staff@test.pro',
        role: 'staff',
        artistId: 'a1',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(invited.id, 'acc1');
      when(() => providers.byId('p1')).thenAnswer(
        (_) async => {
          'id': 'p1',
          'name': 'Salon Awa',
          'artists': [
            {'id': 'a1', 'name': 'Awa'},
            {'id': 'a2', 'name': 'Fatou'},
          ],
        },
      );

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = (await res.json() as Map)['membership'] as Map;
      expect(m['role'], 'staff');
      expect((m['capabilities'] as List).cast<String>(), [
        'journal.manage.own',
        'journal.view.own',
      ]);
      expect(m['artistId'], 'a1');
      expect(m['artistName'], 'Awa');
    });

    test('REVOKED bare member → 403 not_a_member (the revoked-mid-session '
        'signal, §5.3) — an unlinked non-member stays forbidden', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: null));
      final invited = await memberships.invite(
        providerId: 'p1',
        email: 'ex@test.pro',
        role: 'manager',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(invited.id, 'acc1');
      await memberships.revoke(invited.id);

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
      expect((await res.json() as Map)['error'], 'not_a_member');
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
