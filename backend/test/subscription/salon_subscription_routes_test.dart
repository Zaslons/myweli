import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

import '../../routes/admin/providers/[id]/subscription/paid.dart' as paid_route;
import '../../routes/providers/[id]/publish.dart' as publish_route;
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
    auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
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
    when(() => c.read<SalonProvisioningService>()).thenReturn(
      SalonProvisioningService(
        providers,
        auth,
        memberships,
        subscriptions: service,
      ),
    );
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
  group('PUT /providers/{id}/subscription — the demo lock (T69)', () {
    test('THE DEMO SALON → 403 demo_account_locked, no row written', () async {
      final demo = await providers.createSalon(
        name: 'Salon Démo MyWeli',
        category: 'salon',
        phoneNumber: '+2250700000100',
      );
      final id = demo['id'] as String;
      await memberships.ensureOwner(
        providerId: id,
        accountId: 'acc-demo',
        email: kDemoProviderEmail,
      );
      final res = await sub_route.onRequest(
        ctx(
          Request(
            'PUT',
            Uri.parse('http://localhost/providers/$id/subscription'),
            headers: {'Authorization': 'Bearer ${tok('acc-demo')}'},
            body: '{"tier": "reseau"}',
          ),
        ),
        id,
      );
      expect(res.statusCode, HttpStatus.forbidden);
      expect((await res.json() as Map)['error'], 'demo_account_locked');
      expect(await subs.byProvider(id), isNull);
    });
  });

  /// The companion path over the route (docs/design/pro-companion-path.md
  /// §3.1): publish starts the trial when the salon has no offer row.
  group('POST /providers/{id}/publish — the trial starts at publish', () {
    late String salonId;

    Future<void> complete(String id) => providers.updateProfile(id, {
      'description': 'desc',
      'address': 'Cocody',
      'commune': 'Cocody',
      'latitude': 5.3,
      'longitude': -4.0,
      'imageUrls': ['a', 'b', 'c'],
      'services': [
        {'id': 's1', 'name': 'A', 'active': true},
        {'id': 's2', 'name': 'B', 'active': true},
        {'id': 's3', 'name': 'C', 'active': true},
      ],
      'availability': {
        'weeklySchedule': {
          '0': [
            {'startTime': '09:00', 'endTime': '18:00'},
          ],
        },
      },
    });

    Future<Response> publish() => publish_route.onRequest(
      ctx(
        Request(
          'POST',
          Uri.parse('http://localhost/providers/$salonId/publish'),
          headers: {'Authorization': 'Bearer ${tok(ownerId)}'},
        ),
      ),
      salonId,
    );

    Future<Response> getSubscription() => sub_route.onRequest(
      ctx(req('GET', '/providers/$salonId/subscription', token: tok(ownerId))),
      salonId,
    );

    setUp(() async {
      final salon = await providers.createSalon(
        name: 'Salon Compagnon',
        category: 'salon',
        phoneNumber: '+2250500000052',
      );
      salonId = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: salonId,
        accountId: ownerId,
        email: 'own@x.pro',
      );
    });

    test(
      'no choice + complete → 200 active; GET → trial on pro, 90 days',
      () async {
        await complete(salonId);
        expect((await getSubscription()).statusCode, HttpStatus.notFound);

        final res = await publish();
        expect(res.statusCode, HttpStatus.ok);
        expect((await res.json() as Map)['status'], 'active');

        final got = await getSubscription();
        expect(got.statusCode, HttpStatus.ok);
        final state = await got.json() as Map;
        expect(state['status'], 'trial');
        expect(state['tier'], 'pro');
        final hoursLeft = DateTime.parse(
          state['trialEndsAt'] as String,
        ).difference(DateTime.now().toUtc()).inHours;
        expect(hoursLeft, inInclusiveRange(89 * 24, 90 * 24));
      },
    );

    test('incomplete → 409 incomplete, `offer` NOT among the keys, GET '
        'still 404', () async {
      final res = await publish();
      expect(res.statusCode, HttpStatus.conflict);
      final body = await res.json() as Map;
      expect(body['error'], 'incomplete');
      expect(body['missing'], isNot(contains('offer')));
      expect((await getSubscription()).statusCode, HttpStatus.notFound);
    });

    test('a SUSPENDED salon → 403 provider_suspended (not a 409 the app '
        'reads as a missing step); GET still 404, still suspended', () async {
      await complete(salonId);
      await providers.setStatus(salonId, 'suspended');

      final res = await publish();
      expect(res.statusCode, HttpStatus.forbidden);
      expect((await res.json() as Map)['error'], 'provider_suspended');
      expect((await getSubscription()).statusCode, HttpStatus.notFound);
      expect((await providers.byId(salonId))!['status'], 'suspended');
    });

    test('an EXPIRED offer → 409 with `offer` — no second trial', () async {
      await complete(salonId);
      final expiredEnd = DateTime.now().toUtc().subtract(
        const Duration(days: 100),
      );
      await subs.create(
        providerId: salonId,
        tier: 'pro',
        trialEndsAt: expiredEnd,
      );

      final res = await publish();
      expect(res.statusCode, HttpStatus.conflict);
      expect((await res.json() as Map)['missing'], ['offer']);
      expect((await subs.byProvider(salonId))!.trialEndsAt, expiredEnd);
    });
  });
}
