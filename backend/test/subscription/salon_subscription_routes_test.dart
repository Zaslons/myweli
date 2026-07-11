import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

import '../../routes/admin/providers/[id]/subscription/paid.dart' as paid_route;
import '../../routes/providers/[id]/subscription.dart' as sub_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// R2a route handlers: the owner's GET/PUT + the audited admin paid action
/// (threat T54 — clients can never flip billing state).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository memberships;
  late InMemorySalonSubscriptionRepository subs;
  late InMemoryProvidersRepository providers;
  late InMemoryAuditLogRepository audit;
  late SalonSubscriptionService service;
  late String ownerId;

  setUp(() async {
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    memberships = InMemoryMembershipRepository();
    subs = InMemorySalonSubscriptionRepository();
    providers = InMemoryProvidersRepository();
    audit = InMemoryAuditLogRepository();
    service = SalonSubscriptionService(
      subs,
      MembershipService(memberships, auth),
      memberships,
      providers,
      auth,
    );
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250500000051',
      email: 'own@x.pro',
      authProvider: 'google',
      googleSub: 'sub-o',
      providerId: 'p1',
    );
    ownerId = reg.provider!.id;
    await memberships.ensureOwner(
      providerId: 'p1',
      accountId: ownerId,
      email: 'own@x.pro',
    );
  });

  RequestContext ctx(Request request) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(request);
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<SalonSubscriptionService>()).thenReturn(service);
    when(
      () => c.read<MembershipService>(),
    ).thenReturn(MembershipService(memberships, auth));
    when(() => c.read<AdminProviderService>()).thenReturn(
      AdminProviderService(
        providers,
        InMemoryAppointmentRepository(),
        audit,
        service,
      ),
    );
    return c;
  }

  Request req(String method, String path, {String? token, Object? body}) =>
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
        body: body == null ? null : '{"tier": "pro"}',
      );

  String tok(String sub, {String role = 'provider'}) =>
      tokens.issueAccessToken(subject: sub, role: role).token;

  group('GET/PUT /providers/{id}/subscription', () {
    test('setup state → GET 404; PUT pro → 200 trial; GET → 200', () async {
      final missing = await sub_route.onRequest(
        ctx(req('GET', '/providers/p1/subscription', token: tok(ownerId))),
        'p1',
      );
      expect(missing.statusCode, HttpStatus.notFound);

      final put = await sub_route.onRequest(
        ctx(
          Request(
            'PUT',
            Uri.parse('http://localhost/providers/p1/subscription'),
            headers: {'Authorization': 'Bearer ${tok(ownerId)}'},
            body: '{"tier": "business"}',
          ),
        ),
        'p1',
      );
      expect(put.statusCode, HttpStatus.ok);
      final state = await put.json() as Map;
      expect(state['tier'], 'business');
      expect(state['status'], 'trial');

      final got = await sub_route.onRequest(
        ctx(req('GET', '/providers/p1/subscription', token: tok(ownerId))),
        'p1',
      );
      expect(got.statusCode, HttpStatus.ok);
    });

    test('bad tier → 400; anon → 401; consumer/other salon → 403; '
        'DELETE → 405', () async {
      final bad = await sub_route.onRequest(
        ctx(
          Request(
            'PUT',
            Uri.parse('http://localhost/providers/p1/subscription'),
            headers: {'Authorization': 'Bearer ${tok(ownerId)}'},
            body: '{"tier": "gold"}',
          ),
        ),
        'p1',
      );
      expect(bad.statusCode, HttpStatus.badRequest);

      final anon = await sub_route.onRequest(
        ctx(req('GET', '/providers/p1/subscription')),
        'p1',
      );
      expect(anon.statusCode, HttpStatus.unauthorized);

      final consumer = await sub_route.onRequest(
        ctx(
          req(
            'GET',
            '/providers/p1/subscription',
            token: tok('u1', role: 'user'),
          ),
        ),
        'p1',
      );
      expect(consumer.statusCode, HttpStatus.forbidden);

      final foreign = await sub_route.onRequest(
        ctx(req('GET', '/providers/p9/subscription', token: tok(ownerId))),
        'p9',
      );
      expect(foreign.statusCode, HttpStatus.forbidden);

      final wrongMethod = await sub_route.onRequest(
        ctx(req('DELETE', '/providers/p1/subscription', token: tok(ownerId))),
        'p1',
      );
      expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /admin/providers/{id}/subscription/paid', () {
    test(
      'records the payment + audits; bad months → 400; unknown → 404',
      () async {
        await service.chooseOffer(ownerId, 'p1', 'pro');

        final ok = await paid_route.onRequest(
          ctx(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/admin/providers/p1/subscription/paid',
              ),
              headers: {
                'Authorization': 'Bearer ${tok('adm1', role: 'admin')}',
              },
              body: '{"months": 3}',
            ),
          ),
          'p1',
        );
        expect(ok.statusCode, HttpStatus.ok);
        final state = await ok.json() as Map;
        expect(state['status'], 'paid');
        final entries = await audit.list();
        expect(entries.items.single['action'], 'subscription.paid');

        final bad = await paid_route.onRequest(
          ctx(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/admin/providers/p1/subscription/paid',
              ),
              headers: {
                'Authorization': 'Bearer ${tok('adm1', role: 'admin')}',
              },
              body: '{"months": 99}',
            ),
          ),
          'p1',
        );
        expect(bad.statusCode, HttpStatus.badRequest);

        final missing = await paid_route.onRequest(
          ctx(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/admin/providers/nope/subscription/paid',
              ),
              headers: {
                'Authorization': 'Bearer ${tok('adm1', role: 'admin')}',
              },
              body: '{"months": 1}',
            ),
          ),
          'nope',
        );
        expect(missing.statusCode, HttpStatus.notFound);
      },
    );
  });
}
